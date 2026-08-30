module soc_peripherals #(
    parameter CLKS_PER_BIT = 868
)(
    input clk,
    input rstn,
    
    // PicoRV32 memory interface
    input         mem_valid,
    output reg    mem_ready,
    input  [31:0] mem_addr,
    input  [31:0] mem_wdata,
    input  [ 3:0] mem_wstrb,
    output reg [31:0] mem_rdata,

    // UART external ports
    input  rx,
    output tx,
    output tx_active,

    // Signals to/from PUF, FE, KDF
    output reg puf_start,
    output reg fe_start,
    output reg fe_mode,
    output reg kdf_start,

    input puf_done,
    input fe_done,
    input fe_success,
    input kdf_done,
    input [511:0] kdf_seed,

    output [263:0] helper_out_data, // Helper data from UART to FE
    input  [263:0] helper_in_data   // Helper data from FE to UART
);

    // Memory-mapped address decoder. Declare these before all logic that
    // consumes them so older Vivado versions do not create implicit nets.
    wire sel_uart_data = (mem_addr == 32'h10000000);
    wire sel_uart_stat = (mem_addr == 32'h10000004);
    wire sel_sys_ctrl  = (mem_addr == 32'h10000008);
    wire sel_helper    = (mem_addr >= 32'h10000010 && mem_addr <= 32'h10000030);
    wire [3:0] helper_idx = (mem_addr - 32'h10000010) >> 2;
    wire sel_kdf       = (mem_addr >= 32'h10000040 && mem_addr <= 32'h1000007C);
    wire [3:0] kdf_idx = (mem_addr - 32'h10000040) >> 2;

    // ==========================================
    // UART Instantiation
    // ==========================================
    wire rx_dv;
    wire [7:0] rx_byte;
    wire tx_done;
    reg tx_dv;
    reg [7:0] tx_byte;

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
        .i_Clock(clk),
        .i_Rst(~rstn),
        .i_Rx_Serial(rx),
        .o_Rx_DV(rx_dv),
        .o_Rx_Byte(rx_byte)
    );
    
    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .i_Clock(clk),
        .i_Rst(~rstn),
        .i_Tx_DV(tx_dv),
        .i_Tx_Byte(tx_byte),
        .o_Tx_Active(tx_active),
        .o_Tx_Serial(tx),
        .o_Tx_Done(tx_done)
    );

    // UART RX FIFO/Buffer (15-byte usable capacity) with overflow protection
    reg [7:0] rx_fifo [0:15];
    reg [3:0] rx_wr_ptr;
    reg [3:0] rx_rd_ptr;
    reg       rx_overflow;
    wire rx_empty = (rx_wr_ptr == rx_rd_ptr);
    wire rx_full  = ((rx_wr_ptr + 4'd1) == rx_rd_ptr);
    
    always @(posedge clk) begin
        if (!rstn) begin
            rx_wr_ptr <= 0;
            rx_rd_ptr <= 0;
            rx_overflow <= 0;
        end else begin
            if (rx_dv && !rx_full) begin
                rx_fifo[rx_wr_ptr] <= rx_byte;
                rx_wr_ptr <= rx_wr_ptr + 1;
            end
            if (rx_dv && rx_full)
                rx_overflow <= 1;
            // Writing UART_STATUS[2]=1 acknowledges/clears overflow.
            if (mem_valid && !mem_ready && (|mem_wstrb) && sel_uart_stat && mem_wdata[2])
                rx_overflow <= 0;
            if (mem_valid && mem_ready && (mem_addr == 32'h10000000) && (mem_wstrb == 0)) begin
                // Read from UART advances FIFO read pointer
                if (mem_rdata[8]) rx_rd_ptr <= rx_rd_ptr + 1;
            end
        end
    end

    // ==========================================
    // Helper Data Registers (9 words = 36 bytes)
    // ==========================================
    reg [31:0] helper_reg [0:8];
    
    assign helper_out_data = {
        helper_reg[8][7:0], helper_reg[7], helper_reg[6], helper_reg[5], helper_reg[4],
        helper_reg[3], helper_reg[2], helper_reg[1], helper_reg[0]
    };

    wire [31:0] helper_in_words [0:8];
    assign helper_in_words[0] = helper_in_data[31:0];
    assign helper_in_words[1] = helper_in_data[63:32];
    assign helper_in_words[2] = helper_in_data[95:64];
    assign helper_in_words[3] = helper_in_data[127:96];
    assign helper_in_words[4] = helper_in_data[159:128];
    assign helper_in_words[5] = helper_in_data[191:160];
    assign helper_in_words[6] = helper_in_data[223:192];
    assign helper_in_words[7] = helper_in_data[255:224];
    assign helper_in_words[8] = {24'd0, helper_in_data[263:256]};

    // ==========================================
    // Sticky Done Latches
    // Hardware done signals are 1-cycle pulses.
    // CPU polls at ~2-4 cycles per read. Without latching, CPU misses the pulse → deadlock!
    // Latch is SET by hardware pulse, CLEARED when CPU writes SYS_CTRL (starts next op).
    // ==========================================
    reg puf_done_sticky;
    reg fe_done_sticky;
    reg fe_success_sticky;
    reg kdf_done_sticky;

    always @(posedge clk) begin
        if (!rstn) begin
            puf_done_sticky   <= 0;
            fe_done_sticky    <= 0;
            fe_success_sticky <= 0;
            kdf_done_sticky   <= 0;
        end else begin
            // Latch on hardware pulse
            if (puf_done)   puf_done_sticky   <= 1;
            if (fe_done)    fe_done_sticky    <= 1;
            if (fe_done && fe_success) fe_success_sticky <= 1;
            if (kdf_done)   kdf_done_sticky   <= 1;

            // Clear ALL latches when CPU writes to SYS_CTRL (starting a new operation)
            if (mem_valid && !mem_ready && (|mem_wstrb) && sel_sys_ctrl) begin
                puf_done_sticky   <= 0;
                fe_done_sticky    <= 0;
                fe_success_sticky <= 0;
                kdf_done_sticky   <= 0;
            end
        end
    end

    always @(posedge clk) begin
        if (!rstn) begin
            mem_ready <= 0;
            mem_rdata <= 0;
            tx_dv <= 0;
            tx_byte <= 0;
            puf_start <= 0;
            fe_start <= 0;
            kdf_start <= 0;
            fe_mode <= 0;
            for (int i=0; i<9; i++) helper_reg[i] <= 0;
        end else begin
            mem_ready <= 0;
            tx_dv <= 0;
            puf_start <= 0;
            fe_start <= 0;
            kdf_start <= 0;

            if (mem_valid && !mem_ready) begin
                mem_ready <= 1;
                
                // --- WRITE ---
                if (|mem_wstrb) begin
                    if (sel_uart_data) begin
                        tx_byte <= mem_wdata[7:0];
                        tx_dv <= 1;
                    end else if (sel_sys_ctrl) begin
                        puf_start <= mem_wdata[0];
                        fe_start  <= mem_wdata[1];
                        fe_mode   <= mem_wdata[2];
                        kdf_start <= mem_wdata[3];
                    end else if (sel_helper) begin
                        helper_reg[helper_idx] <= mem_wdata;
                    end
                end 
                // --- READ ---
                else begin
                    if (sel_uart_data) begin
                        mem_rdata <= {23'd0, !rx_empty, rx_fifo[rx_rd_ptr]};
                    end else if (sel_uart_stat) begin
                        mem_rdata <= {29'd0, rx_overflow, tx_done, tx_active};
                    end else if (sel_sys_ctrl) begin
                        // Return STICKY latched status bits
                        mem_rdata <= {28'd0, kdf_done_sticky, fe_success_sticky, fe_done_sticky, puf_done_sticky};
                    end else if (sel_helper) begin
                        mem_rdata <= helper_in_words[helper_idx];
                    end else if (sel_kdf) begin
                        case(kdf_idx)
                            4'd0: mem_rdata <= kdf_seed[31:0];
                            4'd1: mem_rdata <= kdf_seed[63:32];
                            4'd2: mem_rdata <= kdf_seed[95:64];
                            4'd3: mem_rdata <= kdf_seed[127:96];
                            4'd4: mem_rdata <= kdf_seed[159:128];
                            4'd5: mem_rdata <= kdf_seed[191:160];
                            4'd6: mem_rdata <= kdf_seed[223:192];
                            4'd7: mem_rdata <= kdf_seed[255:224];
                            4'd8: mem_rdata <= kdf_seed[287:256];
                            4'd9: mem_rdata <= kdf_seed[319:288];
                            4'd10: mem_rdata <= kdf_seed[351:320];
                            4'd11: mem_rdata <= kdf_seed[383:352];
                            4'd12: mem_rdata <= kdf_seed[415:384];
                            4'd13: mem_rdata <= kdf_seed[447:416];
                            4'd14: mem_rdata <= kdf_seed[479:448];
                            4'd15: mem_rdata <= kdf_seed[511:480];
                        endcase
                    end else begin
                        mem_rdata <= 32'h0;
                    end
                end
            end
        end
    end

endmodule
