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

module Kyber_System_Top #(
    // Diagnostic research image: anchor provisions once from the first
    // enrollment and locks.  An operational build must set this to 0 and
    // provision the ROM anchor (rtl/top/edge_kcv_anchor_rom.vh); with
    // ROM_VALID=0 the elaboration guard below fails.
    parameter bit DIAGNOSTIC_ANCHOR = 1'b1
)(
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
    // Giữ reset 65536 cycles (~1.31 ms @ 50 MHz), sau đó tự động RUN.
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
    wire tx_active;
    wire kyber_done;
    wire [263:0] puf_resp;
    wire [191:0] fe_key;
    wire [511:0] kyber_seed;
    assign UART_TXD = tx;

    // Shared Secret Output (Internal)
    (* keep = "true" *) wire [255:0] shared_secret_K;
    
    // LED[0]: UART TX Active
    // LED[1]: Kyber completion status. Never expose a function of secret data.
    assign LED[0] = tx_active;
    assign LED[1] = kyber_done;

    // ==========================================
    // 1. RISC-V SoC Core (PicoRV32 + Firmware + Peripherals)
    // ==========================================
    wire puf_start_r, fe_start_r, fe_mode_r, kdf_start_r;
    wire secure_zeroize;
    wire puf_done, fe_done, fe_success, kdf_done;
    // SoC-FE helper data connections
    wire [263:0] helper_soc_to_fe; // From UART to FE
    wire [263:0] helper_fe_to_soc; // From FE to UART
    // KCV same-root control/status (engine taps fe_key directly).
    wire        kcv_start;
    wire [223:0] kcv_ref;
    wire [55:0]  kcv_ctx;
    wire        kcv_done;
    wire        kcv_pass;
    wire [223:0] kcv_out;
    wire [223:0] trusted_kcv_ref;
    wire         trusted_kcv_valid;
    wire         anchor_provision = kcv_done && !fe_mode_r && (|kcv_out);
    // Helper KCV shadow from the SoC record registers: comparison-only.  A
    // mismatch fails the gate; it can never replace the trusted anchor.
    wire         helper_kcv_mismatch = (kcv_ref != trusted_kcv_ref);
    
    // The accepted FPGA research image keeps internal key observability for
    // legacy diagnostics. UART release firmware still withholds the secret.
    // ASIC/production integrations use the locked default instead.
    riscv_soc #(
        .CLKS_PER_BIT(434),
        .EXPOSE_KYBER_SECRETS(1),
        .SECURE_KYBER_SCRUB(1),
        .DIAGNOSTIC_PROVISION(DIAGNOSTIC_ANCHOR)
    ) u_soc (
        .clk(clk),
        .rstn(rst_n),
        .rx(rx),
        .tx(tx),
        .tx_active(tx_active),
        .kyber_done(kyber_done),
        .kyber_shared_secret(shared_secret_K),
        .puf_start(puf_start_r),
        .fe_start(fe_start_r),
        .fe_mode(fe_mode_r),
        .kdf_start(kdf_start_r),
        .secure_zeroize(secure_zeroize),
        .puf_done(puf_done),
        .fe_done(fe_done),
        .fe_success(fe_success),
        .kdf_done(kdf_done),
        .helper_out(helper_soc_to_fe),
        .helper_in(helper_fe_to_soc),
        .kdf_seed(kyber_seed),
        .kcv_start(kcv_start),
        .kcv_ref(kcv_ref),
        .kcv_ctx(kcv_ctx),
        .kcv_done(kcv_done),
        .kcv_pass(kcv_pass && !helper_kcv_mismatch),
        .kcv_out(kcv_out),
        .trusted_kcv_valid_i(trusted_kcv_valid),
        .trusted_kcv_ref_i(trusted_kcv_ref)
    );

    // ==========================================
    // 4. RO PUF Module
    // ==========================================
    kp_puf_top u_puf (
        .clk(clk),
        .rst_n(rst_n),
        .zeroize(secure_zeroize),
        .start(puf_start_r),
        .seed(8'h42),
        .busy(),
        .done(puf_done),
        .response(puf_resp),
        .telemetry_valid(), .telemetry_index(), .telemetry_challenge(),
        .telemetry_count0(), .telemetry_count1(), .telemetry_winner()
    );

    // ==========================================
    // 5. Fuzzy Extractor (BCH)
    // ==========================================
    fuzzy_extractor u_fe (
        .clk(clk),
        .rst_n(rst_n),
        .zeroize(secure_zeroize),
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
        .zeroize(secure_zeroize),
        .start(kdf_start_r),
        .key_in(fe_key),
        .done(kdf_done),
        .seed_out(kyber_seed)
    );

    // Same-root KCV engine.  Taps the FE key in place; the key never reaches
    // the CPU or MMIO.  Firmware supplies the public reference/context and
    // reads back done/pass (verify) or the public digest (enroll).
    edge_root_binding u_kcv (
        .clk(clk),
        .rst_n(rst_n),
        .zeroize(secure_zeroize),
        .start(kcv_start),
        .root_key(fe_key),
        .kcv_ctx(kcv_ctx),
        .kcv_ref(trusted_kcv_ref),
        .busy(),
        .done(kcv_done),
        .kcv_pass(kcv_pass),
        .kcv_out(kcv_out)
    );

    // The full Kyber-512 Server/Client loopback is instantiated inside
    // riscv_soc and controlled by firmware through its AXI-Lite registers.


    // Trusted KCV anchor.  Diagnostic images provision once from the first
    // enrollment digest and lock; operational images must use the ROM anchor.
    `include "edge_kcv_anchor_rom.vh"
    edge_kcv_anchor #(
        .DIAGNOSTIC(DIAGNOSTIC_ANCHOR),
        .ROM_REF(EDGE_KCV_ROM_REF),
        .ROM_VALID(EDGE_KCV_ROM_VALID)
    ) u_kcv_anchor (
        .clk(clk),
        .rst_n(rst_n),
        .zeroize(secure_zeroize),
        .provision(DIAGNOSTIC_ANCHOR && anchor_provision),
        .provision_ref(kcv_out),
        .provision_valid(|kcv_out),
        .trusted_kcv_ref(trusted_kcv_ref),
        .trusted_kcv_valid(trusted_kcv_valid),
        .anchor_locked(),
        .anchor_diagnostic()
    );

`ifndef SYNTHESIS
    initial begin
        if (!DIAGNOSTIC_ANCHOR && !EDGE_KCV_ROM_VALID)
            $fatal(1, "operational KCV anchor has no provisioned ROM reference");
    end
`endif
endmodule
