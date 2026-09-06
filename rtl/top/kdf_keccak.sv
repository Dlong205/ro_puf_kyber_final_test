`timescale 1ns / 1ps
`default_nettype none

// Fixed-profile KDF between the fuzzy extractor and ML-KEM-512.
//
// Function: SHAKE256(key_in[191:0] as 24 little-endian bytes, 64 output
// bytes). This controller intentionally uses the project's compact 32-bit
// Keccak stream datapath. The general byte-stream fips202_sponge remains the
// independently tested reference implementation for arbitrary lengths and
// all four FIPS 202 primitives, but instantiating that general controller here
// costs a second 1600-bit state buffer on FPGA.
module kdf_keccak (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [191:0] key_in,
    output reg          done,
    output reg  [511:0] seed_out
);

    localparam [3:0] ST_IDLE        = 4'd0;
    localparam [3:0] ST_CLEAR       = 4'd1;
    localparam [3:0] ST_INIT        = 4'd2;
    localparam [3:0] ST_ABSORB_KEY  = 4'd3;
    localparam [3:0] ST_DOMAIN      = 4'd4;
    localparam [3:0] ST_PAD_ZERO    = 4'd5;
    localparam [3:0] ST_PAD_FINAL   = 4'd6;
    localparam [3:0] ST_CAPACITY    = 4'd7;
    localparam [3:0] ST_PERM_START  = 4'd8;
    localparam [3:0] ST_PERM_WAIT   = 4'd9;
    localparam [3:0] ST_SQUEEZE     = 4'd10;
    localparam [3:0] ST_DONE        = 4'd11;

    reg [3:0] state;
    reg [3:0] next_state;
    reg [5:0] word_count;
    reg [191:0] key_shift;

    reg         keccak_init;
    reg         keccak_extend;
    reg         keccak_absorb;
    reg         keccak_go;
    reg         keccak_shift;
    reg  [31:0] keccak_din;
    wire        keccak_done;
    wire [31:0] keccak_dout;

    keccak_f1600_server keccak_inst (
        .clk     (clk),
        .rst     (~rst_n),
        .init    (keccak_init),
        .squeeze (keccak_shift),
        .extend  (keccak_extend),
        .absorb  (keccak_absorb),
        .go      (keccak_go),
        .din     (keccak_din),
        .done    (keccak_done),
        .dout    (keccak_dout)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= ST_IDLE;
            word_count <= 6'd0;
            key_shift  <= 192'd0;
            seed_out   <= 512'd0;
            done       <= 1'b0;
        end else begin
            state <= next_state;
            done  <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (start) begin
                        key_shift  <= key_in;
                        seed_out   <= 512'd0;
                        word_count <= 6'd0;
                    end
                end

                ST_CLEAR: word_count <= word_count + 6'd1;
                ST_INIT: word_count <= 6'd0;

                ST_ABSORB_KEY: begin
                    word_count <= word_count + 6'd1;
                    key_shift  <= {32'd0, key_shift[191:32]};
                end

                ST_DOMAIN:   word_count <= word_count + 6'd1;
                ST_PAD_ZERO: word_count <= word_count + 6'd1;

                ST_PAD_FINAL:  word_count <= 6'd0;
                ST_CAPACITY:   word_count <= word_count + 6'd1;
                ST_PERM_START: word_count <= 6'd0;

                ST_SQUEEZE: begin
                    word_count <= word_count + 6'd1;
                    seed_out   <= {keccak_dout, seed_out[511:32]};
                end

                ST_DONE: done <= 1'b1;
                default: ;
            endcase
        end
    end

    always @* begin
        next_state    = state;
        keccak_init   = 1'b0;
        keccak_extend = 1'b0;
        keccak_absorb = 1'b0;
        keccak_go     = 1'b0;
        keccak_shift  = 1'b0;
        keccak_din    = 32'd0;

        case (state)
            ST_IDLE: begin
                if (start)
                    next_state = ST_CLEAR;
            end

            // Fifty zero shifts clear all 1600 state bits without adding a
            // second wide resettable register bank.
            ST_CLEAR: begin
                keccak_shift = 1'b1;
                if (word_count == 6'd49)
                    next_state = ST_INIT;
            end

            ST_INIT: begin
                keccak_init = 1'b1;
                next_state  = ST_ABSORB_KEY;
            end

            // Six little-endian 32-bit words contain the 24-byte key.
            ST_ABSORB_KEY: begin
                keccak_absorb = 1'b1;
                keccak_shift  = 1'b1;
                keccak_din    = key_shift[31:0];
                if (word_count == 6'd5)
                    next_state = ST_DOMAIN;
            end

            // SHAKE256 delimited suffix 0x1f at rate word index 6.
            ST_DOMAIN: begin
                keccak_absorb = 1'b1;
                keccak_shift  = 1'b1;
                keccak_din    = 32'h0000001f;
                next_state    = ST_PAD_ZERO;
            end

            // Zero-fill rate word indices 7..32.
            ST_PAD_ZERO: begin
                keccak_absorb = 1'b1;
                keccak_shift  = 1'b1;
                if (word_count == 6'd32)
                    next_state = ST_PAD_FINAL;
            end

            // Final pad10*1 bit at byte 135 (rate word index 33).
            ST_PAD_FINAL: begin
                keccak_absorb = 1'b1;
                keccak_shift  = 1'b1;
                keccak_din    = 32'h80000000;
                next_state    = ST_CAPACITY;
            end

            // Rotate the sixteen capacity words through unchanged so the
            // stream-oriented state is aligned for Keccak-f[1600].
            ST_CAPACITY: begin
                keccak_extend = 1'b1;
                if (word_count == 6'd15)
                    next_state = ST_PERM_START;
            end

            ST_PERM_START: begin
                keccak_go  = 1'b1;
                next_state = ST_PERM_WAIT;
            end

            ST_PERM_WAIT: begin
                if (keccak_done)
                    next_state = ST_SQUEEZE;
            end

            // The requested 64 bytes fit inside the first SHAKE256 rate block.
            ST_SQUEEZE: begin
                keccak_extend = 1'b1;
                if (word_count == 6'd15)
                    next_state = ST_DONE;
            end

            ST_DONE: begin
                if (!start)
                    next_state = ST_IDLE;
            end

            default: next_state = ST_IDLE;
        endcase
    end

endmodule

`default_nettype wire
