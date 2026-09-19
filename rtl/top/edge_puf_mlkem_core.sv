`timescale 1ns / 1ps
`default_nettype none

// CPU-free Edge integration boundary used before adding framed transport.
// It sequences a physical PUF measurement, BCH enroll/reconstruct, immediate
// secret erasure, compact KDF, and ML-KEM-512 KeyGen/Decaps.
// shared_secret remains an internal verification boundary and must not become
// a board pin; the final board top must consume it in a confirmation engine.
module edge_puf_mlkem_core (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         zeroize,
    input  wire         start,
    input  wire         enroll,
    input  wire [7:0]   puf_seed,
    input  wire [263:0] helper_in,
    output wire [263:0] helper_out,
    output wire         fe_success,

    // Same-root binding (docs/PUF_ROOT_BINDING_DESIGN.md).  The reference is
    // a public KCV verifier provisioned with the enrollment; disabling the
    // gate is only allowed in diagnostic builds that never become artifacts.
    // Trusted KCV anchor (docs/PUF64_KCV_TRUST_ANCHOR_AUDIT.md).  The
    // comparator only ever uses the anchor reference; the helper KCV is a
    // secondary consistency check, never the anchor.
    input  wire         trusted_kcv_valid,
    input  wire [223:0] trusted_kcv_ref,
    input  wire [223:0] helper_kcv_ref,
    input  wire         helper_kcv_valid,
    // Enrollment (provisioning) is only permitted in diagnostic/manufacturing
    // builds; operational builds tie this low so enroll transactions cannot
    // start the core.
    input  wire         enroll_allowed,
    output wire         enroll_mode_o,
    input  wire [55:0]  kcv_ctx,
    input  wire [55:0]  enroll_ctx,
    output wire         kcv_pass,
    output reg  [223:0] fe_kcv,
    // Diagnostic telemetry (characterization builds only; release protocols
    // must not expose these as a byte-position oracle).
    output wire [7:0]   bch_corr_bits,
    output reg          kcv_fail,

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
    output wire         scrub_done,
    output wire         protocol_start,
    output wire         secret_valid,
    output wire [255:0] shared_secret
);
    localparam [3:0] ST_IDLE       = 4'd0;
    localparam [3:0] ST_PUF_START  = 4'd1;
    localparam [3:0] ST_PUF_WAIT   = 4'd2;
    localparam [3:0] ST_FE_START   = 4'd3;
    localparam [3:0] ST_FE_WAIT    = 4'd4;
    localparam [3:0] ST_KCV_CHECK  = 4'd5;
    localparam [3:0] ST_EDGE_START = 4'd6;
    localparam [3:0] ST_EDGE_WAIT  = 4'd7;
    localparam [3:0] ST_FE_ERASE   = 4'd8;
    localparam [3:0] ST_DONE       = 4'd9;
    localparam [3:0] ST_KCV_GEN    = 4'd10;

    reg [3:0] state;
    reg start_seen;
    reg mode_enroll;
    reg result_success;
    wire start_accept = state == ST_IDLE && start && !start_seen;

    wire puf_busy;
    wire puf_done;
    wire [263:0] puf_response;
    wire fe_busy;
    wire fe_done;
    wire fe_result;
    wire [191:0] fe_key;
    wire edge_busy;
    wire edge_done;

    wire puf_start = state == ST_PUF_START;
    wire fe_start = state == ST_FE_START;
    wire edge_start = state == ST_EDGE_START;
    // FE captures the PUF response on ST_FE_START. Erase the PUF one cycle
    // later.  Keep the FE key through ST_EDGE_START: edge_seed_controller and
    // its KDF capture the key on that state's closing edge.  ST_EDGE_WAIT is
    // therefore the earliest safe FE erase point.  The KCV check keeps the
    // FE key until the comparison completes; ST_EDGE_START (pass) or
    // ST_FE_ERASE (fail) is the erase point in both paths.
    wire puf_zeroize = zeroize || state == ST_FE_WAIT ||
                        state == ST_KCV_CHECK || state == ST_KCV_GEN ||
                        state == ST_EDGE_START ||
                        state == ST_EDGE_WAIT || state == ST_FE_ERASE ||
                        state == ST_DONE;
    wire fe_zeroize = zeroize || state == ST_EDGE_WAIT ||
                      state == ST_FE_ERASE || state == ST_DONE;

    assign busy = (state != ST_IDLE) && (state != ST_DONE);
    assign done = state == ST_DONE;
    assign enroll_mode_o = mode_enroll;
    // Helper KCV equality is a consistency check only.  The anchor is
    // always the trusted reference; when no helper KCV is present
    // (legacy diagnostic helper) only the anchor comparison applies.
    wire helper_kcv_ok = !helper_kcv_valid ||
                         (helper_kcv_ref == trusted_kcv_ref);
    assign fe_success = result_success;
    assign kcv_pass = kcv_match_reg;

    edge_root_binding u_kcv (
        .clk(clk), .rst_n(rst_n), .zeroize(zeroize),
        .start((state == ST_KCV_CHECK || state == ST_KCV_GEN) && !kcv_done),
        .root_key(fe_key),
        .kcv_ctx(state == ST_KCV_GEN ? enroll_ctx : kcv_ctx),
        .kcv_ref(trusted_kcv_ref),
        .busy(), .done(kcv_done), .kcv_pass(kcv_match),
        .kcv_out(kcv_digest)
    );

    reg  kcv_match_reg;
    wire kcv_done;
    wire kcv_match;
    wire [223:0] kcv_digest;

    kp_puf_top u_puf (
        .clk(clk), .rst_n(rst_n), .zeroize(puf_zeroize),
        .start(puf_start), .seed(puf_seed), .busy(puf_busy),
        .done(puf_done), .response(puf_response),
        .telemetry_valid(), .telemetry_index(), .telemetry_challenge(),
        .telemetry_count0(), .telemetry_count1(), .telemetry_winner()
    );

    fuzzy_extractor u_fe (
        .clk(clk), .rst_n(rst_n), .zeroize(fe_zeroize),
        .start(fe_start), .mode(!mode_enroll),
        .response_in(puf_response), .helper_in(helper_in),
        .helper_out(helper_out), .key_out(fe_key), .busy(fe_busy),
        .done(fe_done), .success(fe_result),
        .corr_bit_count(bch_corr_bits)
    );

    edge_mlkem_core u_edge (
        .clk(clk), .rst_n(rst_n), .zeroize(zeroize), .start(edge_start),
        .fe_key(fe_key), .stream_in_valid(stream_in_valid),
        .peer_ready_c(peer_ready_c), .peer_req_pk(peer_req_pk),
        .stream_in_data(stream_in_data), .ready_pk(ready_pk), .req_c(req_c),
        .stream_out_valid(stream_out_valid),
        .stream_out_data(stream_out_data), .busy(edge_busy),
        .done(edge_done), .scrub_done(scrub_done),
        .protocol_start(protocol_start), .secret_valid(secret_valid),
        .shared_secret(shared_secret)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= ST_IDLE;
            start_seen     <= 1'b0;
            mode_enroll    <= 1'b0;
            result_success <= 1'b0;
            kcv_match_reg  <= 1'b0;
            fe_kcv         <= 224'd0;
            kcv_fail       <= 1'b0;
        end else if (zeroize) begin
            state          <= ST_IDLE;
            start_seen     <= 1'b1;
            mode_enroll    <= 1'b0;
            result_success <= 1'b0;
            kcv_match_reg  <= 1'b0;
            fe_kcv         <= 224'd0;
            kcv_fail       <= 1'b0;
        end else begin
            if (!start)
                start_seen <= 1'b0;
            else if (start_accept)
                start_seen <= 1'b1;

            case (state)
                ST_IDLE: begin
                    result_success <= 1'b0;
                    if (start_accept && (!enroll || enroll_allowed)) begin
                        kcv_match_reg <= 1'b0;
                        kcv_fail <= 1'b0;
                        mode_enroll <= enroll;
                        state <= ST_PUF_START;
                    end
                end
                ST_PUF_START: state <= ST_PUF_WAIT;
                ST_PUF_WAIT: if (puf_done) state <= ST_FE_START;
                ST_FE_START: state <= ST_FE_WAIT;
                ST_FE_WAIT: begin
                    if (fe_done) begin
                        result_success <= fe_result;
                        if (mode_enroll && fe_result)
                            state <= ST_KCV_GEN;
                        else if (!mode_enroll && fe_result && trusted_kcv_valid)
                            state <= ST_KCV_CHECK;
                        else
                            state <= ST_FE_ERASE;
                    end
                end
                // Enrollment runs the same SHAKE256 KCV core over the freshly
                // generated FE key to publish the public KCV verifier in the
                // helper record.  No comparison is needed on this path.
                ST_KCV_GEN:
                    if (kcv_done) begin
                        fe_kcv <= kcv_digest;
                        state <= ST_DONE;
                    end
                // The KCV verifier latches the FE key on its start cycle and
                // holds it internally until done, so ST_KCV_CHECK may erase
                // the FE copy one cycle after entry.  Wait for the verifier
                // to finish before branching on its result.  The gate
                // decision is registered here because the verifier drops
                // kcv_pass on its return to IDLE while edge_start is still
                // asserted.
                ST_KCV_CHECK:
                    if (kcv_done) begin
                        kcv_match_reg <= kcv_match && helper_kcv_ok;
                        kcv_fail <= ~(kcv_match && helper_kcv_ok);
                        state <= (kcv_match && helper_kcv_ok) ? ST_EDGE_START
                                                              : ST_FE_ERASE;
                    end
                ST_EDGE_START: state <= ST_EDGE_WAIT;
                ST_EDGE_WAIT: if (edge_done) state <= ST_DONE;
                ST_FE_ERASE: state <= ST_DONE;
                ST_DONE: state <= ST_IDLE;
                default: state <= ST_IDLE;
            endcase
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (!zeroize && edge_start && (mode_enroll || !result_success))
            $error("Edge launched without successful reconstruction");
        if (!zeroize && state == ST_EDGE_WAIT && !fe_zeroize)
            $error("FE key was not erased after Edge handoff");
        if (!zeroize && edge_start && !trusted_kcv_valid)
            $error("KCV gate bypassed: edge_start without a trusted anchor");
        if (!zeroize && edge_start && !kcv_match_reg)
            $error("KCV gate bypassed: edge_start without kcv_match");
        if (!zeroize && start_accept && enroll && !enroll_allowed)
            $error("enrollment attempted in an operational core");
        if (!zeroize && edge_start && !helper_kcv_ok)
            $error("edge_start with a helper KCV inconsistent with the anchor");
    end
`endif
endmodule

`default_nettype wire
