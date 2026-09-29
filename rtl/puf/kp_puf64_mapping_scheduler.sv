`timescale 1ns / 1ps
`default_nettype none

// PUF64 mapped-response scheduler (I3).
//
// Consumes the canonical all-pairs telemetry stream (index 0..2015, one
// terminal event per pair) from the qualified measurement FSM and produces the
// frozen 264-bit mapped response.  The sweep itself stays canonical: the
// operational duty cycle/order/coupling is identical to characterization;
// only selected pairs are stored.
//
// Frozen convention (audited): response bit = 1 if count_a < count_b, 0 if
// count_a > count_b; count_a == count_b is a tie.
//   * tie on a SELECTED pair  -> correctable error for the BCH (t=8):
//     deterministic 0 is stored and the sweep continues. At most
//     MAX_TIE_ERRORS ties per sweep are absorbed; a further tie fails
//     closed (sticky error, reason 0x5). Rationale: board E2E on the
//     operational image showed a stable single tie (0x45, 10/10 runs) on a
//     margin-4 selected pair that never tied in characterization; aborting
//     the whole session on one marginal bit gives 0% availability while the
//     BCH + 224-bit KCV gate still hold the same-root guarantee.
//   * tie on an UNSELECTED pair -> ignored (qualification observed them).
//   * timeout / overflow / count-zero / MMCM unlock on ANY pair -> sticky
//     sweep error and fail-closed; the partial response is erased.
//
// The response is held stable until mapped_response_ready and is zeroized when
// consumed.  A new start or reset clears response/bitmap/error.
module kp_puf64_mapping_scheduler #(
    parameter integer NUM_RO = 64,
    parameter integer PAIR_COUNT = 2016,
    parameter integer LEN_BITS = 264,
    parameter integer MAX_TIE_ERRORS = 2,
    // R7: characterization override (char builds raise this to collect data
    // through marginal pairs; release keeps 2). The tie budget bounds
    // scheduler-absorbed ties per sweep; BCH(t=8)+KCV still gate downstream.
    parameter integer TIE_BUDGET = MAX_TIE_ERRORS
)(
    input  wire logic               clk,
    input  wire logic               rst_n,
    input  wire logic               zeroize,
    input  wire logic               start,

    // Canonical sweep telemetry: one valid pulse per pair, in index order.
    input  wire logic               tel_valid,
    input  wire logic [10:0]        tel_index,
    input  wire logic [5:0]         tel_pair_a,
    input  wire logic [5:0]         tel_pair_b,
    input  wire logic [31:0]        tel_count0,
    input  wire logic [31:0]        tel_count1,
    input  wire logic               tel_stable,
    input  wire logic               tel_timeout,
    input  wire logic               tel_ovf_a,
    input  wire logic               tel_ovf_b,
    input  wire logic               mmcm_locked,
    input  wire logic               sweep_done,

    // Mapped response handshake.
    output logic [LEN_BITS-1:0] mapped_response,
    output logic                mapped_response_valid,
    input  wire logic                mapped_response_ready,
    output logic                mapped_response_error,
    output logic [3:0]          mapped_error_reason,
    output logic                busy,
    output logic [8:0]          selected_count
);
    `include "puf64_mapping_data.vh"

    localparam logic [1:0] S_IDLE   = 2'd0;
    localparam logic [1:0] S_SWEEP  = 2'd1;
    localparam logic [1:0] S_FINISH = 2'd2;
    localparam logic [1:0] S_ERROR  = 2'd3;

    logic [1:0] state;
    logic [8:0] sel_ptr;
    logic [8:0] count;
    logic [2:0] tie_count;
    logic       error_sticky;
    logic [LEN_BITS-1:0] response_r;

    // I4.2a pipeline: break the sel_ptr -> mapping-table -> compare ->
    // response-write chain that missed 100 MHz (was 20 logic levels in one
    // cycle).  Nothing outside this module changes: same canonical sweep
    // order, same table, same destinations, same REF_CYCLES/settle/capture.
    //
    // Cycle N:   sel_ptr -> puf64_map_sorted_full/dest LUTs -> lookup_*_r.
    // Cycle N+1: latched event vs lookup_*_r compare -> tie/error/match.
    // The lookup registers refresh every cycle from the live sel_ptr, so a
    // decision in cycle D always uses the table entry for sel_ptr@(D-1),
    // which already includes every earlier commit.  A match commit sets
    // bubble_r for one cycle so the lookup can refresh to the next entry
    // before the following decision; non-match events need no bubble.
    // HW telemetry spacing (>1000 clocks) never fills the 2-deep event FIFO;
    // any FIFO overflow fails closed.
    logic [10:0] lookup_full_r;
    logic [8:0]  lookup_dest_r;
    logic        ev_valid;
    logic [10:0] ev_index;
    logic [31:0] ev_c0;
    logic [31:0] ev_c1;
    logic        ev_ok;
    logic        ev2_valid;
    logic [10:0] ev2_index;
    logic [31:0] ev2_c0;
    logic [31:0] ev2_c1;
    logic        ev2_ok;
    logic        bubble_r;
    logic        sweep_done_seen;

    // Capture-time event health (evaluated on the raw telemetry inputs, in
    // parallel with the table lookup -- never chained after it).
    wire pair_ok = tel_stable && !tel_timeout && !tel_ovf_a && !tel_ovf_b &&
                   (tel_count0 != 32'd0) && (tel_count1 != 32'd0) &&
                   mmcm_locked;

    // Decision-time compare against the pre-registered lookup.
    wire ev_match = ev_valid && (sel_ptr < PUF64_MAP_PAIR_COUNT) &&
                    (ev_index == lookup_full_r);
    wire ev_past  = ev_valid && (sel_ptr < PUF64_MAP_PAIR_COUNT) &&
                    (ev_index > lookup_full_r);
    wire ev_tie   = ev_match && (ev_c0 == ev_c1);
    wire tie_ok   = ev_tie && (tie_count < TIE_BUDGET);
    wire ev_err   = ev_valid && (!ev_ok || ev_past || (ev_tie && !tie_ok));
    wire consume  = ev_valid && !bubble_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state               <= S_IDLE;
            sel_ptr             <= 9'd0;
            count               <= 9'd0;
            tie_count           <= 3'd0;
            error_sticky        <= 1'b0;
            response_r          <= '0;
            mapped_response     <= '0;
            mapped_response_valid <= 1'b0;
            mapped_response_error <= 1'b0;
            mapped_error_reason <= 4'h0;
            busy                <= 1'b0;
            selected_count      <= 9'd0;
            lookup_full_r       <= 11'd0;
            lookup_dest_r       <= 9'd0;
            ev_valid            <= 1'b0;
            ev2_valid           <= 1'b0;
            bubble_r            <= 1'b0;
            sweep_done_seen     <= 1'b0;
        end else if (zeroize) begin
            state               <= S_IDLE;
            sel_ptr             <= 9'd0;
            count               <= 9'd0;
            tie_count           <= 3'd0;
            error_sticky        <= 1'b0;
            response_r          <= '0;
            mapped_response     <= '0;
            mapped_response_valid <= 1'b0;
            mapped_response_error <= 1'b0;
            mapped_error_reason <= 4'h0;
            busy                <= 1'b0;
            selected_count      <= 9'd0;
            lookup_full_r       <= 11'd0;
            lookup_dest_r       <= 9'd0;
            ev_valid            <= 1'b0;
            ev2_valid           <= 1'b0;
            bubble_r            <= 1'b0;
            sweep_done_seen     <= 1'b0;
        end else begin
            // The lookup tracks the live sel_ptr every cycle so it is fresh
            // for the next decision even across resets, restarts and bubbles.
            lookup_full_r <= puf64_map_sorted_full(sel_ptr);
            lookup_dest_r <= puf64_map_sorted_dest(sel_ptr);
            case (state)
                S_IDLE: begin
                    mapped_response_valid <= 1'b0;
                    mapped_response_error <= 1'b0;
                    mapped_error_reason    <= 4'h0;
                    error_sticky          <= 1'b0;
                    response_r            <= '0;
                    sel_ptr               <= 9'd0;
                    count                 <= 9'd0;
                    tie_count             <= 3'd0;
                    selected_count        <= 9'd0;
                    busy                  <= 1'b0;
                    ev_valid              <= 1'b0;
                    ev2_valid             <= 1'b0;
                    bubble_r              <= 1'b0;
                    sweep_done_seen       <= 1'b0;
                    if (start) begin
                        busy  <= 1'b1;
                        state <= S_SWEEP;
                    end
                end

                S_SWEEP: begin
                    if (consume) begin
                        // Decide the pending event against the pre-registered
                        // lookup, then shift the FIFO (a same-cycle arrival
                        // below takes the freed slot, preserving order).
                        if (tie_ok) begin
                            // Correctable selected tie: store deterministic 0
                            // for the BCH (t=8) + KCV gate downstream. Same
                            // commit shape as a match so the lookup refreshes
                            // to the next entry before the next decision.
                            response_r[lookup_dest_r] <= 1'b0;
                            sel_ptr <= sel_ptr + 9'd1;
                            count   <= count + 9'd1;
                            selected_count <= count + 9'd1;
                            tie_count <= tie_count + 3'd1;
                            bubble_r <= 1'b1;
                            ev_index <= ev2_index;
                            ev_c0    <= ev2_c0;
                            ev_c1    <= ev2_c1;
                            ev_ok    <= ev2_ok;
                            ev_valid <= ev2_valid;
                            ev2_valid <= 1'b0;
                        end else if (ev_err) begin
                            error_sticky <= 1'b1;
                            if (!ev_ok) begin
                                if (!mmcm_locked)
                                    mapped_error_reason <= 4'h4;
                                else if (ev_c0 == 32'd0 || ev_c1 == 32'd0)
                                    mapped_error_reason <= 4'h3;
                                else
                                    mapped_error_reason <= 4'h1;
                            end else if (ev_tie)
                                mapped_error_reason <= 4'h5;
                            else
                                mapped_error_reason <= 4'h6;
                            state        <= S_ERROR;
                            ev_valid     <= 1'b0;
                            ev2_valid    <= 1'b0;
                            bubble_r     <= 1'b0;
                        end else if (ev_match) begin
                            response_r[lookup_dest_r] <=
                                (ev_c0 < ev_c1) ? 1'b1 : 1'b0;
                            sel_ptr <= sel_ptr + 9'd1;
                            count   <= count + 9'd1;
                            selected_count <= count + 9'd1;
                            bubble_r <= 1'b1;
                            ev_index <= ev2_index;
                            ev_c0    <= ev2_c0;
                            ev_c1    <= ev2_c1;
                            ev_ok    <= ev2_ok;
                            ev_valid <= ev2_valid;
                            ev2_valid <= 1'b0;
                        end else begin
                            ev_index <= ev2_index;
                            ev_c0    <= ev2_c0;
                            ev_c1    <= ev2_c1;
                            ev_ok    <= ev2_ok;
                            ev_valid <= ev2_valid;
                            ev2_valid <= 1'b0;
                        end
                    end else if (bubble_r) begin
                        bubble_r <= 1'b0;
                    end
                    if (tel_valid) begin
                        if (consume) begin
                            if (ev2_valid) begin
                                ev2_index <= tel_index;
                                ev2_c0    <= tel_count0;
                                ev2_c1    <= tel_count1;
                                ev2_ok    <= pair_ok;
                                ev2_valid <= 1'b1;
                            end else begin
                                ev_index <= tel_index;
                                ev_c0    <= tel_count0;
                                ev_c1    <= tel_count1;
                                ev_ok    <= pair_ok;
                                ev_valid <= 1'b1;
                            end
                        end else if (!ev_valid) begin
                            ev_index <= tel_index;
                            ev_c0    <= tel_count0;
                            ev_c1    <= tel_count1;
                            ev_ok    <= pair_ok;
                            ev_valid <= 1'b1;
                        end else if (!ev2_valid) begin
                            ev2_index <= tel_index;
                            ev2_c0    <= tel_count0;
                            ev2_c1    <= tel_count1;
                            ev2_ok    <= pair_ok;
                            ev2_valid <= 1'b1;
                        end else begin
                            // FIFO full while stalled: fail closed, never drop.
                            error_sticky <= 1'b1;
                            mapped_error_reason <= 4'h7;
                            state        <= S_ERROR;
                            ev_valid     <= 1'b0;
                            ev2_valid    <= 1'b0;
                            bubble_r     <= 1'b0;
                        end
                    end
                    if (sweep_done)
                        sweep_done_seen <= 1'b1;
                    // Event after the sweep end (other than the same-cycle
                    // coincident last event) is a protocol violation.
                    if (sweep_done_seen && tel_valid && !sweep_done) begin
                        error_sticky <= 1'b1;
                        mapped_error_reason <= 4'h8;
                        state        <= S_ERROR;
                        ev_valid     <= 1'b0;
                        ev2_valid    <= 1'b0;
                        bubble_r     <= 1'b0;
                    end
                    // Drain-safe finish: only after the last event committed,
                    // the bubble elapsed and the FIFO is empty.  The final
                    // selected bit is never dropped and selected_count is
                    // never evaluated before the drain completes.
                    if (sweep_done_seen && !ev_valid && !ev2_valid &&
                            !bubble_r && !tel_valid) begin
                        if (sel_ptr == PUF64_MAP_PAIR_COUNT &&
                                count == PUF64_MAP_PAIR_COUNT &&
                                !error_sticky)
                            state <= S_FINISH;
                        else begin
                            error_sticky <= 1'b1;
                            mapped_error_reason <= 4'h9;
                            state        <= S_ERROR;
                        end
                    end
                end

                S_FINISH: begin
                    mapped_response <= response_r;
                    if (count == PUF64_MAP_PAIR_COUNT && !error_sticky) begin
                        mapped_response_valid <= 1'b1;
                        if (mapped_response_valid && mapped_response_ready) begin
                            mapped_response_valid <= 1'b0;
                            mapped_response       <= '0;
                            busy                  <= 1'b0;
                            state                 <= S_IDLE;
                        end
                    end else begin
                        error_sticky <= 1'b1;
                        mapped_error_reason <= 4'ha;
                        state        <= S_ERROR;
                    end
                end

                S_ERROR: begin
                    mapped_response       <= '0;
                    mapped_response_valid <= 1'b0;
                    mapped_response_error <= 1'b1;
                    response_r            <= '0;
                    busy                  <= 1'b0;
                    // Sticky until reset or an explicit new start.
                    if (start) begin
                        mapped_response_error <= 1'b0;
                        mapped_error_reason    <= 4'h0;
                        error_sticky          <= 1'b0;
                        count                 <= 9'd0;
                        tie_count             <= 3'd0;
                        selected_count        <= 9'd0;
                        sel_ptr               <= 9'd0;
                        busy                  <= 1'b1;
                        ev_valid              <= 1'b0;
                        ev2_valid             <= 1'b0;
                        bubble_r              <= 1'b0;
                        sweep_done_seen       <= 1'b0;
                        state                 <= S_SWEEP;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (rst_n && mapped_response_valid && (busy == 1'b0) && (state != S_FINISH))
            $error("mapped response valid outside the finish handshake");
    end
`endif
endmodule

`default_nettype wire
