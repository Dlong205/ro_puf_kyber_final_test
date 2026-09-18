`timescale 1ns / 1ps

// Isolated 496-candidate RO-PUF characterization image.  This top exports
// physical fingerprint telemetry and must never be used as a release image.
module Puf_AllPairs_Characterization_Top #(
    parameter integer UART_CLKS_PER_BIT = 434
)(
    input  wire       CLK100MHZ,
    input  wire [1:0] SW,
    input  wire       UART_RXD,
    output wire       UART_TXD,
    output wire [1:0] LED
);
    wire clk = CLK100MHZ;

    reg [15:0] por_cnt = 16'd0;
    reg por_done = 1'b0;
    always @(posedge clk) begin
        if (!por_done) begin
            por_cnt <= por_cnt + 1'b1;
            por_done <= (por_cnt == 16'hFFFF);
        end
    end

    wire puf_start, puf_busy, puf_done, tx_active;
    wire [495:0] puf_response;
    wire telemetry_valid;
    wire [8:0] telemetry_index;
    wire [4:0] telemetry_pair_a, telemetry_pair_b;
    wire [31:0] telemetry_count0, telemetry_count1;
    wire telemetry_winner;

    // The instance/generate names intentionally match the release hierarchy
    // so the established 128-LUT LOC/BEL map remains auditable.
    kp_puf_allpairs_top #(.USE_PRESCALER(0)) u_puf (
        .clk(clk), .rst_n(por_done), .zeroize(1'b0), .start(puf_start),
        .busy(puf_busy), .done(puf_done), .response(puf_response),
        .telemetry_valid(telemetry_valid),
        .telemetry_index(telemetry_index),
        .telemetry_pair_a(telemetry_pair_a),
        .telemetry_pair_b(telemetry_pair_b),
        .telemetry_count0(telemetry_count0),
        .telemetry_count1(telemetry_count1),
        .telemetry_winner(telemetry_winner)
    );

    puf_allpairs_uart #(.CLKS_PER_BIT(UART_CLKS_PER_BIT)) u_uart (
        .clk(clk), .rst_n(por_done),
        .uart_rx_i(UART_RXD), .uart_tx_o(UART_TXD), .tx_active(tx_active),
        .puf_start(puf_start), .puf_done(puf_done),
        .puf_response(puf_response),
        .telemetry_valid(telemetry_valid),
        .telemetry_index(telemetry_index),
        .telemetry_pair_a(telemetry_pair_a),
        .telemetry_pair_b(telemetry_pair_b),
        .telemetry_count0(telemetry_count0),
        .telemetry_count1(telemetry_count1),
        .telemetry_winner(telemetry_winner),
        .mmcm_locked(1'b1)
    );

    assign LED[0] = tx_active;
    assign LED[1] = puf_busy;
    wire unused_sw = &SW;
endmodule
