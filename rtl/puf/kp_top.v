`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// kp_top — Arty A7-35T board wrapper for kp_puf_top (264-bit RO-PUF)
//
// UART protocol (115200 8N1):
//   PC -> FPGA : 1 byte seed  (LFSR challenge seed)
//   FPGA -> PC : 1 byte seed echo + 33 bytes response (264 bits)
//
// SW[1:0]:
//   00 : raw 264-bit response (measurement mode)
//   others : reserved (same behavior for now)
//////////////////////////////////////////////////////////////////////////////////

module kp_top(
    input CLK100MHZ,
    input [1:0] SW,
    input UART_RXD,
    output UART_TXD,
    output [1:0] LED,
    output LED17_R
    );

    // ---- Reset / clock ----
    wire reset;
    reg [7:0] por_cnt;
    reg por_done;
    assign reset = ~por_done;
    always @(posedge CLK100MHZ) begin
        if (!por_done) begin
            por_cnt <= por_cnt + 1;
            if (por_cnt == 8'hFF) por_done <= 1'b1;
        end
    end

    // DEBUG: blink LED17_R to prove clock alive
    reg [23:0] dbg_cnt = 0;
    reg dbg_blink = 0;
    always @(posedge CLK100MHZ) begin
        dbg_cnt <= dbg_cnt + 1;
        if (dbg_cnt == 24'hFFFFFF) dbg_blink <= ~dbg_blink;
    end

    // ---- UART wires ----
    wire uart_done, tx_DV, rx_DV;
    wire [7:0] tx_byte;
    wire [7:0] rx_byte;

    // ---- kp_puf_top ----
    wire puf_start, puf_done;
    wire [7:0] puf_seed;
    wire [263:0] puf_response;
    reg [263:0] response_latch;

    wire [7:0] bridge_seed;
    wire bridge_start;

    assign puf_seed   = bridge_seed;
    assign puf_start  = bridge_start;

    kp_puf_top #(
        .BIT_COUNT(264),
        .REF_CYCLES(4095)
    ) kp_puf_inst (
        .clk      (CLK100MHZ),
        .rst_n    (por_done),
        .start    (puf_start),
        .seed     (puf_seed),
        .busy     (),
        .done     (puf_done),
        .response (puf_response)
    );

    // Latch response when PUF finishes (done is 1 cycle at S_DONE)
    always @(posedge CLK100MHZ)
        if (puf_done) response_latch <= puf_response;

    // ---- UART controller bridge ----
    kp_uart_ctrl bridge (
        .clk          (CLK100MHZ),
        .reset        (reset),
        .rx_byte      (rx_byte),
        .rx_DV        (rx_DV),
        .response     (response_latch),
        .puf_done     (puf_done),
        .uart_done    (uart_done),
        .seed         (bridge_seed),
        .start        (bridge_start),
        .tx_byte      (tx_byte),
        .tx_DV        (tx_DV)
    );

    uart_tx #(868) MyTX(
        .i_Clock     (CLK100MHZ),
        .i_Tx_DV     (tx_DV),
        .i_Tx_Byte   (tx_byte),
        .o_Tx_Active (),
        .o_Tx_Serial (UART_TXD),
        .o_Tx_Done   (uart_done)
    );

    uart_rx #(868) MyRX(
        .i_Clock    (CLK100MHZ),
        .i_Rx_Serial(UART_RXD),
        .o_Rx_DV    (rx_DV),
        .o_Rx_Byte  (rx_byte)
    );

    // ---- LEDs ----
    reg dbg_done_latch = 0;
    always @(posedge CLK100MHZ)
        if (puf_done) dbg_done_latch <= 1'b1;

    assign LED[0] = dbg_done_latch;
    assign LED[1] = dbg_blink;
    assign LED17_R = dbg_blink;

endmodule