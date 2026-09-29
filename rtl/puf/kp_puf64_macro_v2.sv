`timescale 1ns / 1ps
`default_nettype none

// R1 macro-V2 root: thin, stable boundary around puf64_ro_bench_v2.
// This module is the OOC synthesis root and the black-box unit imported by
// both the V2 characterization and operational tops via the SAME routed DCP.
// Port-for-port identical to puf64_ro_bench_v2; straight wires only, no
// logic at this level.  DONT_TOUCH on the instance keeps the boundary crisp
// for OOC synthesis and black-box matching (checked by
// scripts/check_puf64_macro_v2_ports.py).
(* KEEP_HIERARCHY = "yes" *)
module kp_puf64_macro_v2 #(
    parameter integer NUM_RO = 64,
    parameter integer WIDTH = 16,
    parameter integer REF_CYCLES = 1023,
    parameter integer CLEAR_CYCLES = 8,
    parameter integer SETTLE_CYCLES = 8,
    parameter integer CAPTURE_TIMEOUT = 1024,
    parameter integer PAIR_COUNT = (NUM_RO * (NUM_RO - 1)) / 2,
    parameter integer RO_BITS = (NUM_RO <= 1) ? 1 : $clog2(NUM_RO),
    parameter integer IDX_W = (PAIR_COUNT <= 1) ? 1 : $clog2(PAIR_COUNT)
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  zeroize,
    input  wire                  start,
    output wire                  busy,
    output wire                  done,
    output wire [PAIR_COUNT-1:0] response,
    output wire                  telemetry_valid,
    output wire                  telemetry_stable,
    output wire                  telemetry_timeout,
    output wire                  telemetry_overflow_a,
    output wire                  telemetry_overflow_b,
    output wire [IDX_W-1:0]      telemetry_index,
    output wire [RO_BITS-1:0]    telemetry_pair_a,
    output wire [RO_BITS-1:0]    telemetry_pair_b,
    output wire [31:0]           telemetry_count0,
    output wire [31:0]           telemetry_count1,
    output wire                  telemetry_winner
);
    (* DONT_TOUCH = "true" *) puf64_ro_bench_v2 #(
        .NUM_RO(NUM_RO),
        .WIDTH(WIDTH),
        .REF_CYCLES(REF_CYCLES),
        .CLEAR_CYCLES(CLEAR_CYCLES),
        .SETTLE_CYCLES(SETTLE_CYCLES),
        .CAPTURE_TIMEOUT(CAPTURE_TIMEOUT)
    ) u_bench (
        .clk(clk),
        .rst_n(rst_n),
        .zeroize(zeroize),
        .start(start),
        .busy(busy),
        .done(done),
        .response(response),
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
endmodule

`default_nettype wire
