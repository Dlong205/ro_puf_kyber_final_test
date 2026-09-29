`timescale 1ns / 1ps
`default_nettype none

// R1 macro-V2 characterization image for Zynq-7020 (NEW image; the golden
// Puf_AllPairs64_Characterization_Top/bitstream is frozen and untouched).
//
// Differences from the golden image:
//   * PUF source is the OOC routed macro kp_puf64_macro_v2 (black box at
//     synthesis, bound with read_checkpoint -cell after synthesis).
//   * BUILD_ID 3, protocol 3.2 (INFO2 returns macro/fingerprint SHAs).
//   * MACRO_SHA256 / FP_SHA256 ROM parameters mirror the frozen R2 manifest
//     (checked by scripts/check_puf64_macrov2_ids.py).
// Same 50 MHz -> 100 MHz MMCM, same pins, same telemetry protocol 3.1
// frames.  This is a characterization image, never an operational image.
module Puf64_MacroV2_Characterization_Top #(
    parameter integer UART_CLKS_PER_BIT = 868
)(
    input  wire       CLK50MHZ,
    input  wire [1:0] SW,
    input  wire       UART_RXD,
    output wire       UART_TXD,
    output wire [1:0] LED
);
    localparam integer NUM_RO = 64;
    localparam integer PAIR_COUNT = NUM_RO * (NUM_RO - 1) / 2;
    localparam integer REF_CYCLES = 1023;
    localparam integer BUILD_ID = 16'h0003;
    localparam integer INPUT_CLOCK_HZ = 50000000;
    localparam integer SYSTEM_CLOCK_HZ = 100000000;
    localparam integer MEASUREMENT_WINDOW_NS = (REF_CYCLES * 1000) / (SYSTEM_CLOCK_HZ / 1000000);
    // Frozen R2 macro: build/puf64_macro_v2/r2_freeze_manifest.tsv.
    localparam [255:0] MACRO_SHA256 =
        256'hbd0cd6200ca4e122932596eb8502d29f1b7d4b1aedf974a79990b4d1f5a9fdd4;
    localparam [255:0] FP_SHA256 =
        256'h7d12e3a99849f6d6351e414ebe17829fa2175cdbe42c55bc19df27bbd45afbf5;

    wire clk_in = CLK50MHZ;
    wire clk_sys_pre;
    wire clk_sys;
    wire mmcm_locked;
    wire mmcm_fb;

    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKFBOUT_MULT_F(20.0),
        .CLKFBOUT_PHASE(0.0),
        .CLKIN1_PERIOD(20.0),
        .CLKOUT0_DIVIDE_F(10.0),
        .CLKOUT0_DUTY_CYCLE(0.5),
        .CLKOUT0_PHASE(0.0),
        .DIVCLK_DIVIDE(1),
        .REF_JITTER1(0.0),
        .STARTUP_WAIT("FALSE")
    ) mmcm_i (
        .CLKOUT0(clk_sys_pre),
        .CLKFBOUT(mmcm_fb),
        .CLKFBIN(mmcm_fb),
        .CLKIN1(clk_in),
        .PWRDWN(1'b0),
        .RST(1'b0),
        .LOCKED(mmcm_locked)
    );

    BUFG bufg_sys (
        .I(clk_sys_pre),
        .O(clk_sys)
    );

    reg [15:0] por_cnt = 16'd0;
    reg por_done = 1'b0;
    always @(posedge clk_sys) begin
        if (!mmcm_locked) begin
            por_cnt <= 16'd0;
            por_done <= 1'b0;
        end else if (!por_done) begin
            por_cnt <= por_cnt + 1'b1;
            if (por_cnt == 16'hFFFF)
                por_done <= 1'b1;
        end
    end

    wire puf_start, puf_busy, puf_done, tx_active;
    wire [PAIR_COUNT-1:0] puf_response;
    wire telemetry_valid;
    wire telemetry_stable, telemetry_timeout;
    wire telemetry_overflow_a, telemetry_overflow_b;
    wire [10:0] telemetry_index;
    wire [5:0] telemetry_pair_a, telemetry_pair_b;
    wire [31:0] telemetry_count0, telemetry_count1;
    wire telemetry_winner;

    // NOTE: no parameter overrides on purpose.  Vivado elaborates black-box
    // instances against a generated parameter-less stub, so overrides fail
    // with Synth 8-3438.  All macro defaults already equal the frozen OOC
    // build (NUM_RO 64 etc.); scripts/check_puf64_macro_v2_ports.py fails
    // closed if stub/wrapper defaults ever drift.
    (* KEEP_HIERARCHY = "yes" *) kp_puf64_macro_v2 u_macro (
        .clk(clk_sys), .rst_n(por_done), .zeroize(1'b0), .start(puf_start),
        .busy(puf_busy), .done(puf_done), .response(puf_response),
        .telemetry_valid(telemetry_valid),
        .telemetry_stable(telemetry_stable),
        .telemetry_timeout(telemetry_timeout),
        .telemetry_overflow_a(telemetry_overflow_a),
        .telemetry_overflow_b(telemetry_overflow_b),
        .telemetry_index(telemetry_index),
        .telemetry_pair_a(telemetry_pair_a),
        .telemetry_pair_b(telemetry_pair_b),
        .telemetry_count0(telemetry_count0),
        .telemetry_count1(telemetry_count1),
        .telemetry_winner(telemetry_winner)
    );

    puf_allpairs_uart_v2 #(
        .CLKS_PER_BIT(UART_CLKS_PER_BIT),
        .NUM_RO(NUM_RO),
        .PAIR_COUNT(PAIR_COUNT),
        .RESPONSE_BITS(PAIR_COUNT),
        .INPUT_CLOCK_HZ(INPUT_CLOCK_HZ),
        .SYSTEM_CLOCK_HZ(SYSTEM_CLOCK_HZ),
        .REF_CYCLES_INFO(REF_CYCLES),
        .MEASUREMENT_WINDOW_NS(MEASUREMENT_WINDOW_NS),
        .WIDTH(16), .TOPOLOGY_ID(16'hC0DE), .BUILD_ID(BUILD_ID),
        .IMAGE_MODE(8'h01),
        .PROTO_MAJOR(3), .PROTO_MINOR(2),
        .MACRO_SHA256(MACRO_SHA256),
        .FP_SHA256(FP_SHA256)
    ) u_uart (
        .clk(clk_sys), .rst_n(por_done),
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
        .telemetry_stable(telemetry_stable),
        .telemetry_timeout(telemetry_timeout),
        .telemetry_overflow_a(telemetry_overflow_a),
        .telemetry_overflow_b(telemetry_overflow_b),
        .mmcm_locked(mmcm_locked)
    );

    assign LED[0] = tx_active;
    assign LED[1] = puf_busy;
    wire unused_sw = &SW;
endmodule

`default_nettype wire
