`timescale 1ns / 1ps
`default_nettype none

// Elaboration-only leaf contracts. Functional behavior of both leaves is
// covered by their dedicated regressions; this file checks the new I3.7
// boundary port wiring without duplicating the large FE/ML-KEM compilation.
module edge_puf64_operational_core #(
    parameter integer NUM_RO = 64,
    parameter integer WIDTH = 16,
    parameter integer REF_CYCLES = 1023,
    parameter integer CLEAR_CYCLES = 8,
    parameter integer SETTLE_CYCLES = 8,
    parameter integer CAPTURE_TIMEOUT = 1024,
    parameter bit ALLOW_ENROLL = 1'b0
) (
    input wire clk, rst_n, zeroize, start, enroll, command_ok,
    input wire [263:0] helper_in,
    output wire [263:0] helper_out,
    output wire fe_success,
    input wire mmcm_locked, trusted_kcv_valid,
    input wire [223:0] trusted_kcv_ref, helper_kcv_ref,
    input wire helper_kcv_valid,
    input wire [55:0] kcv_ctx, enroll_ctx,
    output wire kcv_pass,
    output wire [223:0] fe_kcv,
    output wire kcv_fail,
    output wire [7:0] bch_corr_bits,
    output wire [191:0] downstream_key_internal,
    output wire downstream_start,
    input wire downstream_done,
    output wire mapped_error, early_reject, busy, done,
    output wire [8:0] selected_count
);
    assign helper_out = 264'd0;
    assign fe_success = 1'b0;
    assign kcv_pass = 1'b0;
    assign fe_kcv = 224'd0;
    assign kcv_fail = 1'b0;
    assign bch_corr_bits = 8'd0;
    assign downstream_key_internal = 192'd0;
    assign downstream_start = 1'b0;
    assign mapped_error = 1'b0;
    assign early_reject = 1'b0;
    assign busy = 1'b0;
    assign done = 1'b0;
    assign selected_count = 9'd0;
endmodule

module edge_mlkem_core (
    input wire clk, rst_n, zeroize, start,
    input wire [191:0] fe_key,
    input wire stream_in_valid, peer_ready_c, peer_req_pk,
    input wire [31:0] stream_in_data,
    output wire ready_pk, req_c, stream_out_valid,
    output wire [31:0] stream_out_data,
    output wire busy, done, scrub_done, protocol_start, secret_valid,
    output wire [255:0] shared_secret
);
    assign ready_pk = 1'b0;
    assign req_c = 1'b0;
    assign stream_out_valid = 1'b0;
    assign stream_out_data = 32'd0;
    assign busy = 1'b0;
    assign done = 1'b0;
    assign scrub_done = 1'b0;
    assign protocol_start = 1'b0;
    assign secret_valid = 1'b0;
    assign shared_secret = 256'd0;
endmodule

`default_nettype wire
