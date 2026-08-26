`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// Kyber_System_Top.sv — Top-level integration module
//
// Pipeline: RO_PUF → Fuzzy Extractor → Keccak KDF → Kyber Server
// Control: PC (Server) ↔ UART ↔ FPGA (Client)
//
// Commands:
//   0x01 = ENROLL: Read PUF → Generate Helper Data → Send to PC
//   0x02 = RECONSTRUCT: Receive Helper Data → Recover Key → Run Kyber
//-----------------------------------------------------------------------------

module Kyber_System_Top(
    input  wire CLK100MHZ,
    
    // Use Switch 0 for active-low reset
    input  wire [1:0] SW,
    
    // UART interface to PC
    input  wire UART_RXD,
    output wire UART_TXD,
    
    // Kyber Interface (Internal to avoid IO placement errors on Arty A7)
    // We will use 2 LEDs to output the status
    output wire [1:0] LED
);

    wire clk = CLK100MHZ;
    
    // ==========================================
    // Power-On Reset (POR) — tự động nhả reset sau khi FPGA boot
    // Giữ reset 65536 cycles (~655µs @ 100MHz), sau đó tự động RUN.
    // SW[0] = 0 (down) sẽ ép reset thủ công bất kỳ lúc nào.
    // ==========================================
    reg [15:0] por_cnt = 0;
    reg        por_done = 0;
    always @(posedge clk) begin
        if (!por_done) begin
            por_cnt  <= por_cnt + 1'b1;
            por_done <= (por_cnt == 16'hFFFF);
        end
    end
    // rst_n = 1 (run) khi POR xong VÀ SW[0] = 1 (hoặc không cần gạt)
    // Nếu muốn chạy tự động mà không cần gạt SW: bỏ "&& SW[0]"
    wire rst_n = por_done; // Auto-run after POR, SW[0] freed for other use
    wire rx = UART_RXD;
    wire tx;
    assign UART_TXD = tx;

    // Shared Secret Output (Internal)
    (* keep = "true" *) wire [255:0] shared_secret_K;
    
    // LED[0]: UART TX Active
    // LED[1]: XOR reduction of Kyber Shared Secret (to prevent logic optimization)
    assign LED[0] = tx_active;
    assign LED[1] = ^shared_secret_K;

    // ==========================================
    // 1. RISC-V SoC Core (PicoRV32 + Firmware + Peripherals)
    // ==========================================
    wire tx_active;
    wire puf_start_r, fe_start_r, fe_mode_r, kdf_start_r;
    wire puf_done, fe_done, fe_success, kdf_done;
    // SoC-FE helper data connections
    wire [263:0] helper_soc_to_fe; // From UART to FE
    wire [263:0] helper_fe_to_soc; // From FE to UART
    
    riscv_soc #(.CLKS_PER_BIT(434)) u_soc (
        .clk(clk),
        .rstn(rst_n),
        .rx(rx),
        .tx(tx),
        .tx_active(tx_active),
        .puf_start(puf_start_r),
        .fe_start(fe_start_r),
        .fe_mode(fe_mode_r),
        .kdf_start(kdf_start_r),
        .puf_done(puf_done),
        .fe_done(fe_done),
        .fe_success(fe_success),
        .kdf_done(kdf_done),
        .helper_out(helper_soc_to_fe),
        .helper_in(helper_fe_to_soc),
        .kdf_seed(kyber_seed)
    );

    wire [263:0] puf_resp;
    wire [191:0] fe_key;
    wire [511:0] kyber_seed;

    // ==========================================
    // 4. RO PUF Module
    // ==========================================
    kp_puf_top u_puf (
        .clk(clk),
        .rst_n(rst_n),
        .start(puf_start_r),
        .seed(8'h42),
        .busy(),
        .done(puf_done),
        .response(puf_resp)
    );

    // ==========================================
    // 5. Fuzzy Extractor (BCH)
    // ==========================================
    fuzzy_extractor u_fe (
        .clk(clk),
        .rst_n(rst_n),
        .start(fe_start_r),
        .mode(fe_mode_r),
        .response_in(puf_resp),
        .helper_in(helper_soc_to_fe),
        .helper_out(helper_fe_to_soc),
        .key_out(fe_key),
        .busy(),
        .done(fe_done),
        .success(fe_success)
    );

    // ==========================================
    // 6. Keccak KDF (192-bit -> 512-bit)
    // ==========================================
    kdf_keccak u_kdf (
        .clk(clk),
        .rst_n(rst_n),
        .start(kdf_start_r),
        .key_in(fe_key),
        .done(kdf_done),
        .seed_out(kyber_seed)
    );

    // ==========================================
    // 7. Kyber Server Core (Post-Quantum) - BYPASSED FOR A7-35T TESTING
    // ==========================================
    // Kyber_Server u_kyber_server (
    //     .clk(clk),
    //     .rst(~rst_n),
    //     .start(kyber_start_r),
    //     .wen(1'b0),
    //     .k(3'd2),
    //     .ready_c(1'b1),
    //     .req_pk(req_pk),
    //     .din(din_pk),
    //     .ready_pk(ready_pk),
    //     .req_c(req_c),
    //     .valid(valid_c),
    //     .dout(dout_c),
    //     .seed_d(kyber_seed[255:0]),
    //     .seed_z(kyber_seed[511:256]),
    //     .K(shared_secret_K)
    // );
    
    // Kyber bypassed: map KDF output directly to shared_secret for LED[1]
    assign shared_secret_K = kyber_seed[255:0];

endmodule
