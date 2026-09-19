`timescale 1ns / 1ps
`default_nettype none

// I3A.1: operational physical PUF hierarchy (`u_puf64_physical` instance in
// the operational top).  This module is a thin, stable wrapper around the
// qualified measurement FSM and its physical cells: 64 RO LUT oscillators,
// local prescaler + 17-stage ripple counters, canonical pair enumerator,
// settle/window/capture and internal telemetry.
//
// No FE/KCV/UART/control logic lives here.  The sweep is always the canonical
// 2016-pair sweep from the qualification campaign; the mapped 264-bit response
// is produced outside this boundary by `kp_puf64_mapping_scheduler`.
//
// The internal instance name `u_puf` is kept so the qualified physical cell
// paths keep their shape for the I4 fingerprint flow.
(* KEEP_HIERARCHY = "yes" *)
module kp_puf64_physical #(
    parameter integer NUM_RO = 64,
    parameter integer WIDTH = 16,
    parameter integer REF_CYCLES = 1023,
    parameter integer CLEAR_CYCLES = 8,
    parameter integer SETTLE_CYCLES = 8,
    parameter integer CAPTURE_TIMEOUT = 1024
)(
    input  logic         clk,
    input  logic         rst_n,
    input  logic         zeroize,
    input  logic         start,
    output logic         busy,
    output logic         done,

    // Internal canonical-sweep telemetry (one terminal event per pair, in
    // canonical index order).  Never exported in the operational image.
    output logic         telemetry_valid,
    output logic [10:0]  telemetry_index,
    output logic [5:0]   telemetry_pair_a,
    output logic [5:0]   telemetry_pair_b,
    output logic [31:0]  telemetry_count0,
    output logic [31:0]  telemetry_count1,
    output logic         telemetry_stable,
    output logic         telemetry_timeout,
    output logic         telemetry_overflow_a,
    output logic         telemetry_overflow_b,
    output logic         telemetry_winner
);
    localparam integer PAIR_COUNT = (NUM_RO * (NUM_RO - 1)) / 2;

    // Physical implementation: the same bench used for build-2
    // characterization/train/holdout.  Do not modify its cells or FSM.
    (* KEEP_HIERARCHY = "yes" *) puf64_ro_bench #(
        .NUM_RO(NUM_RO),
        .WIDTH(WIDTH),
        .REF_CYCLES(REF_CYCLES),
        .CLEAR_CYCLES(CLEAR_CYCLES),
        .SETTLE_CYCLES(SETTLE_CYCLES),
        .CAPTURE_TIMEOUT(CAPTURE_TIMEOUT),
        .PAIR_COUNT(PAIR_COUNT)
    ) u_puf (
        .clk(clk), .rst_n(rst_n), .zeroize(zeroize), .start(start),
        .busy(busy), .done(done), .response(),
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
