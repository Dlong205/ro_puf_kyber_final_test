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
    input  wire        hard_init,   // force-clear a partial legacy rate block
    input  wire [1:0]  mode,
    input  wire        pre_padded,  // input consists of complete padded rate blocks
    // message absorb
    input  wire        wr_en,       // accept din this cycle
    input  wire [31:0] din,
    input  wire        wr_xor,      // pre-padded mode: XOR vs overwrite word
    input  wire        wr_last,     // this word is the final message word
    output wire        busy,        // high: cannot accept message words
    // squeeze stream
    input  wire        rd_en,       // consume dout this cycle
    input  wire        rd_extend,   // explicit request to continue past rate
    output wire [31:0] dout,
    output wire        dout_valid,
    output wire        done         // 1-clk pulse: a fresh block is available
);

    // ----------------------------------------------------------
    // Rate / domain table
    // ----------------------------------------------------------
    reg [1:0] mode_latched;
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

    reg          auto_squeeze_perm;

    wire permuting  = (perm_state != S_IDLE);
    wire start_perm = have_block && (perm_state == S_IDLE);
    wire last_round = (round_count == 5'd23);
    wire init_clears = hard_init || auto_squeeze_perm ||
                       (wr_idx == 6'd0 && !have_block);

    assign busy       = permuting | have_block;
    assign dout       = squeeze_reg[31:0];
    assign dout_valid = ready_flag && !permuting;

    // Pulse whenever a permutation result is captured.  Detecting an edge on
    // ready_flag is insufficient because a new absorb/permutation may start
    // while the previous squeeze block still has ready_flag asserted.
    reg done_reg;
    assign done = done_reg;

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
    // Keep the sequencer control reset synchronous.  Several control registers
    // feed inferred block-RAM pins; an asynchronous reset on them triggers
    // REQP-1839/1840.  The four 1600-bit datapath registers intentionally have
    // no reset assignment here: resetting them synchronously costs thousands
    // of LUT input muxes on XC7Z020.  Configuration initializes FPGA registers,
    // and every accepted hard message boundary clears these values before use.
    always @(posedge clk) begin
        if (rst) begin
            mode_latched   <= 2'd0;
            wr_idx         <= 6'd0;
            rd_idx         <= 6'd0;
            have_block     <= 1'b0;
            ready_flag     <= 1'b0;
            pad_extra      <= 1'b0;
            round_count    <= 5'd0;
            perm_state     <= S_IDLE;
            perm_active    <= 1'b0;
            done_reg       <= 1'b0;
            auto_squeeze_perm <= 1'b0;
        end else begin
            done_reg <= 1'b0;

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
                    done_reg    <= 1'b1;
                    if (pre_padded) begin
                        // The Kyber legacy FSM supplies complete rate blocks,
                        // including domain and final 0x80.  Seed the next
                        // absorb block with this permutation result so a
                        // multi-block message chains as Keccak requires.
                        block_reg <= algo_out;
                    end else if (pad_extra) begin
                        // queue a padding-only continuation block
                        for (i = 0; i < 50; i = i + 1)
                            block_reg[i*32 +: 32] <= 32'h0;
                        block_reg[0 +: 32]                 <= dom_word;
                        block_reg[32*(rate_words-1) +: 32] <= 32'h80000000;
                        have_block <= 1'b1;
                        auto_squeeze_perm <= 1'b0;
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
                // Hard message boundaries must discard partial legacy
                // squeeze traffic.  Soft state-11 pulses retain the original
                // guard because they can arrive while a block is in flight.
                if (init_clears) begin
                    block_reg    <= 1600'h0;
                    squeeze_reg  <= 1600'h0;
                    block_perm_src <= 1600'h0;
                    base_state   <= 1600'h0;
                    wr_idx       <= 6'd0;
                    rd_idx       <= 6'd0;
                    have_block   <= 1'b0;
                    ready_flag   <= 1'b0;
                    pad_extra    <= 1'b0;
                    tail_pending <= 1'b0;
                    auto_squeeze_perm <= 1'b0;
                    if (hard_init || auto_squeeze_perm) begin
                        // A hard boundary or auto-squeeze continuation may arrive
                        // while permuting. Abort it so its S_CAPTURE cannot restore
                        // old state.
                        round_count <= 5'd0;
                        perm_state  <= S_IDLE;
                        perm_active <= 1'b0;
                    end
                end
            end

            // A legacy state-11 init pulse can coincide with the FIFO word
            // accepted on this edge.  When that init is only latching mode
            // (not clearing the sponge), the word must still be absorbed.
            // The previous mutually-exclusive `else if` silently dropped it.
            if (wr_en && !have_block && !permuting &&
                !(init && init_clears)) begin
                // In the legacy interface, absorb=0 starts an independent
                // Keccak block by overwriting rate words; absorb=1 chains a
                // continuation by XORing into the prior permutation state.
                // Clear capacity at the first overwrite word as well.
                if (pre_padded && wr_idx == 0 && !wr_xor)
                    block_reg <= 1600'h0;
                if (wr_last) begin
                    // Kyber supplies complete, pre-padded rate blocks.  Its
                    // legacy mode signal is updated by a neighbouring FSM
                    // state and can therefore be one transaction out of
                    // phase.  The accepted block length is unambiguous:
                    // 18 words = SHA3-512, 34 = SHAKE256/SHA3-256, and
                    // 42 = SHAKE128.  Use it to select the squeeze rate so
                    // Client and Server cannot interpret an identical block
                    // with different rates.
                    if (pre_padded) begin
                        case (wr_idx)
                            6'd17: mode_latched <= 2'd0;
                            6'd41: mode_latched <= 2'd2;
                            default: mode_latched <= 2'd1;
                        endcase
                    end
                    if (pre_padded && !wr_xor)
                        block_reg[32*wr_idx +: 32] <= din;
                    else
                        block_reg[32*wr_idx +: 32] <= block_reg[32*wr_idx +: 32] ^ din;
                    if (pre_padded) begin
                        // No second padding pass: the final word already
                        // contains the trailing 0x80 supplied by Kyber.
                        pad_extra <= 1'b0;
                    end else begin
                        // FIPS pad10*1: domain byte goes AFTER the message
                        // and 0x80 marks the final byte of the rate block.
                        if (wr_idx == rate_words-1) begin
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
                    end
                    have_block <= 1'b1;
                    auto_squeeze_perm <= 1'b0;
                    wr_idx     <= 6'd0;
                end else begin
                    if (pre_padded && !wr_xor)
                        block_reg[32*wr_idx +: 32] <= din;
                    else
                        block_reg[32*wr_idx +: 32] <= block_reg[32*wr_idx +: 32] ^ din;
                    wr_idx <= wr_idx + 6'd1;
                end
            end

            // ---------------- squeeze side ----------------
            if (rd_en && ready_flag && !permuting) begin
                squeeze_reg <= {squeeze_reg[31:0], squeeze_reg[1599:32]};
                if (rd_idx == rate_words - 1) begin
                    // The legacy Kyber datapath often absorbs the next
                    // message while it drains the tail of a fixed digest.
                    // Crossing the rate in that overlap must stop the old
                    // stream, not overwrite the partially accumulated next
                    // message with an automatic squeeze permutation.  Only
                    // the top-level explicit EXTEND windows request another
                    // XOF block.
                    rd_idx     <= 6'd0;
                    ready_flag <= 1'b0;
                    if (rd_extend) begin
                        block_reg  <= base_state;
                        have_block <= 1'b1;
                        auto_squeeze_perm <= 1'b1;
                    end else begin
                        auto_squeeze_perm <= 1'b0;
                    end
                end else begin
                    rd_idx <= rd_idx + 6'd1;
                end
            end
        end
    end

endmodule
