`timescale 1ns / 1ps

// Isolated 2016-candidate (C(64,2)) RO-PUF characterization image for the
// PUF64 qualification phase.  Protocol 3.0 self-reports NUM_RO=64/PAIR_COUNT
// =2016 so a host can never confuse this pool with the 32-RO/PUF32 baseline.
// This top exports physical fingerprint telemetry and must never be used as a
// release image.
module Puf_AllPairs64_Characterization_Top #(
    parameter integer UART_CLKS_PER_BIT = 434
)(
    input  wire       CLK100MHZ,
    input  wire [1:0] SW,
    input  wire       UART_RXD,
    output wire       UART_TXD,
    output wire [1:0] LED
);
    localparam integer NUM_RO = 64;
    localparam integer PAIR_COUNT = NUM_RO * (NUM_RO - 1) / 2;
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
    wire [PAIR_COUNT-1:0] puf_response;
    wire telemetry_valid;
    wire [10:0] telemetry_index;
    wire [5:0] telemetry_pair_a, telemetry_pair_b;
    wire [31:0] telemetry_count0, telemetry_count1;
    wire telemetry_winner;

    // Deliberately the same hierarchy naming convention as the 32-RO image so
    // the physical placement audit filter (*u_puf*ring*LUT6*) still applies;
    // NUM_RO=64 yields 256 RO LUTs.
    kp_puf_allpairs_top #(
        .NUM_RO(NUM_RO), .PAIR_COUNT(PAIR_COUNT)
    ) u_puf (
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

    puf_allpairs_uart #(
        .CLKS_PER_BIT(UART_CLKS_PER_BIT),
        .NUM_RO(NUM_RO),
        .PAIR_COUNT(PAIR_COUNT),
        .RESPONSE_BITS(PAIR_COUNT)
    ) u_uart (
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
        .telemetry_winner(telemetry_winner)
    );

    assign LED[0] = tx_active;
    assign LED[1] = puf_busy;
    wire unused_sw = &SW;
endmodule