`timescale 1ns / 1ps
`default_nettype none

// Same-root bound Edge integration boundary for the ASIC flow
// (PUF/FE -> KCV -> KDF -> ML-KEM-512 KeyGen/Decaps).
//
// Kyber_System_Asic_Top keeps the legacy SoC loopback; this top is the
// CPU-free bounded-chain target that carries the Phase 1 KCV gate (security
// review): the FE root is compared against the provisioned reference before
// the compact KDF and Kyber_Server may launch.  It deliberately contains no
// pad cell, PLL, power-on-reset counter or FPGA primitive (mirroring
// Kyber_System_Asic_Top).  shared_secret stays internal: only a non-crypto-
// graphic result tag and status cross this boundary.  The physical
// integration layer must consume/confirm the tag on-chip.
module Edge_Puf_Mlkem_Asic_Top (
    input  wire        clk_i,
    input  wire        rst_ni,

    // Lifecycle commands (pulse; enroll must be qualified by the wrapper).
    input  wire        zeroize_i,
    input  wire        enroll_i,
    input  wire        start_i,

    // Challenge/config seed for the RO-PUF measurement.
    input  wire [7:0]  puf_seed_i,

    // Public helper + same-root KCV provisioning.
    input  wire [263:0] helper_in_i,
    output wire [263:0] helper_out_o,

    // Trusted KCV anchor supplied by the platform (ROM/OTP/integrity-protected
    // macro).  The helper KCV is only a consistency input.  With
    // trusted_kcv_valid_i=0 the core fails closed before KDF/ML-KEM.
    input  wire         trusted_kcv_valid_i,
    input  wire [223:0] trusted_kcv_ref_i,
    input  wire [223:0] helper_kcv_ref_i,
    input  wire         helper_kcv_valid_i,
    input  wire         enroll_allowed_i,
    input  wire [55:0]  kcv_ctx_i,
    input  wire [55:0]  enroll_ctx_i,
    output wire         kcv_pass_o,
    output wire         kcv_fail_o,
    output wire [223:0] kcv_out_o,
    output wire         fe_success_o,
    // Diagnostic-only applied BCH correction magnitude; release builds must
    // tie it off so it never becomes a byte-position oracle.
    output wire [7:0]   bch_corr_bits_o,

    // ML-KEM-512 server stream (word based).
    input  wire         peer_req_pk_i,
    input  wire         peer_ready_c_i,
    input  wire         stream_in_valid_i,
    input  wire [31:0]  stream_in_data_i,
    output wire         ready_pk_o,
    output wire         req_c_o,
    output wire         stream_out_valid_o,
    output wire [31:0]  stream_out_data_o,

    output wire         busy_o,
    output wire         done_o,
    output wire         scrub_done_o,
    output wire         protocol_start_o,
    output wire         secret_valid_o,
    // Non-secret confirmation: XOR-folded shared secret, usable by a host
    // that runs the ML-KEM-512 client handshake.
    output wire [31:0]  result_tag_o,
    output wire [1:0]   status_o
);

    // Asynchronous assertion, synchronous release into the system clock
    // domain (same reset contract as Kyber_System_Asic_Top).
    wire rst_sys_n;
    reset_sync_n u_reset_sync (
        .clk_i(clk_i),
        .arst_ni(rst_ni),
        .srst_no(rst_sys_n)
    );

    wire [263:0] helper_out;
    wire         fe_success;
    wire         kcv_pass;
    wire         kcv_fail;
    wire [223:0] kcv_out;
    wire [255:0] shared_secret;
    wire         secret_valid;

    edge_puf_mlkem_core u_core (
        .clk(clk_i),
        .rst_n(rst_sys_n),
        .zeroize(zeroize_i),
        .start(start_i),
        .enroll(enroll_i),
        .puf_seed(puf_seed_i),
        .helper_in(helper_in_i),
        .helper_out(helper_out),
        .fe_success(fe_success),
        .enroll_allowed(enroll_allowed_i),
        .trusted_kcv_valid(trusted_kcv_valid_i),
        .trusted_kcv_ref(trusted_kcv_ref_i),
        .helper_kcv_ref(helper_kcv_ref_i),
        .helper_kcv_valid(helper_kcv_valid_i),
        .kcv_ctx(kcv_ctx_i),
        .enroll_ctx(enroll_ctx_i),
        .kcv_pass(kcv_pass),
        .fe_kcv(kcv_out),
        .bch_corr_bits(bch_corr_bits_o),
        .kcv_fail(kcv_fail),
        .stream_in_valid(stream_in_valid_i),
        .peer_ready_c(peer_ready_c_i),
        .peer_req_pk(peer_req_pk_i),
        .stream_in_data(stream_in_data_i),
        .ready_pk(ready_pk_o),
        .req_c(req_c_o),
        .stream_out_valid(stream_out_valid_o),
        .stream_out_data(stream_out_data_o),
        .busy(busy_o),
        .done(done_o),
        .scrub_done(scrub_done_o),
        .protocol_start(protocol_start_o),
        .secret_valid(secret_valid),
        .shared_secret(shared_secret)
    );

    assign helper_out_o = helper_out;
    assign fe_success_o = fe_success;
    assign kcv_pass_o   = kcv_pass;
    assign kcv_fail_o   = kcv_fail;
    assign kcv_out_o    = kcv_out;
    assign secret_valid_o = secret_valid;

    // XOR-fold the shared secret into a single confirmation tag.  This is
    // intentionally not a cryptographic MAC; a verifying host must perform
    // the matching client-side encapsulation.
    assign result_tag_o = shared_secret[31:0]   ^ shared_secret[63:32] ^
                          shared_secret[95:64]  ^ shared_secret[127:96] ^
                          shared_secret[159:128] ^ shared_secret[191:160] ^
                          shared_secret[223:192] ^ shared_secret[255:224];

    assign status_o[0] = kcv_pass;
    assign status_o[1] = done_o;

endmodule

`default_nettype wire