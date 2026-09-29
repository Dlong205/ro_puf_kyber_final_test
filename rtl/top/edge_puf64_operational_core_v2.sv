`timescale 1ns / 1ps
`default_nettype none

// I3A operational core, macro-V2 edition (CONSTRUCTION shell, NON-RELEASE).
// Identical to edge_puf64_operational_core except the PUF source is the
// black-box macro kp_puf64_macro_v2 (instance u_macro) instead of the golden
// kp_puf64_physical.  Telemetry wiring is unchanged; the macro response bus
// is intentionally left unconnected (scheduler consumes telemetry only).
//
// Hierarchy in the operational top:
//   u_macro            (kp_puf64_macro_v2: frozen OOC RO/ripple/sweep)
//   u_puf64_scheduler  (kp_puf64_mapping_scheduler)
//   u_edge_core        (this module: FE/KCV/downstream control)
//   u_kcv_anchor       (edge_kcv_anchor, outside this core)
//
// Fail early: a reconstruct start is accepted only when the helper parser PASS
// (`command_ok`) and the trusted anchor is valid; otherwise no RO is enabled
// and no sweep runs.  Enrollment is build-time gated (ALLOW_ENROLL) and is
// rejected before the PUF when disabled.
module edge_puf64_operational_core_v2 #(
    parameter integer NUM_RO = 64,
    parameter integer WIDTH = 16,
    parameter integer REF_CYCLES = 1023,
    parameter integer CLEAR_CYCLES = 8,
    parameter integer SETTLE_CYCLES = 8,
    parameter integer CAPTURE_TIMEOUT = 1024,
    parameter bit     ALLOW_ENROLL = 1'b0,
    // R6.1 qualification superset: 1 = qualification (private telemetry
    // readout enabled, NONRELEASE image); 0 = final (capture hardware still
    // present with identical loads, readout forced to zero).  The capture
    // side is unconditional; only the readout mux depends on this parameter.
    parameter bit     QUALIFICATION_NONRELEASE = 1'b0,
    // R7: scheduler tie budget override (release keeps 2; char builds raise
    // to collect data through marginal pairs for re-selection).
    parameter integer TIE_BUDGET = 2
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         zeroize,
    input  wire         start,
    input  wire         enroll,
    // Helper parser result for this request (magic/version/len/tag/profile/CRC).
    input  wire         command_ok,
    input  wire [263:0] helper_in,
    output wire [263:0] helper_out,
    output wire         fe_success,
    // Trusted anchor (from edge_kcv_anchor); helper KCV is consistency-only.
    input  wire         mmcm_locked,
    input  wire         trusted_kcv_valid,
    input  wire [223:0] trusted_kcv_ref,
    input  wire [223:0] helper_kcv_ref,
    input  wire         helper_kcv_valid,
    input  wire [55:0]  kcv_ctx,
    input  wire [55:0]  enroll_ctx,
    output wire         kcv_pass,
    output reg  [223:0] fe_kcv,
    output reg          kcv_fail,
    // Sticky BCH correction count latched at FE-done, preserved through
    // S_ERASE/S_DONE until the next accepted start (the raw FE count is
    // erased with the FE). Count only, never response/helper/key material.
    // Release builds do not expose it; the diagnostic UART appends it after
    // a 0x32 BCH-failure code.
    output reg  [7:0]   bch_corr_bits,
    // Internal handoff only.  This port must terminate in edge_mlkem_core
    // inside the operational integration boundary and must never reach a
    // board pin, UART or MMIO register.
    output wire [191:0] downstream_key_internal,
    // Downstream KDF/ML-KEM gate: one-cycle request, completion input.
    output reg          downstream_start,
    input  wire         downstream_done,
    // Status.
    output reg          mapped_error,
    output reg  [3:0]   mapped_error_reason,
    output reg          early_reject,
    output wire         busy,
    output wire         done,
    output wire [8:0]   selected_count,
    // R6.1 qualification readout (transport-owned).  Capture runs in every
    // build; the sniffer zeroes these in final (QUAL=0) builds.
    input  wire         qual_rd_en,
    input  wire [10:0]  qual_rd_addr,
    output wire [81:0]  qual_rd_data,
    output wire [31:0]  qual_frame_seq,
    output wire [11:0]  qual_entry_count,
    output wire [7:0]   qual_hdr_bch_corr,
    output wire [7:0]   qual_hdr_status,
    output wire         qual_frame_valid
);
    localparam integer PAIR_COUNT = (NUM_RO * (NUM_RO - 1)) / 2;

    localparam logic [3:0] S_IDLE       = 4'd0;
    localparam logic [3:0] S_SWEEP      = 4'd1;
    localparam logic [3:0] S_MAP        = 4'd2;
    localparam logic [3:0] S_FE_START   = 4'd3;
    localparam logic [3:0] S_FE_WAIT    = 4'd4;
    localparam logic [3:0] S_KCV_GEN    = 4'd5;
    localparam logic [3:0] S_KCV_CHECK  = 4'd6;
    localparam logic [3:0] S_DOWNSTREAM = 4'd7;
    localparam logic [3:0] S_ERASE      = 4'd8;
    localparam logic [3:0] S_DONE       = 4'd9;
    localparam logic [3:0] S_DOWN_WAIT  = 4'd10;

    logic [3:0] state;
    logic       start_seen;
    logic       mode_enroll;
    logic       result_success;
    logic       kcv_match_reg;
    logic [263:0] mapped_latched;
    logic         mapped_seen;
    logic [263:0] helper_latched;
    logic         sched_zeroize;
    wire  start_accept = (state == S_IDLE) && start && !start_seen;

    // Physical PUF boundary.
    wire         puf_busy, puf_done;
    wire         tel_valid;
    wire [10:0]  tel_index;
    wire [5:0]   tel_a, tel_b;
    wire [31:0]  tel_c0, tel_c1;
    wire         tel_stable, tel_timeout, tel_ovf_a, tel_ovf_b, tel_winner;
    wire [263:0] mapped_response;
    wire         mapped_valid, mapped_ready, sched_error, sched_busy;
    wire [3:0]   sched_error_reason;
    reg          puf_start_r;

    wire puf_zeroize = zeroize || (state == S_ERASE) || (state == S_DONE);

    // NOTE: no parameter overrides on the black-box macro (Vivado binds
    // #(...) instances against a generated parameter-less stub -> 8-3438).
    // All macro defaults equal the frozen OOC build; the ports checker fails
    // closed on drift.  response[] is intentionally unconnected.
    (* KEEP_HIERARCHY = "yes" *) kp_puf64_macro_v2 u_macro (
        .clk(clk), .rst_n(rst_n), .zeroize(puf_zeroize), .start(puf_start_r),
        .busy(puf_busy), .done(puf_done), .response(),
        .telemetry_valid(tel_valid), .telemetry_index(tel_index),
        .telemetry_pair_a(tel_a), .telemetry_pair_b(tel_b),
        .telemetry_count0(tel_c0), .telemetry_count1(tel_c1),
        .telemetry_stable(tel_stable), .telemetry_timeout(tel_timeout),
        .telemetry_overflow_a(tel_ovf_a), .telemetry_overflow_b(tel_ovf_b),
        .telemetry_winner(tel_winner)
    );

    kp_puf64_mapping_scheduler #(
        .NUM_RO(NUM_RO), .PAIR_COUNT(PAIR_COUNT), .LEN_BITS(264),
        .TIE_BUDGET(TIE_BUDGET)
    ) u_puf64_scheduler (
        .clk(clk), .rst_n(rst_n), .zeroize(zeroize || sched_zeroize),
        .start(start_accept && (state == S_IDLE)),
        .tel_valid(tel_valid), .tel_index(tel_index),
        .tel_pair_a(tel_a), .tel_pair_b(tel_b),
        .tel_count0(tel_c0), .tel_count1(tel_c1),
        .tel_stable(tel_stable), .tel_timeout(tel_timeout),
        .tel_ovf_a(tel_ovf_a), .tel_ovf_b(tel_ovf_b),
        .mmcm_locked(mmcm_locked), .sweep_done(puf_done),
        .mapped_response(mapped_response),
        .mapped_response_valid(mapped_valid),
        .mapped_response_ready(mapped_ready),
        .mapped_response_error(sched_error),
        .mapped_error_reason(sched_error_reason),
        .busy(sched_busy), .selected_count(selected_count)
    );

    wire fe_busy, fe_done_w, fe_result;
    wire [191:0] fe_key;
    wire [263:0] fe_helper_out;
    wire [7:0] fe_corr_w;
    wire fe_zeroize = zeroize || (state == S_ERASE);


    fuzzy_extractor u_fe (
        .clk(clk), .rst_n(rst_n), .zeroize(fe_zeroize),
        .start(state == S_FE_START), .mode(!mode_enroll),
        .response_in(mapped_latched), .helper_in(helper_in),
        .helper_out(fe_helper_out), .key_out(fe_key), .busy(fe_busy),
        .done(fe_done_w), .success(fe_result),
        .corr_bit_count(fe_corr_w)
    );

    wire kcv_done_w, kcv_match;
    wire [223:0] kcv_digest;
    wire helper_kcv_ok = !helper_kcv_valid || (helper_kcv_ref == trusted_kcv_ref);

    edge_root_binding u_kcv (
        .clk(clk), .rst_n(rst_n), .zeroize(zeroize || (state == S_ERASE)),
        .start((state == S_KCV_GEN || state == S_KCV_CHECK) && !kcv_done_w),
        .root_key(fe_key),
        .kcv_ctx(state == S_KCV_GEN ? enroll_ctx : kcv_ctx),
        .kcv_ref(state == S_KCV_GEN ? 224'd0 : trusted_kcv_ref),
        .busy(), .done(kcv_done_w), .kcv_pass(kcv_match),
        .kcv_out(kcv_digest)
    );

    assign fe_success   = result_success;
    assign kcv_pass     = kcv_match_reg;
    assign helper_out   = helper_latched;
    assign downstream_key_internal = fe_key;
    assign busy         = (state != S_IDLE) && (state != S_DONE);
    assign done         = (state == S_DONE);

    // R6.1 qualification sniffer: unconditional capture tap (identical loads
    // in qual and final), lifecycle-gated readout.  Kept as hierarchy so the
    // influence fingerprint can prove the capture hardware present + placed.
    wire sweep_will_start = start_accept &&
        (enroll ? ALLOW_ENROLL : (command_ok && trusted_kcv_valid));
    (* KEEP_HIERARCHY = "yes" *) (* DONT_TOUCH = "yes" *)
    puf64_qual_telemetry_sniffer #(
        .NUM_PAIRS(PAIR_COUNT),
        .QUALIFICATION_NONRELEASE(QUALIFICATION_NONRELEASE)
    ) u_qual_sniffer (
        .clk(clk), .rst_n(rst_n), .zeroize(fe_zeroize),
        .sweep_start(sweep_will_start),
        .sweep_done(mapped_valid),
        .tel_valid(tel_valid), .tel_index(tel_index),
        .tel_a(tel_a), .tel_b(tel_b),
        .tel_c0(tel_c0), .tel_c1(tel_c1),
        .tel_stable(tel_stable), .tel_timeout(tel_timeout),
        .tel_ovf_a(tel_ovf_a), .tel_ovf_b(tel_ovf_b),
        .tel_winner(tel_winner),
        .fe_done(fe_done_w), .fe_success_in(fe_result),
        .fe_corr_in(fe_corr_w),
        .kcv_done(kcv_done_w), .kcv_match_in(kcv_match),
        .rd_en(qual_rd_en), .rd_addr(qual_rd_addr),
        .rd_data(qual_rd_data),
        .frame_seq(qual_frame_seq), .entry_count(qual_entry_count),
        .hdr_bch_corr(qual_hdr_bch_corr), .hdr_status(qual_hdr_status),
        .frame_valid(qual_frame_valid)
    );
    assign done         = (state == S_DONE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= S_IDLE;
            start_seen     <= 1'b0;
            mode_enroll    <= 1'b0;
            result_success <= 1'b0;
            kcv_match_reg  <= 1'b0;
            fe_kcv         <= 224'd0;
            kcv_fail       <= 1'b0;
            mapped_latched <= '0;
            mapped_seen    <= 1'b0;
            helper_latched <= '0;
            mapped_error   <= 1'b0;
            mapped_error_reason <= 4'h0;
            early_reject   <= 1'b0;
            downstream_start <= 1'b0;
            sched_zeroize  <= 1'b0;
            puf_start_r    <= 1'b0;
            bch_corr_bits  <= 8'd0;
        end else if (zeroize) begin
            state          <= S_IDLE;
            start_seen     <= 1'b1;
            mode_enroll    <= 1'b0;
            result_success <= 1'b0;
            kcv_match_reg  <= 1'b0;
            fe_kcv         <= 224'd0;
            kcv_fail       <= 1'b0;
            mapped_latched <= '0;
            mapped_seen    <= 1'b0;
            helper_latched <= '0;
            mapped_error   <= 1'b0;
            mapped_error_reason <= 4'h0;
            early_reject   <= 1'b1;
            downstream_start <= 1'b0;
            sched_zeroize  <= 1'b0;
            puf_start_r    <= 1'b0;
        end else begin
            if (!start)
                start_seen <= 1'b0;
            else if (start_accept)
                start_seen <= 1'b1;

            puf_start_r <= (state == S_SWEEP && !puf_busy && !puf_done);
            sched_zeroize <= 1'b0;
            downstream_start <= 1'b0;

            case (state)
                S_IDLE: begin
                    result_success <= 1'b0;
                    mapped_error   <= 1'b0;
                    mapped_error_reason <= 4'h0;
                    early_reject   <= 1'b0;
                    mapped_seen    <= 1'b0;
                    if (start_accept) begin
                        kcv_match_reg <= 1'b0;
                        kcv_fail <= 1'b0;
                        bch_corr_bits <= 8'd0;
                        fe_kcv <= 224'd0;
                        helper_latched <= '0;
                        mode_enroll <= enroll;
                        if (enroll) begin
                            if (ALLOW_ENROLL) begin
                                state <= S_SWEEP;
                            end else begin
                                early_reject <= 1'b1;
                                state <= S_ERASE;
                            end
                        end else if (command_ok && trusted_kcv_valid) begin
                            state <= S_SWEEP;
                        end else begin
                            early_reject <= 1'b1;
                            state <= S_ERASE;
                        end
                    end
                end

                S_SWEEP: begin
                    if (sched_error) begin
                        mapped_error <= 1'b1;
                        mapped_error_reason <= sched_error_reason;
                        sched_zeroize <= 1'b1;
                        state <= S_ERASE;
                    end else if (mapped_valid) begin
                        mapped_latched <= mapped_response;
                        mapped_seen    <= 1'b1;
                        state <= S_FE_START;
                    end else if (puf_done && sched_busy) begin
                        // Sweep finished; wait for the scheduler handshake.
                        state <= S_MAP;
                    end
                end

                S_MAP: begin
                    if (mapped_valid) begin
                        mapped_latched <= mapped_response;
                        mapped_seen    <= 1'b1;
                        state <= S_FE_START;
                    end else if (sched_error) begin
                        mapped_error <= 1'b1;
                        mapped_error_reason <= sched_error_reason;
                        state <= S_ERASE;
                    end
                end

                S_FE_START: state <= S_FE_WAIT;

                S_FE_WAIT: begin
                    if (fe_done_w) begin
                        result_success <= fe_result;
                        bch_corr_bits <= fe_corr_w;
                        if (mode_enroll && fe_result)
                            helper_latched <= fe_helper_out;
                        if (mode_enroll && fe_result) state <= S_KCV_GEN;
                        else if (!mode_enroll && fe_result && mapped_seen &&
                                 trusted_kcv_valid) state <= S_KCV_CHECK;
                        else state <= S_ERASE;
                    end
                end

                S_KCV_GEN: begin
                    if (kcv_done_w) begin
                        fe_kcv <= kcv_digest;
                        state  <= S_ERASE;
                    end
                end

                S_KCV_CHECK: begin
                    if (kcv_done_w) begin
                        kcv_match_reg <= kcv_match && helper_kcv_ok;
                        kcv_fail <= ~(kcv_match && helper_kcv_ok);
                        state <= (kcv_match && helper_kcv_ok) ? S_DOWNSTREAM
                                                              : S_ERASE;
                    end
                end

                S_DOWNSTREAM: begin
                    downstream_start <= 1'b1;
                    state <= S_DOWN_WAIT;
                end

                S_DOWN_WAIT: begin
                    if (downstream_done) state <= S_ERASE;
                end

                S_ERASE: begin
                    mapped_latched <= '0;
                    sched_zeroize  <= 1'b1;
                    state <= S_DONE;
                end

                S_DONE: state <= S_IDLE;
                default: state <= S_IDLE;
            endcase
        end
    end

    // The scheduler holds mapped_valid until ready; consume as soon as the
    // core can accept it (ready may be high before valid).
    assign mapped_ready = (state == S_SWEEP) || (state == S_MAP);

`ifndef SYNTHESIS
    initial begin
        if (NUM_RO != 64 || WIDTH != 16 || REF_CYCLES != 1023 ||
                CLEAR_CYCLES != 8 || SETTLE_CYCLES != 8 || CAPTURE_TIMEOUT != 1024)
            $error("core_v2 requires the frozen macro defaults (black box has none to override)");
    end
    always @(posedge clk) begin
        if (!zeroize && downstream_start && !(kcv_match_reg))
            $error("KDF/ML-KEM launched without the KCV gate");
        if (!zeroize && downstream_start && mode_enroll)
            $error("KDF/ML-KEM launched during enrollment");
        if (!zeroize && (state == S_FE_START) && !mapped_seen)
            $error("FE launched without a latched mapped response");
        if (!zeroize && puf_start_r && (state != S_SWEEP))
            $error("PUF sweep started outside the sweep state");
    end
`endif
endmodule

`default_nettype wire
