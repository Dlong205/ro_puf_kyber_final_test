`timescale 1ns / 1ps
`default_nettype none

// R1 macro-V2 black-box stub for the V2 characterization and operational
// tops' synthesis runs.  Port-for-port identical to kp_puf64_macro_v2; the
// routed OOC DCP is bound with read_checkpoint -cell after synthesis.
// Checked against the real wrapper by scripts/check_puf64_macro_v2_ports.py.
(* black_box *)
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
endmodule

`default_nettype wire
