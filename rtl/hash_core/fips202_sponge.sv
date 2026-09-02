`timescale 1ns / 1ps
`default_nettype none

// FIPS 202 byte-stream sponge controller.
//
// This module supplies the general message-length and multi-block behaviour
// that the legacy Kyber word-stream wrapper does not provide.  It reuses the
// project's existing 24-round Keccak-f[1600] datapath (ALGORITHM).
//
// Mode encoding:
//   2'b00: SHA3-512  (rate 72 bytes,  domain 0x06, output 64 bytes)
//   2'b01: SHAKE256  (rate 136 bytes, domain 0x1f)
//   2'b10: SHAKE128  (rate 168 bytes, domain 0x1f)
//   2'b11: SHA3-256  (rate 136 bytes, domain 0x06, output 32 bytes)
//
// Protocol:
//   * Pulse start for one cycle while busy is low.
//   * msg_len_bytes is the exact number of bytes that will be accepted.
//   * Hold in_valid/in_data until in_ready is high.
//   * Consume output only on out_valid && out_ready.
//   * done and error are one-cycle completion pulses.
module fips202_sponge (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [1:0]   mode,
    input  wire [31:0]  msg_len_bytes,
    input  wire [31:0]  out_len_bytes,

    input  wire         in_valid,
    output wire         in_ready,
    input  wire [7:0]   in_data,

    output wire         out_valid,
    input  wire         out_ready,
    output wire [7:0]   out_data,
    output wire         out_last,

    output wire         busy,
    output reg          done,
    output reg          error
);

    localparam [3:0] ST_IDLE         = 4'd0;
    localparam [3:0] ST_ABSORB       = 4'd1;
    localparam [3:0] ST_PAD          = 4'd2;
    localparam [3:0] ST_PERM_START   = 4'd3;
    localparam [3:0] ST_PERMUTE      = 4'd4;
    localparam [3:0] ST_PERM_CAPTURE = 4'd5;
    localparam [3:0] ST_SQUEEZE      = 4'd6;
    localparam [3:0] ST_DONE         = 4'd7;
    localparam [3:0] ST_RESET_CLEAR  = 4'd8;

    localparam [1:0] PERM_ABSORB_CONT = 2'd0;
    localparam [1:0] PERM_PAD_EXTRA   = 2'd1;
    localparam [1:0] PERM_FINAL       = 2'd2;
    localparam [1:0] PERM_SQUEEZE     = 2'd3;

    reg [3:0]    state;
    reg [1:0]    mode_latched;
    reg [1:0]    perm_reason;
    reg [7:0]    rate_bytes;
    reg [7:0]    domain_byte;
    reg [7:0]    absorb_pos;
    reg [7:0]    squeeze_pos;
    reg [31:0]   msg_remaining;
    reg [31:0]   out_remaining;

    // These wide registers intentionally have no asynchronous reset assignment.
    // ST_RESET_CLEAR clears them on the first clock after reset is released,
    // while start and ST_DONE also clear transaction material.  This avoids
    // forcing reset pins onto 3200 datapath bits without retaining stale state.
    reg [1599:0] sponge_state;
    reg [1599:0] perm_input;

    reg [4:0] round_count;
    reg       perm_active;

    wire [1599:0] algo_out;
    wire [1599:0] algo_in;
    wire [4:0]    rc_flag_unused;

    assign algo_in = (round_count == 5'd0) ? perm_input : algo_out;

    ALGORITHM permutation (
        .Clk        (clk),
        .reset      (rst_n),
        .en_in      (perm_active),
        .en_ctr     (perm_active),
        .padding_in (algo_in),
        .RC_id_in   (round_count),
        .RC_flag    (rc_flag_unused),
        .data_out   (algo_out)
    );

    assign in_ready  = (state == ST_ABSORB) && (msg_remaining != 32'd0);
    assign out_valid = (state == ST_SQUEEZE) && (out_remaining != 32'd0);
    assign out_data  = sponge_state[(squeeze_pos * 8) +: 8];
    assign out_last  = out_valid && (out_remaining == 32'd1);
    assign busy      = (state != ST_IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= ST_RESET_CLEAR;
            mode_latched   <= 2'b00;
            perm_reason    <= PERM_FINAL;
            rate_bytes     <= 8'd0;
            domain_byte    <= 8'd0;
            absorb_pos     <= 8'd0;
            squeeze_pos    <= 8'd0;
            msg_remaining  <= 32'd0;
            out_remaining  <= 32'd0;
            round_count    <= 5'd0;
            perm_active    <= 1'b0;
            done           <= 1'b0;
            error          <= 1'b0;
        end else begin
            done  <= 1'b0;
            error <= 1'b0;

            case (state)
                ST_RESET_CLEAR: begin
                    sponge_state <= 1600'd0;
                    perm_input   <= 1600'd0;
                    state        <= ST_IDLE;
                end

                ST_IDLE: begin
                    perm_active <= 1'b0;
                    if (start) begin
                        // SHA3 has a fixed digest size.  Reject accidental
                        // truncation/extension instead of silently producing
                        // a non-standard result.  SHAKE permits any length,
                        // including zero bytes.
                        if (((mode == 2'b00) && (out_len_bytes != 32'd64)) ||
                            ((mode == 2'b11) && (out_len_bytes != 32'd32))) begin
                            done  <= 1'b1;
                            error <= 1'b1;
                        end else begin
                            mode_latched  <= mode;
                            absorb_pos    <= 8'd0;
                            squeeze_pos   <= 8'd0;
                            msg_remaining <= msg_len_bytes;
                            out_remaining <= out_len_bytes;
                            round_count   <= 5'd0;
                            sponge_state  <= 1600'd0;
                            perm_input    <= 1600'd0;

                            case (mode)
                                2'b00: begin
                                    rate_bytes  <= 8'd72;
                                    domain_byte <= 8'h06;
                                end
                                2'b01: begin
                                    rate_bytes  <= 8'd136;
                                    domain_byte <= 8'h1f;
                                end
                                2'b10: begin
                                    rate_bytes  <= 8'd168;
                                    domain_byte <= 8'h1f;
                                end
                                default: begin
                                    rate_bytes  <= 8'd136;
                                    domain_byte <= 8'h06;
                                end
                            endcase

                            if (msg_len_bytes == 32'd0)
                                state <= ST_PAD;
                            else
                                state <= ST_ABSORB;
                        end
                    end
                end

                ST_ABSORB: begin
                    if (in_valid && in_ready) begin
                        sponge_state[(absorb_pos * 8) +: 8] <=
                            sponge_state[(absorb_pos * 8) +: 8] ^ in_data;
                        msg_remaining <= msg_remaining - 32'd1;

                        if (absorb_pos == rate_bytes - 8'd1) begin
                            absorb_pos <= 8'd0;
                            state      <= ST_PERM_START;
                            if (msg_remaining == 32'd1)
                                perm_reason <= PERM_PAD_EXTRA;
                            else
                                perm_reason <= PERM_ABSORB_CONT;
                        end else begin
                            absorb_pos <= absorb_pos + 8'd1;
                            if (msg_remaining == 32'd1)
                                state <= ST_PAD;
                        end
                    end
                end

                ST_PAD: begin
                    // FIPS 202 delimited suffix followed by pad10*1.  If both
                    // markers share the last rate byte they are XORed once.
                    if (absorb_pos == rate_bytes - 8'd1) begin
                        sponge_state[(absorb_pos * 8) +: 8] <=
                            sponge_state[(absorb_pos * 8) +: 8] ^
                            domain_byte ^ 8'h80;
                    end else begin
                        sponge_state[(absorb_pos * 8) +: 8] <=
                            sponge_state[(absorb_pos * 8) +: 8] ^ domain_byte;
                        sponge_state[((rate_bytes - 8'd1) * 8) +: 8] <=
                            sponge_state[((rate_bytes - 8'd1) * 8) +: 8] ^ 8'h80;
                    end
                    perm_reason <= PERM_FINAL;
                    state       <= ST_PERM_START;
                end

                ST_PERM_START: begin
                    // Snapshot one cycle after the last absorb/pad write so
                    // nonblocking assignments are included in the permutation.
                    perm_input  <= sponge_state;
                    round_count <= 5'd0;
                    perm_active <= 1'b1;
                    state       <= ST_PERMUTE;
                end

                ST_PERMUTE: begin
                    if (round_count == 5'd23) begin
                        // ALGORITHM registers IOTA at this edge.  Keep enables
                        // high through the following capture cycle.
                        round_count <= round_count + 5'd1;
                        state       <= ST_PERM_CAPTURE;
                    end else begin
                        round_count <= round_count + 5'd1;
                    end
                end

                ST_PERM_CAPTURE: begin
                    sponge_state <= algo_out;
                    round_count  <= 5'd0;
                    perm_active  <= 1'b0;

                    case (perm_reason)
                        PERM_ABSORB_CONT: begin
                            absorb_pos <= 8'd0;
                            state      <= ST_ABSORB;
                        end
                        PERM_PAD_EXTRA: begin
                            absorb_pos <= 8'd0;
                            state      <= ST_PAD;
                        end
                        PERM_FINAL: begin
                            squeeze_pos <= 8'd0;
                            if (out_remaining == 32'd0)
                                state <= ST_DONE;
                            else
                                state <= ST_SQUEEZE;
                        end
                        default: begin
                            squeeze_pos <= 8'd0;
                            state       <= ST_SQUEEZE;
                        end
                    endcase
                end

                ST_SQUEEZE: begin
                    if (out_valid && out_ready) begin
                        out_remaining <= out_remaining - 32'd1;
                        if (out_remaining == 32'd1) begin
                            state <= ST_DONE;
                        end else if (squeeze_pos == rate_bytes - 8'd1) begin
                            squeeze_pos <= 8'd0;
                            perm_reason <= PERM_SQUEEZE;
                            state       <= ST_PERM_START;
                        end else begin
                            squeeze_pos <= squeeze_pos + 8'd1;
                        end
                    end
                end

                ST_DONE: begin
                    // Clear intermediate material at the transaction boundary.
                    sponge_state <= 1600'd0;
                    perm_input   <= 1600'd0;
                    done         <= 1'b1;
                    state        <= ST_IDLE;
                end

                default: begin
                    state       <= ST_IDLE;
                    perm_active <= 1'b0;
                    done        <= 1'b1;
                    error       <= 1'b1;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
