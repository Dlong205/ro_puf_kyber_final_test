`timescale 1ns / 1ps
`default_nettype none

// Launch/zeroize sequencer for one Kyber_Server instance.  A launch always
// begins with reset plus a complete RAM/FIFO scrub.  A security zeroize may
// interrupt any state and follows the same scrub path without launching KEM.
module edge_kem_scrub_controller #(
    parameter integer SCRUB_LAST_ADDR = 2047
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        zeroize,
    input  wire        launch_req,
    input  wire        core_done,
    output wire        ready,
    output wire        busy,
    output wire        done,
    output wire        scrub_done,
    output wire        core_reset,
    output wire        core_start,
    output wire        scrub_en,
    output reg  [10:0] scrub_addr
);
    localparam [2:0] ST_IDLE       = 3'd0;
    localparam [2:0] ST_RESET      = 3'd1;
    localparam [2:0] ST_SCRUB      = 3'd2;
    localparam [2:0] ST_START      = 3'd3;
    localparam [2:0] ST_RUN        = 3'd4;
    localparam [2:0] ST_DONE       = 3'd5;
    localparam [2:0] ST_SCRUB_DONE = 3'd6;

    reg [2:0] state;
    reg       launch_after_scrub;
    reg       launch_seen;
    wire      launch_accept = (state == ST_IDLE) && launch_req && !launch_seen;

    assign ready      = (state == ST_IDLE);
    assign busy       = (state != ST_IDLE) && (state != ST_DONE) &&
                        (state != ST_SCRUB_DONE);
    assign done       = (state == ST_DONE);
    assign scrub_done = (state == ST_SCRUB_DONE);
    assign core_reset = !rst_n || zeroize || (state == ST_RESET) ||
                        (state == ST_SCRUB);
    assign core_start = (state == ST_START);
    assign scrub_en   = (state == ST_SCRUB);

    // Keep the scrub state/address reset synchronous.  Both signals select
    // inferred BRAM ports inside Kyber_Server; an asynchronous reset here
    // propagates onto RAM address pins and triggers Vivado REQP-1839/1840.
    // core_reset remains asserted directly from rst_n, so the accelerator is
    // still held inactive immediately while this sequencer waits for a clock.
    always @(posedge clk) begin
        if (!rst_n) begin
            state              <= ST_IDLE;
            launch_after_scrub <= 1'b0;
            launch_seen        <= 1'b0;
            scrub_addr         <= 11'd0;
        end else if (zeroize) begin
            state              <= ST_RESET;
            launch_after_scrub <= 1'b0;
            launch_seen        <= launch_req;
            scrub_addr         <= 11'd0;
        end else begin
            if (!launch_req)
                launch_seen <= 1'b0;
            else
                launch_seen <= 1'b1;

            case (state)
                ST_IDLE: begin
                    scrub_addr <= 11'd0;
                    if (launch_accept) begin
                        launch_after_scrub <= 1'b1;
                        state <= ST_RESET;
                    end
                end

                ST_RESET: begin
                    scrub_addr <= 11'd0;
                    state <= ST_SCRUB;
                end

                ST_SCRUB: begin
                    if (scrub_addr == SCRUB_LAST_ADDR[10:0]) begin
                        scrub_addr <= 11'd0;
                        if (launch_after_scrub)
                            state <= ST_START;
                        else
                            state <= ST_SCRUB_DONE;
                    end else begin
                        scrub_addr <= scrub_addr + 11'd1;
                    end
                end

                ST_START: begin
                    launch_after_scrub <= 1'b0;
                    state <= ST_RUN;
                end

                ST_RUN: begin
                    if (core_done)
                        state <= ST_DONE;
                end

                ST_DONE: state <= ST_IDLE;
                ST_SCRUB_DONE: state <= ST_IDLE;

                default: begin
                    state              <= ST_RESET;
                    launch_after_scrub <= 1'b0;
                    scrub_addr         <= 11'd0;
                end
            endcase
        end
    end
endmodule

`default_nettype wire
