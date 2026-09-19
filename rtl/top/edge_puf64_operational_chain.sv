`timescale 1ns / 1ps
`default_nettype none

// Operational-only PUF64 -> FE -> trusted KCV -> KDF/ML-KEM boundary.
// Secret-bearing signals terminate inside this module. Only non-secret stream
// handshakes, status and the nonce-bound diagnostic result tag cross it.
module edge_puf64_operational_chain #(
    parameter integer NUM_RO = 64,
    parameter integer WIDTH = 16,
    parameter integer REF_CYCLES = 1023,
    parameter integer CLEAR_CYCLES = 8,
    parameter integer SETTLE_CYCLES = 8,
    parameter integer CAPTURE_TIMEOUT = 1024
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         zeroize,
    input  wire         start,
    input  wire         command_ok,
    input  wire [263:0] helper_in,
    input  wire         mmcm_locked,
    input  wire         trusted_kcv_valid,
    input  wire [223:0] trusted_kcv_ref,
    input  wire [223:0] helper_kcv_ref,
    input  wire         helper_kcv_valid,
    input  wire [55:0]  kcv_ctx,
    input  wire [31:0]  result_nonce,
    input  wire         stream_in_valid,
    input  wire         peer_ready_c,
    input  wire         peer_req_pk,
    input  wire [31:0]  stream_in_data,
    output wire         ready_pk,
    output wire         req_c,
    output wire         stream_out_valid,
    output wire [31:0]  stream_out_data,
    output wire         busy,
    output wire         done,
    output wire         fe_success,
    output wire         kcv_pass,
    output wire         kcv_fail,
    output wire         mapped_error,
    output wire         early_reject,
    output wire [7:0]   bch_corr_bits,
    output wire [8:0]   selected_count,
    output wire         result_valid,
    output wire [31:0]  result_tag,
    output wire         scrub_done,
    output wire         protocol_start
);
    wire [191:0] fe_key_internal;
    wire         downstream_start;
    wire         downstream_done;
    wire         mlkem_busy;
    wire         secret_valid_internal;
    wire [255:0] shared_secret_internal;

    (* KEEP_HIERARCHY = "yes" *) edge_puf64_operational_core #(
        .NUM_RO(NUM_RO), .WIDTH(WIDTH), .REF_CYCLES(REF_CYCLES),
        .CLEAR_CYCLES(CLEAR_CYCLES), .SETTLE_CYCLES(SETTLE_CYCLES),
        .CAPTURE_TIMEOUT(CAPTURE_TIMEOUT), .ALLOW_ENROLL(1'b0)
    ) u_puf64_core (
        .clk(clk), .rst_n(rst_n), .zeroize(zeroize), .start(start),
        .enroll(1'b0), .command_ok(command_ok), .helper_in(helper_in),
        .helper_out(), .fe_success(fe_success), .mmcm_locked(mmcm_locked),
        .trusted_kcv_valid(trusted_kcv_valid),
        .trusted_kcv_ref(trusted_kcv_ref), .helper_kcv_ref(helper_kcv_ref),
        .helper_kcv_valid(helper_kcv_valid), .kcv_ctx(kcv_ctx),
        .enroll_ctx(56'd0), .kcv_pass(kcv_pass), .fe_kcv(),
        .kcv_fail(kcv_fail), .bch_corr_bits(bch_corr_bits),
        .downstream_key_internal(fe_key_internal),
        .downstream_start(downstream_start),
        .downstream_done(downstream_done), .mapped_error(mapped_error),
        .early_reject(early_reject), .busy(busy), .done(done),
        .selected_count(selected_count)
    );

    edge_mlkem_core u_mlkem (
        .clk(clk), .rst_n(rst_n), .zeroize(zeroize),
        .start(downstream_start), .fe_key(fe_key_internal),
        .stream_in_valid(stream_in_valid), .peer_ready_c(peer_ready_c),
        .peer_req_pk(peer_req_pk), .stream_in_data(stream_in_data),
        .ready_pk(ready_pk), .req_c(req_c),
        .stream_out_valid(stream_out_valid),
        .stream_out_data(stream_out_data), .busy(mlkem_busy),
        .done(downstream_done), .scrub_done(scrub_done),
        .protocol_start(protocol_start), .secret_valid(secret_valid_internal),
        .shared_secret(shared_secret_internal)
    );

    assign result_valid = secret_valid_internal;
    assign result_tag = result_nonce ^ shared_secret_internal[31:0] ^
                        shared_secret_internal[63:32] ^
                        shared_secret_internal[95:64] ^
                        shared_secret_internal[127:96] ^
                        shared_secret_internal[159:128] ^
                        shared_secret_internal[191:160] ^
                        shared_secret_internal[223:192] ^
                        shared_secret_internal[255:224];

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (!zeroize && downstream_start && !command_ok)
            $error("operational ML-KEM launch without an accepted record");
        if (!zeroize && downstream_start && !trusted_kcv_valid)
            $error("operational ML-KEM launch without a trusted anchor");
    end
`endif

    wire unused_mlkem_busy = mlkem_busy;
endmodule

`default_nettype wire
