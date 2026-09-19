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
//   * tie on a SELECTED pair  -> whole mapped response invalid (sticky error).
//   * tie on an UNSELECTED pair -> ignored (qualification observed them).
//   * timeout / overflow / count-zero / MMCM unlock on ANY pair -> sticky
//     sweep error and fail-closed; the partial response is erased.
//
// The response is held stable until mapped_response_ready and is zeroized when
// consumed.  A new start or reset clears response/bitmap/error.
module kp_puf64_mapping_scheduler #(
    parameter integer NUM_RO = 64,
    parameter integer PAIR_COUNT = 2016,
    parameter integer LEN_BITS = 264
)(
    input  logic               clk,
    input  logic               rst_n,
    input  logic               zeroize,
    input  logic               start,

    // Canonical sweep telemetry: one valid pulse per pair, in index order.
    input  logic               tel_valid,
    input  logic [10:0]        tel_index,
    input  logic [5:0]         tel_pair_a,
    input  logic [5:0]         tel_pair_b,
    input  logic [31:0]        tel_count0,
    input  logic [31:0]        tel_count1,
    input  logic               tel_stable,
    input  logic               tel_timeout,
    input  logic               tel_ovf_a,
    input  logic               tel_ovf_b,
    input  logic               mmcm_locked,
    input  logic               sweep_done,

    // Mapped response handshake.
    output logic [LEN_BITS-1:0] mapped_response,
    output logic                mapped_response_valid,
    input  logic                mapped_response_ready,
    output logic                mapped_response_error,
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
    logic       error_sticky;
    logic [LEN_BITS-1:0] response_r;

    wire pair_ok = tel_stable && !tel_timeout && !tel_ovf_a && !tel_ovf_b &&
                   (tel_count0 != 32'd0) && (tel_count1 != 32'd0) &&
                   mmcm_locked;
    wire [8:0] selected_dest  = puf64_map_sorted_dest(sel_ptr);
    wire selected_match = (sel_ptr < PUF64_MAP_PAIR_COUNT) &&
                          (tel_index == puf64_map_sorted_full(sel_ptr));
    wire selected_past  = (sel_ptr < PUF64_MAP_PAIR_COUNT) &&
                          (tel_index > puf64_map_sorted_full(sel_ptr));
    wire selected_tie   = selected_match && (tel_count0 == tel_count1);
    wire error_now      = tel_valid && (!pair_ok || selected_tie);
    wire [8:0] sel_ptr_next = selected_match ? (sel_ptr + 9'd1) : sel_ptr;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state               <= S_IDLE;
            sel_ptr             <= 9'd0;
            count               <= 9'd0;
            error_sticky        <= 1'b0;
            response_r          <= '0;
            mapped_response     <= '0;
            mapped_response_valid <= 1'b0;
            mapped_response_error <= 1'b0;
            busy                <= 1'b0;
            selected_count      <= 9'd0;
        end else if (zeroize) begin
            state               <= S_IDLE;
            sel_ptr             <= 9'd0;
            count               <= 9'd0;
            error_sticky        <= 1'b0;
            response_r          <= '0;
            mapped_response     <= '0;
            mapped_response_valid <= 1'b0;
            mapped_response_error <= 1'b0;
            busy                <= 1'b0;
            selected_count      <= 9'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    mapped_response_valid <= 1'b0;
                    mapped_response_error <= 1'b0;
                    error_sticky          <= 1'b0;
                    response_r            <= '0;
                    sel_ptr               <= 9'd0;
                    count                 <= 9'd0;
                    selected_count        <= 9'd0;
                    busy                  <= 1'b0;
                    if (start) begin
                        busy  <= 1'b1;
                        state <= S_SWEEP;
                    end
                end

                S_SWEEP: begin
                    if (tel_valid) begin
                        if (!pair_ok) begin
                            error_sticky <= 1'b1;
                            state        <= S_ERROR;
                        end else if (selected_tie) begin
                            error_sticky <= 1'b1;
                            state        <= S_ERROR;
                        end else if (selected_match) begin
                            response_r[selected_dest] <=
                                (tel_count0 < tel_count1) ? 1'b1 : 1'b0;
                            sel_ptr <= sel_ptr + 9'd1;
                            count   <= count + 9'd1;
                            selected_count <= count + 9'd1;
                        end else if (selected_past) begin
                            error_sticky <= 1'b1;
                            state        <= S_ERROR;
                        end
                    end
                    if (sweep_done) begin
                        if (sel_ptr_next == PUF64_MAP_PAIR_COUNT &&
                                !error_sticky && !error_now)
                            state <= S_FINISH;
                        else begin
                            error_sticky <= 1'b1;
                            state        <= S_ERROR;
                        end
                    end
                end

                S_FINISH: begin
                    mapped_response <= response_r;
                    if (count == PUF64_MAP_PAIR_COUNT && !error_sticky) begin
                        mapped_response_valid <= 1'b1;
                        if (mapped_response_ready) begin
                            mapped_response_valid <= 1'b0;
                            mapped_response       <= '0;
                            busy                  <= 1'b0;
                            state                 <= S_IDLE;
                        end
                    end else begin
                        error_sticky <= 1'b1;
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
                        error_sticky          <= 1'b0;
                        count                 <= 9'd0;
                        selected_count        <= 9'd0;
                        sel_ptr               <= 9'd0;
                        busy                  <= 1'b1;
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
