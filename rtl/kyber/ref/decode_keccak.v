`timescale 1ns / 1ps

// Convert the 32-bit little-endian SHAKE stream into the units consumed by
// the Kyber datapath:
//   * eta=3 noise and matrix rejection sampling: 3 x 32 -> 4 x 24 bits
//   * eta=2 noise:                              1 x 32 -> 2 x 16 bits
//
// The input FIFO has a registered (one-cycle) read output. Separate request
// and capture states make that latency explicit and flush every complete
// group even when there is a gap between two SHAKE rate blocks.
module decode_keccak(
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] din,
    input  wire        fifo_empty,
    input  wire        patt_bit,
    input  wire        eta3_bit,
    input  wire [3:0]  stream_id,
    output reg  [23:0] dout,
    output reg         req,
    output reg         valid,
    output reg         patt_out,
    output reg         eta3_out,
    output reg  [3:0]  stream_out
);

localparam [3:0]
    S_REQ0  = 4'h0,
    S_CAP0  = 4'h1,
    S_REQ1  = 4'h2,
    S_CAP1  = 4'h3,
    S_REQ2  = 4'h4,
    S_CAP2  = 4'h5,
    S_OUT0  = 4'h6,
    S_OUT1  = 4'h7,
    S_OUT2  = 4'h8,
    S_OUT3  = 4'h9,
    S_HALF0 = 4'ha,
    S_HALF1 = 4'hb;

reg [3:0] state;
reg [31:0] word0, word1, word2;
reg group_patt, group_eta3;
reg [3:0] group_stream;

wire full_width_group = eta3_bit | ~patt_bit;
wire group_is_noise = group_patt | group_eta3;
wire input_is_noise = patt_bit | eta3_bit;
wire input_boundary = (group_is_noise != input_is_noise) ||
                      (!input_is_noise && (group_stream != stream_id));

always @(posedge clk) begin
    if (rst) begin
        state       <= S_REQ0;
        word0       <= 32'h0;
        word1       <= 32'h0;
        word2       <= 32'h0;
        group_patt  <= 1'b0;
        group_eta3  <= 1'b0;
        group_stream <= 4'h0;
    end else begin
        case (state)
            S_REQ0:  if (!fifo_empty) state <= S_CAP0;
            S_CAP0: begin
                word0      <= din;
                group_patt <= patt_bit;
                group_eta3 <= eta3_bit;
                group_stream <= stream_id;
                state      <= full_width_group ? S_REQ1 : S_HALF0;
            end
            S_REQ1:  if (!fifo_empty) state <= S_CAP1;
            S_CAP1: begin
                // Matrix rejection sampling may stop with one or two raw
                // words pending.  Never complete that group with the first
                // word of a following PRF stream: discard only the incomplete
                // matrix tail and make the new word the start of its group.
                if (input_boundary) begin
                    word0      <= din;
                    group_patt <= patt_bit;
                    group_eta3 <= eta3_bit;
                    group_stream <= stream_id;
                    state      <= full_width_group ? S_REQ1 : S_HALF0;
                end else begin
                    word1 <= din;
                    state <= S_REQ2;
                end
            end
            S_REQ2:  if (!fifo_empty) state <= S_CAP2;
            S_CAP2: begin
                if (input_boundary) begin
                    word0      <= din;
                    group_patt <= patt_bit;
                    group_eta3 <= eta3_bit;
                    group_stream <= stream_id;
                    state      <= full_width_group ? S_REQ1 : S_HALF0;
                end else begin
                    word2 <= din;
                    state <= S_OUT0;
                end
            end
            S_OUT0:  state <= S_OUT1;
            S_OUT1:  state <= S_OUT2;
            S_OUT2:  state <= S_OUT3;
            S_OUT3:  state <= S_REQ0;
            S_HALF0: state <= S_HALF1;
            S_HALF1: state <= S_REQ0;
            default: state <= S_REQ0;
        endcase
    end
end

always @(*) begin
    req = 1'b0;
    case (state)
        S_REQ0, S_REQ1, S_REQ2: req = ~fifo_empty;
        default: req = 1'b0;
    endcase
end

always @(*) begin
    dout     = 24'h0;
    valid    = 1'b0;
    patt_out = group_patt;
    eta3_out = group_eta3;
    stream_out = group_stream;
    case (state)
        S_OUT0: begin
            dout  = word0[23:0];
            valid = 1'b1;
        end
        S_OUT1: begin
            dout  = {word1[15:0], word0[31:24]};
            valid = 1'b1;
        end
        S_OUT2: begin
            dout  = {word2[7:0], word1[31:16]};
            valid = 1'b1;
        end
        S_OUT3: begin
            dout  = word2[31:8];
            valid = 1'b1;
        end
        S_HALF0: begin
            dout  = {8'h00, word0[15:0]};
            valid = 1'b1;
        end
        S_HALF1: begin
            dout  = {8'h00, word0[31:16]};
            valid = 1'b1;
        end
        default: begin
            dout  = 24'h0;
            valid = 1'b0;
        end
    endcase
end

endmodule
