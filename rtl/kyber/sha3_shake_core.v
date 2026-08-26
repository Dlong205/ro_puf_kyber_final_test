`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// sha3_shake_core.v — FIPS-202 compliant Keccak sponge controller
//
// Reuses the existing ALGORITHM 24-round permutation datapath (same hookup
// as the legacy keccak_f1600_server).
//
//   * Absorb : 32-bit message words XORed directly at their lane position
//              (whole-word messages assumed — true for all Kyber inputs)
//   * Padding: FIPS pad10*1 generated internally from the actual message
//              length; domain 0x06 (SHA3*) / 0x1F (SHAKE*); handles the
//              full-block edge case with an extra padding-only block
//   * Squeeze: streams state[31:0] LSB-first; automatically chains
//              permutations for outputs longer than one block; dout_valid
//              stalls while a block is being permuted
//
// Mode map (latched at init):
//   0 = SHA3-512  (rate 72 B  = 18 words)
//   1 = SHAKE256  (rate 136 B = 34 words)
//   2 = SHAKE128  (rate 168 B = 42 words)
//   3 = SHA3-256  (rate 136 B = 34 words)
//-----------------------------------------------------------------------------
module sha3_shake_core(
    input  wire        clk,
    input  wire        rst,
    input  wire        init,        // 1-clk pulse: clear sponge, latch mode
    input  wire [1:0]  mode,
    // message absorb
    input  wire        wr_en,       // accept din this cycle
    input  wire [31:0] din,
    input  wire        wr_last,     // this word is the final message word
    output wire        busy,        // high: cannot accept message words
    // squeeze stream
    input  wire        rd_en,       // consume dout this cycle
    output wire [31:0] dout,
    output wire        dout_valid,
    output wire        done         // 1-clk pulse: a fresh block is available
);

    // ----------------------------------------------------------
    // Rate / domain table
    // ----------------------------------------------------------
    reg [5:0] rate_words;
    reg [31:0] dom_word;
    always @(*) begin
        case (mode_latched)
            2'd0: begin rate_words = 6'd18; dom_word = 32'h00000006; end // SHA3-512
            2'd1: begin rate_words = 6'd34; dom_word = 32'h0000001f; end // SHAKE256
            2'd2: begin rate_words = 6'd42; dom_word = 32'h0000001f; end // SHAKE128
            default: begin rate_words = 6'd34; dom_word = 32'h00000006; end // SHA3-256
        endcase
    end

    // ----------------------------------------------------------
    // State registers
    // ----------------------------------------------------------
    reg [1599:0] block_reg;      // rate-block accumulator / next-block source
    reg [1599:0] squeeze_reg;    // state currently being streamed out
    reg [1599:0] block_perm_src; // snapshot feeding the permutation
    reg [1599:0] base_state;     // unrotated permutation result (chain source)
    reg [1:0]    mode_latched;

    reg [5:0]    wr_idx;         // message words accumulated in block_reg
    reg [5:0]    rd_idx;         // words streamed out of current block

    reg          have_block;     // block_reg holds a padded block to permute
    reg          ready_flag;     // squeeze_reg holds a valid streamable block
    reg          pad_extra;      // need an extra padding-only block

    // permutation control (legacy-compatible hookup)
    reg [4:0]    round_count;
    reg [1:0]    perm_state;     // 0 IDLE, 1 PERMUTE, 2 DONE
    reg          perm_active;

    localparam S_IDLE = 2'd0, S_PERMUTE = 2'd1, S_DONE = 2'd2, S_CAPTURE = 2'd3;

    wire permuting  = (perm_state != S_IDLE);
    wire start_perm = have_block && (perm_state == S_IDLE);
    wire last_round = (round_count == 5'd23);

    assign busy       = permuting | have_block;
    assign dout       = squeeze_reg[31:0];
    assign dout_valid = ready_flag && !permuting;

    reg ready_q;
    always @(posedge clk or posedge rst) begin
        if (rst)
            ready_q <= 1'b0;
        else
            ready_q <= ready_flag;
    end
    assign done = ready_flag & ~ready_q;

    // ----------------------------------------------------------
    // Permutation datapath (identical structure to legacy core)
    // ----------------------------------------------------------
    wire [1599:0] algo_out;
    wire [1599:0] algo_in = (round_count == 5'd0) ? block_perm_src : algo_out;
    wire [4:0]    rc_flag;

    ALGORITHM algo_inst (
        .Clk        (clk),
        .reset      (~rst),
        .en_in      (perm_active),
        .en_ctr     (perm_active),
        .padding_in (algo_in),
        .RC_id_in   (round_count),
        .RC_flag    (rc_flag),
        .data_out   (algo_out)
    );

    // ----------------------------------------------------------
    // Sequencer
    // ----------------------------------------------------------
    reg [31:0] tail_xor;      // pending trailing-mark deposit
    reg        tail_pending;
    integer i;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            block_reg      <= 1600'h0;
            squeeze_reg    <= 1600'h0;
            block_perm_src <= 1600'h0;
            mode_latched   <= 2'd0;
            wr_idx         <= 6'd0;
            rd_idx         <= 6'd0;
            have_block     <= 1'b0;
            ready_flag     <= 1'b0;
            pad_extra      <= 1'b0;
            round_count    <= 5'd0;
            perm_state     <= S_IDLE;
            perm_active    <= 1'b0;
        end else begin
            // ---------------- permutation engine ----------------
            case (perm_state)
                S_IDLE: begin
                    if (start_perm) begin
                        block_perm_src <= block_reg;
                        have_block     <= 1'b0;
                        perm_state     <= S_PERMUTE;
                        perm_active    <= 1'b1;
                        round_count    <= 5'd0;
                    end
                end
                S_PERMUTE: begin
                    round_count <= round_count + 5'd1;
                    if (last_round) begin
                        perm_state <= S_CAPTURE;   // keep enables high 1 more cycle
                    end
                end
                S_CAPTURE: begin
                    // algo_out holds the final state now (IOTA registered at
                    // the edge entering this cycle); latch it, then drop en.
                    squeeze_reg <= algo_out;
                    base_state  <= algo_out;
                    rd_idx      <= 6'd0;
                    ready_flag  <= 1'b1;
                    perm_active <= 1'b0;
                    perm_state  <= S_IDLE;
                    if (pad_extra) begin
                        // queue a padding-only continuation block
                        for (i = 0; i < 50; i = i + 1)
                            block_reg[i*32 +: 32] <= 32'h0;
                        block_reg[0 +: 32]                 <= dom_word;
                        block_reg[32*(rate_words-1) +: 32] <= 32'h80000000;
                        have_block <= 1'b1;
                        pad_extra  <= 1'b0;
                    end
                end
                default: perm_state <= S_IDLE;
            endcase

            // ---------------- absorb side ----------------
            // NOTE: the Kyber FSM asserts init multiple times per operation
            // (states 1/19/22 legacy artefact). Only honour it as a true
            // start-of-message when nothing has been absorbed yet; otherwise
            // it must NOT wipe partially absorbed data.
            if (init) begin
                mode_latched <= mode;
                if (wr_idx == 6'd0 && !have_block) begin
                    block_reg    <= 1600'h0;
                    wr_idx       <= 6'd0;
                    have_block   <= 1'b0;
                    ready_flag   <= 1'b0;
                    pad_extra    <= 1'b0;
                    tail_pending <= 1'b0;
                end
            end else if (wr_en && !have_block && !permuting) begin
                if (wr_last) begin
                    // FIPS pad10*1: domain byte goes AFTER the message
                    // (byte 0 of the NEXT word), 0x80 marks the final byte
                    // of the block. Deposits are same-edge NBAs on
                    // disjoint slices.
                    block_reg[32*wr_idx +: 32] <= block_reg[32*wr_idx +: 32] ^ din;
                    if (wr_idx == rate_words-1) begin
                        // no room in this block: domain opens the next one
                        pad_extra <= 1'b1;
                    end else begin
                        block_reg[32*(wr_idx+1) +: 32] <= dom_word;
                        if (wr_idx+1 != rate_words-1)
                            block_reg[32*(rate_words-1) +: 32] <=
                                block_reg[32*(rate_words-1) +: 32] ^ 32'h80000000;
                        else
                            block_reg[32*(wr_idx+1) +: 32] <=
                                dom_word ^ 32'h80000000;
                        pad_extra <= 1'b0;
                    end
                    have_block <= 1'b1;
                    wr_idx     <= 6'd0;
                end else begin
                    block_reg[32*wr_idx +: 32] <= block_reg[32*wr_idx +: 32] ^ din;
                    wr_idx <= wr_idx + 6'd1;
                end
            end

            // ---------------- squeeze side ----------------
            if (rd_en && ready_flag && !permuting) begin
                squeeze_reg <= {squeeze_reg[31:0], squeeze_reg[1599:32]};
                if (rd_idx == rate_words - 1) begin
                    // block exhausted: re-permute the full current state
                    rd_idx     <= 6'd0;
                    ready_flag <= 1'b0;
                    block_reg  <= base_state;
                    have_block <= 1'b1;
                end else begin
                    rd_idx <= rd_idx + 6'd1;
                end
            end
        end
    end

endmodule
