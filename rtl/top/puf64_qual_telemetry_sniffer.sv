`timescale 1ns / 1ps
`default_nettype none

// R6.1 operational-qualification telemetry sniffer (QUALIFICATION superset).
//
// Captures the FULL 2016-pair sweep telemetry (counts per pair) plus the
// frame outcome (BCH corrections, FE/KCV status) into block RAM.  The capture
// path is UNCONDITIONAL: it runs identically in qualification and final
// images so the telemetry-net loads, BRAM activity and surrounding placement
// are the same operational environment in both.
//
// The readout path is lifecycle-gated by QUALIFICATION_NONRELEASE:
//   QUAL=1 (qualification image only): private readout command streams the
//     captured frame for train/holdout analysis.  Never a release image.
//   QUAL=0 (final image): readout data is forced to zero and the private
//     command is rejected exactly like any unsupported command.  The capture
//     registers and BRAM remain (DONT_TOUCH) so loads are preserved.
//
// Privacy: this module NEVER sees the mapped response bits used as FE input
// beyond a valid strobe, NEVER sees the FE key, KCV digest, or shared
// secret.  It records per-pair COUNTER values (c0/c1) and outcome metadata
// only.  Counter data is PUF-modelable and therefore the readout must never
// exist in a release image (enforced by check_puf64_qual_static.py + netlist
// gate in build_puf64_qual.tcl).
module puf64_qual_telemetry_sniffer #(
    parameter integer NUM_PAIRS = 2016,
    parameter integer ADDR_W = 11,
    parameter bit QUALIFICATION_NONRELEASE = 1'b0
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         zeroize,
    // Frame delimiters from the operational core.
    input  wire         sweep_start,   // accepted reconstruct start
    input  wire         sweep_done,    // mapped response valid (frame complete)
    // Macro telemetry bus (single-register tap load per bit by design).
    input  wire         tel_valid,
    input  wire [10:0]  tel_index,
    input  wire [5:0]   tel_a,
    input  wire [5:0]   tel_b,
    input  wire [31:0]  tel_c0,
    input  wire [31:0]  tel_c1,
    input  wire         tel_stable,
    input  wire         tel_timeout,
    input  wire         tel_ovf_a,
    input  wire         tel_ovf_b,
    input  wire         tel_winner,
    // Outcome latches (pulsed/valid after sweep_done).
    input  wire         fe_done,
    input  wire         fe_success_in,
    input  wire [7:0]   fe_corr_in,
    input  wire         kcv_done,
    input  wire         kcv_match_in,
    // Synchronous readout port (transport-owned FSM).
    input  wire         rd_en,
    input  wire [10:0]  rd_addr,
    output wire [81:0]  rd_data,
    // Frame header (zeroed when QUAL=0).
    output wire [31:0]  frame_seq,
    output wire [11:0]  entry_count,
    output wire [7:0]   hdr_bch_corr,
    output wire [7:0]   hdr_status,
    output wire         frame_valid
);
    // Entry: {c0, c1, a, b, winner, stable, timeout, ovf_a, ovf_b, valid}.
    localparam integer ENTRY_W = 82;

    // Capture registers: exactly one FDRE load per telemetry bit (the load
    // the final image must also present).
    (* DONT_TOUCH = "yes" *) reg         r_valid;
    (* DONT_TOUCH = "yes" *) reg [10:0]  r_index;
    (* DONT_TOUCH = "yes" *) reg [5:0]   r_a, r_b;
    (* DONT_TOUCH = "yes" *) reg [31:0]  r_c0, r_c1;
    (* DONT_TOUCH = "yes" *) reg         r_stable, r_timeout;
    (* DONT_TOUCH = "yes" *) reg         r_ovf_a, r_ovf_b, r_winner;

    // Capture store: proven true-dual-port block-RAM template
    // (generic_bram, already used by the ML-KEM datapath).  Port A is the
    // unconditional capture write (identical activity in qual and final);
    // port B is the transport-owned readout.
    wire        mem_we_a = r_valid && r_frame_open && (r_index < 11'(NUM_PAIRS));
    wire [ENTRY_W-1:0] mem_din_a = {r_c0, r_c1, r_a, r_b, r_winner, r_stable,
                                    r_timeout, r_ovf_a, r_ovf_b, 1'b1};
    wire [ENTRY_W-1:0] mem_dout_b;
    generic_bram #(
        .DEPTH(2048), .WIDTH(ENTRY_W)
    ) u_frame_mem (
        .clk(clk),
        .en_a(1'b1), .we_a(mem_we_a), .addr_a(r_index), .din_a(mem_din_a),
        .dout_a(),
        .en_b(rd_en), .we_b(1'b0), .addr_b(rd_addr),
        .din_b({ENTRY_W{1'b0}}), .dout_b(mem_dout_b),
        .scrub_en(1'b0), .scrub_addr(11'd0)
    );
    // Frame header registers (completed-frame header survives zeroize so
    // the host can read it after the post-session scrub; next sweep_start
    // resets them.  No secrets here: counters + outcome metadata only).
    (* DONT_TOUCH = "yes" *) reg [31:0] r_frame_seq;
    (* DONT_TOUCH = "yes" *) reg [11:0] r_entry_count;
    (* DONT_TOUCH = "yes" *) reg [7:0]  r_bch_corr;
    // hdr_status bits: [0]=frame_valid [1]=overrun [2]=fe_ok [3]=kcv_ok
    // [4]=timeout_seen [5]=ovf_seen [7:6]=0.
    (* DONT_TOUCH = "yes" *) reg [7:0]  r_status;
    (* DONT_TOUCH = "yes" *) reg         r_frame_open;
    (* DONT_TOUCH = "yes" *) reg         r_frame_valid;

    wire frame_open_d = sweep_start && !r_frame_open;
    // A new sweep while the previous frame was never closed/completed, or a
    // sweep while a completed frame awaits readout, sets the overrun sticky.
    wire overrun_ev = sweep_start && (r_frame_open || r_frame_valid);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_valid <= 1'b0;
            r_index <= 11'd0;
            r_a <= 6'd0; r_b <= 6'd0;
            r_c0 <= 32'd0; r_c1 <= 32'd0;
            r_stable <= 1'b0; r_timeout <= 1'b0;
            r_ovf_a <= 1'b0; r_ovf_b <= 1'b0; r_winner <= 1'b0;
            r_frame_seq <= 32'd0;
            r_entry_count <= 12'd0;
            r_bch_corr <= 8'd0;
            r_status <= 8'd0;
            r_frame_open <= 1'b0;
            r_frame_valid <= 1'b0;
        end else if (zeroize) begin
            // Zeroize clears an in-progress sweep and the tap stage, but
            // PRESERVES the last completed frame (header + BRAM) so the
            // host can fetch it after the post-session scrub.  The next
            // sweep_start resets the header.  Nothing secret is retained:
            // per-pair counters + outcome metadata only (no FE key, no
            // KCV, no shared secret ever enters this module).
            r_valid <= 1'b0;
            r_frame_open <= 1'b0;
        end else begin
            // Input tap stage (the identical load in qual and final).
            r_valid <= tel_valid;
            r_index <= tel_index;
            r_a <= tel_a; r_b <= tel_b;
            r_c0 <= tel_c0; r_c1 <= tel_c1;
            r_stable <= tel_stable; r_timeout <= tel_timeout;
            r_ovf_a <= tel_ovf_a; r_ovf_b <= tel_ovf_b; r_winner <= tel_winner;

            if (frame_open_d) begin
                r_frame_seq <= r_frame_seq + 1'b1;
                r_entry_count <= 12'd0;
                r_bch_corr <= 8'd0;
                r_status <= 8'd0;
                r_frame_open <= 1'b1;
                r_frame_valid <= 1'b0;
                if (overrun_ev)
                    r_status[1] <= 1'b1;
            end else if (overrun_ev) begin
                r_status[1] <= 1'b1;
            end

            // Capture bookkeeping (the BRAM write itself happens in
            // u_frame_mem port A, same cycle, unconditional hardware).
            if (mem_we_a) begin
                if (r_entry_count < 12'd4095)
                    r_entry_count <= r_entry_count + 1'b1;
                if (r_timeout) r_status[4] <= 1'b1;
                if (r_ovf_a || r_ovf_b) r_status[5] <= 1'b1;
            end

            if (sweep_done && r_frame_open) begin
                r_frame_open <= 1'b0;
                r_frame_valid <= 1'b1;
                r_status[0] <= 1'b1;
            end

            if (fe_done && (r_frame_valid || r_frame_open)) begin
                r_bch_corr <= fe_corr_in;
                r_status[2] <= fe_success_in;
            end
            if (kcv_done && (r_frame_valid || r_frame_open)) begin
                r_status[3] <= kcv_match_in;
            end

            // No readout register here: mem_dout_b is already the BRAM's
            // synchronous output (transport holds addr through WAIT, data
            // valid from end of WAIT).  The lifecycle mux below is the
            // only readout gate.
        end
    end

    // Lifecycle gate: final images expose zero on the readout path.  The
    // mux select is the QUALIFICATION_NONRELEASE build parameter; the
    // capture side above is untouched by it (identical loads/activity).
    wire [ENTRY_W-1:0] rd_q_gated =
        QUALIFICATION_NONRELEASE ? mem_dout_b : {ENTRY_W{1'b0}};
    assign rd_data    = rd_q_gated;
    assign frame_seq  = QUALIFICATION_NONRELEASE ? r_frame_seq   : 32'd0;
    assign entry_count = QUALIFICATION_NONRELEASE ? r_entry_count : 12'd0;
    assign hdr_bch_corr = QUALIFICATION_NONRELEASE ? r_bch_corr  : 8'd0;
    assign hdr_status = QUALIFICATION_NONRELEASE ? r_status      : 8'd0;
    assign frame_valid = QUALIFICATION_NONRELEASE ? r_frame_valid : 1'b0;

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (!QUALIFICATION_NONRELEASE && (frame_seq != 32'd0 ||
             entry_count != 12'd0 || hdr_bch_corr != 8'd0 ||
             hdr_status != 8'd0 || frame_valid)) begin
            $error("qual sniffer leaks telemetry in final (QUAL=0) build");
        end
    end
`endif
endmodule

`default_nettype wire
