`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// hash_core_Server.v — REBUILT around sha3_shake_core (FIPS-202)
//
// Changes vs legacy (backup: hash_core_Server.v.bak_legacy):
//   * keccak_f1600_server + manual padding FSM (pad_flag/pad_ctr/pad_last/
//     keccak_go) REMOVED. Padding is now handled correctly inside
//     sha3_shake_core from the IFIFO 'last' flag.
//   * Every word pushed by the Kyber FSM is absorbed as message data
//     (the per-word 'absorb' flag is ignored — legacy used it only to
//     select XOR-vs-shift, equivalent for a zero-initialised state).
//   * Mode mapping chosen so consumer windows never cross a rate boundary:
//       mode 0 -> SHAKE128 (42 words, covers squeeze_ctr < 6'h2A window)
//       others -> SHAKE256 (34 words, covers squeeze_ctr < 6'h22 and G's 16)
//   * keccak_squeeze is now a VALID strobe (one per accepted word);
//     squeeze_ctr counts accepted words; dout advances on rd_en.
//   * 'extend' port kept for pin compatibility but unused (rotation happens
//     inside sha3_shake_core).
//-----------------------------------------------------------------------------

module hash_core_Server(
    input wire clk,
    input wire rst,
    input wire keccak_init,
    input wire keccak_init_hard,
    input wire squeeze_init,
    input wire extend,
    input wire patt_bit,
    input wire eta3_bit,
    input wire [1:0] absorb_ctr_r1,
    input wire [2:0] keccak_ctr,
    input wire ififo_wen,
    input wire [31:0] ififo_din,
    input wire ififo_absorb,
    input wire [1:0] ififo_mode,
    input wire ififo_last,
    output wire ififo_empty,
    output wire keccak_ready,
    output wire keccak_squeeze,
    output wire [31:0] keccak_dout,
    input wire ofifo_ena,
    input wire ofifo0_req,
    input wire ofifo1_req,
    output wire [23:0] ofifo0_dout,
    output wire [24:0] ofifo1_dout,
    output wire ofifo0_full,
    output wire ofifo1_full,
    output wire ofifo0_empty,
    output wire ofifo1_empty,
    output reg [5:0] squeeze_ctr,
    output reg [7:0] fifo_GENA_ctr,
    output wire matrix_stream_active,
    input wire [8:0] ofifo0_prog_thresh,
    input wire [8:0] ofifo1_prog_thresh,
    output wire ofifo0_prog_full,
    output wire ofifo1_prog_full
);

    // ------------------------------------------------------------------
    // IFIFO pop arbitration
    // ------------------------------------------------------------------
    wire        core_busy;
    wire        core_word_accept;   // core consumes the popped word this edge

    wire ififo_req;
    reg  ififo_req_r1;
    wire [31:0] ififo_dout;
    wire ififo_full;

    wire absorb_w;      // word flag (unused, kept for clarity)
    wire [1:0] mode_w;  // word flag (informational)
    wire last_w;

    // In an explicit extension window, IFIFO writes are legacy dummy clocks,
    // not message words.  Leave them out of the rebuilt sponge entirely.
    assign ififo_req = ~(ififo_empty | core_busy | extend);

    always @(posedge clk) begin
        if (rst)
            ififo_req_r1 <= 1'b0;
        else
            ififo_req_r1 <= ififo_req;
    end

    // ------------------------------------------------------------------
    // sha3_shake_core instantiation & glue
    // ------------------------------------------------------------------
    wire        sponge_init;
    reg         init_d;
    wire [31:0] sponge_dout;
    wire        sponge_valid;
    wire        sponge_done;
    wire        sponge_done_extend;
    wire [5:0]  sponge_output_rate;
    wire        sponge_rd_en;

    // Edge-detect keccak_init (Kyber FSM drives it combinationally per state)
    always @(posedge clk) begin
        if (rst)
            init_d <= 1'b0;
        else
            init_d <= keccak_init;
    end
    assign sponge_init = keccak_init & ~init_d;

    // Word stream into the sponge: FIFO pops at E1 (req), new head visible at
    // E2 where we both present it and let the core accept it.
    wire [31:0] core_din   = ififo_dout;
    wire        core_last  = last_w;   // combinational: pairs with ififo_dout

    wire [1:0] core_mode = ififo_mode;   // latched by core at init (post-fix timing)

    sha3_shake_core sponge (
        .clk        (clk),
        .rst        (rst),
        .init       (sponge_init),
        .hard_init  (keccak_init_hard),
        .mode       (core_mode),
        .pre_padded (1'b1),
        .wr_en      (core_word_accept),
        .din        (core_din),
        .wr_xor     (absorb_w),
        .wr_last    (core_last),
        .busy       (core_busy),
        .rd_en      (sponge_rd_en),
        .rd_extend  (extend),
        .dout       (sponge_dout),
        .dout_valid (sponge_valid),
        .done       (sponge_done),
        .done_extend(sponge_done_extend),
        .dout_rate_words(sponge_output_rate)
    );

    // sponge_done is visible to the parent for one full cycle.  Hold word 0
    // for one additional cycle so the parent can advance patt/eta3, then
    // snapshot the updated output classification before any word is consumed.
    reg tag_capture_pending;
    reg output_patt, output_eta3;
    reg [3:0] matrix_stream_id;
    wire output_is_matrix = (sponge_output_rate == 6'd42);
    wire stream_patt = output_is_matrix ? 1'b0 : output_patt;
    wire stream_eta3 = output_is_matrix ? 1'b0 : output_eta3;
    always @(posedge clk) begin
        if (rst || (sponge_init && keccak_init_hard)) begin
            tag_capture_pending <= 1'b0;
            output_patt  <= 1'b0;
            output_eta3  <= 1'b0;
            matrix_stream_id <= 4'h0;
        end else if (sponge_done) begin
            tag_capture_pending <= 1'b1;
            if (!sponge_done_extend && output_is_matrix)
                matrix_stream_id <= matrix_stream_id + 1'b1;
        end else if (tag_capture_pending) begin
            tag_capture_pending <= 1'b0;
            output_patt <= patt_bit;
            output_eta3 <= eta3_bit;
        end else begin
            tag_capture_pending <= tag_capture_pending;
        end
    end

    // Accept a popped word whenever the FIFO offers one while not mid-block.
    // (Absorb never overlaps permutation in the Kyber flow.)
    reg word_pend;
    always @(posedge clk) begin
        if (rst) begin
            word_pend <= 1'b0;
        end else if (sponge_init && keccak_init_hard) begin
            word_pend <= 1'b0;
        end else begin
            case ({ififo_req, core_word_accept})
                2'b10, 2'b11: word_pend <= 1'b1; // next FIFO word is pending
                2'b01:        word_pend <= 1'b0;
                default:      word_pend <= word_pend;
            endcase
        end
    end
    assign core_word_accept = word_pend && !core_busy && !extend;

    // ------------------------------------------------------------------
    // Squeeze streaming
    // ------------------------------------------------------------------
    // Consumers (rho/sigma fill, hash_pk/hash_c/K capture, ofifo routing)
    // sample every cycle inside their windows. We therefore accept EVERY
    // valid word immediately and count it, keeping squeeze_ctr aligned with
    // what consumers see on keccak_dout this cycle.
    //
    // FIX: Suppress rd_en during absorb phase after sponge_init.
    // After sha3 core reset, stale squeeze data appears on dout_valid
    // (dout_valid = ready_flag && !permuting is HIGH during absorb).
    // Block consumption until first keccak_f completes (sponge_done),
    // then fresh squeeze words flow normally.
    // Keep the first output word stationary during sponge_done.  The parent
    // advances patt/eta3 and its capture state on that edge, so consuming the
    // word in the same cycle would classify it as the preceding transaction.
    reg sponge_hold_set;
    always @(posedge clk) begin
        if (rst)
            sponge_hold_set <= 1'b0;
        else if (sponge_init && keccak_init_hard)
            sponge_hold_set <= 1'b1;
        else if (sponge_done)
            sponge_hold_set <= 1'b0;
    end
wire sponge_hold = sponge_hold_set & ~sponge_done;

    // Match the legacy Keccak register protocol: output advances while a new
    // input block is being shifted in, or while a fixed digest window asserts
    // extend.  Otherwise the first output word remains pending for the FSM.
    // eta1=3 needs 192 PRF bytes.  The first SHAKE256 rate contributes all
    // 136 bytes (34 words), including the final two words that the legacy FSM
    // does not overlap with absorption of the next request.  Drain those two
    // words locally before allowing the sponge to permute for the 56-byte tail.
    wire eta3_first_rate_drain = stream_patt & stream_eta3 &
                                 (squeeze_ctr < 6'd34);
    // The sponge owns the exact SHAKE128 rate boundary.  Do not use the
    // legacy squeeze counter here: that counter may be reset while the final
    // words of an overlapped transaction are still pending.
    wire matrix_rate_drain = output_is_matrix;
    // A queued absorb block cannot start while the previous squeeze rate is
    // still marked ready.  Drain that tail whenever core_busy is caused by
    // have_block, otherwise a multi-block H(pk)/H(c) transaction can stall
    // forever with both have_block and ready_flag asserted.
    wire squeeze_accept = sponge_valid & ~sponge_done & ~sponge_hold &
                          ~tag_capture_pending & ~squeeze_init &
                          (core_word_accept | core_busy | extend |
                           eta3_first_rate_drain |
                           matrix_rate_drain);
    assign sponge_rd_en   = squeeze_accept;
    assign keccak_squeeze = squeeze_accept;
    assign keccak_dout    = sponge_dout;
    assign keccak_ready   = sponge_done;     // 1-clk pulse per completed block

    reg extend_r1;
    always @(posedge clk) begin
        if (rst)
            squeeze_ctr <= 6'h0;
        // Each sponge_done publishes word 0 of a newly captured rate block.
        // No read is accepted on that pulse, so resetting here preserves the
        // word and prevents a preceding transaction's index from truncating
        // the new SHAKE block (notably 34-word eta=3 PRF blocks).
        // A new absorb request may overlap the two unused tail words of a
        // preceding eta2 SHAKE256 rate.  Keep their old index until the next
        // sponge_done publishes a genuinely new output block, otherwise the
        // tail is re-labelled as word 0/1 of the following noise polynomial.
        else if (squeeze_init || sponge_done ||
                 (~extend & extend_r1))
            squeeze_ctr <= 6'h0;
        else if (squeeze_accept)
            squeeze_ctr <= squeeze_ctr + 6'h1;
    end
    always @(posedge clk) begin
        if (rst)
            extend_r1 <= 1'b0;
        else
            extend_r1 <= extend;
    end

    // ------------------------------------------------------------------
    // ofifo0/ofifo1 routing (unchanged semantics, new strobe source)
    // ------------------------------------------------------------------
    reg ofifo_wen;
    wire [39:0] ofifo_din;
    wire [39:0] ofifo_dout;
    wire ofifo_full, ofifo_empty;

    wire decode_req;
    wire [23:0] decode_dout;
    wire decode_valid;
    wire decode_patt;
    wire decode_eta3;
    wire [3:0] decode_stream;

    wire ofifo_din_valid0, ofifo_din_valid1;
    reg fifo_data_parity;
    reg [11:0] fifo_data_dropped;
    wire ofifo0_wen, ofifo1_wen;
    reg [23:0] ofifo0_din;
    wire [24:0] ofifo1_din;
    reg ofifo1_full_r1;
    reg [3:0] matrix_stream_seen;

    wire matrix_stream_change = decode_valid & ~decode_patt & ~decode_eta3 &
                                (decode_stream != matrix_stream_seen);
    wire matrix_parity = matrix_stream_change ? 1'b0 : fifo_data_parity;

    assign matrix_stream_active = (matrix_stream_seen == matrix_stream_id);

    assign ofifo_din = {2'b0, matrix_stream_id, stream_patt,
                        stream_eta3, keccak_dout};

    always @(*) case (keccak_ctr)
        3'h1, 3'h2, 3'h3, 3'h4: ofifo_wen = ~ofifo_full & ofifo_ena & keccak_squeeze & ((stream_patt & ~stream_eta3) && ~squeeze_ctr[5] || stream_eta3 && squeeze_ctr < (stream_patt ? 6'd34 : 6'd14) || (~stream_patt&~stream_eta3));
        3'h7: ofifo_wen = ~ofifo_full & ofifo_ena & keccak_squeeze & ((stream_patt & ~stream_eta3) && ~squeeze_ctr[5] || stream_eta3 && squeeze_ctr < (stream_patt ? 6'd34 : 6'd14) || (~stream_patt&~stream_eta3));
        default: ofifo_wen = 1'b0;
    endcase

    assign ofifo_din_valid0 = decode_dout[11:0] < 12'hd01;
    assign ofifo_din_valid1 = decode_dout[23:12] < 12'hd01;

    always @(*) case ({ofifo_din_valid0, ofifo_din_valid1, matrix_parity})
        3'b101, 3'b111: begin
            ofifo0_din[11:0] = fifo_data_dropped;
            ofifo0_din[23:12] = decode_dout[11:0];
        end
        3'b011: begin
            ofifo0_din[11:0] = fifo_data_dropped;
            ofifo0_din[23:12] = decode_dout[23:12];
        end
        default: begin
            ofifo0_din[11:0] = decode_dout[11:0];
            ofifo0_din[23:12] = decode_dout[23:12];
        end
    endcase

    always @(posedge clk) begin
        if(decode_valid & ~decode_patt & ~decode_eta3)
            case({ofifo_din_valid0,ofifo_din_valid1,matrix_parity})
            3'b 100 : fifo_data_dropped <= decode_dout[11:0];
            3'b 010, 3'b 111 : fifo_data_dropped <= decode_dout[23:12];
            default : fifo_data_dropped <= fifo_data_dropped;
            endcase
        else
            fifo_data_dropped <= fifo_data_dropped;
    end

    assign ofifo1_din = {decode_eta3, decode_dout};
    assign ofifo0_wen = ~decode_patt&~decode_eta3 & decode_valid &
        (~fifo_GENA_ctr[7] | matrix_stream_change) &
        (ofifo_din_valid0 & ofifo_din_valid1 |
         (ofifo_din_valid0 ^ ofifo_din_valid1) & matrix_parity);
    assign ofifo1_wen = (decode_patt|decode_eta3) & decode_valid & ~ofifo1_full_r1;

    // Synchronous reset keeps this FIFO status register compatible with the
    // inferred block-RAM control path.
    always @(posedge clk) begin
        if (rst || keccak_init_hard)
            ofifo1_full_r1 <= 1'b0;
        else if (keccak_ready)
            ofifo1_full_r1 <= 1'b0;
        else if (ofifo1_full & decode_eta3)
            ofifo1_full_r1 <= 1'b1;
        else
            ofifo1_full_r1 <= ofifo1_full_r1;
    end

    always @(posedge clk) begin
        if (rst || keccak_init_hard)
            fifo_data_parity <= 1'b0;
        // A SHAKE128 matrix polynomial can require several rate blocks.
        // keccak_ready therefore is not a polynomial boundary: resetting on
        // it re-opens the 128-word gate and leaks rejection-sampling surplus
        // from the previous polynomial into the next NTT input.  The KeyGen
        // schedule places a decoded PRF/noise stream between matrix streams;
        // use that actual data-class boundary to discard any unmatched sample.
        else if (decode_valid && (decode_patt || decode_eta3))
            fifo_data_parity <= 1'b0;
        else if (matrix_stream_change)
            fifo_data_parity <= ofifo_din_valid0 ^ ofifo_din_valid1;
        else if (ofifo_din_valid0 ^ ofifo_din_valid1 && decode_valid && (~decode_patt&~decode_eta3))
            fifo_data_parity <= ~fifo_data_parity;
        else
            fifo_data_parity <= fifo_data_parity;
    end

    always @(posedge clk) begin
        if (rst || keccak_init_hard)
            fifo_GENA_ctr <= 8'h0;
        else if (decode_valid && (decode_patt || decode_eta3))
            fifo_GENA_ctr <= 8'h0;
        else if (matrix_stream_change)
            fifo_GENA_ctr <= (ofifo_din_valid0 & ofifo_din_valid1) ?
                             8'h1 : 8'h0;
        // Count every packed matrix word that can actually be enqueued.
        // Decoder output may trail the parent FSM's ofifo_ena window; gating
        // only the counter (but not ofifo0_wen) allowed uncounted surplus.
        else if (decode_valid && (~decode_patt&~decode_eta3) && ~fifo_GENA_ctr[7])
            case ({ofifo_din_valid0, ofifo_din_valid1, fifo_data_parity})
                3'b110, 3'b111: fifo_GENA_ctr <= fifo_GENA_ctr + 1'h1;
                3'b101, 3'b011: fifo_GENA_ctr <= fifo_GENA_ctr + 1'h1;
                default: fifo_GENA_ctr <= fifo_GENA_ctr;
            endcase
        else
            fifo_GENA_ctr <= fifo_GENA_ctr;
    end

    always @(posedge clk) begin
        if (rst || keccak_init_hard)
            matrix_stream_seen <= 4'h0;
        else if (decode_valid && ~decode_patt && ~decode_eta3)
            matrix_stream_seen <= decode_stream;
    end

    // ------------------------------------------------------------------
    // FIFOs
    // ------------------------------------------------------------------
    wire [35:0] ififo_din_int = {ififo_mode, ififo_absorb, ififo_last, ififo_din};
    wire [35:0] ififo_dout_int;

    fifo_wrapper_36_32 ififo_inst (
        .clk(clk),
        .rst_n(~(rst | (sponge_init & keccak_init_hard))),
        .wr_en(ififo_wen & ~extend),
        .wr_data(ififo_din_int),
        .rd_en(ififo_req),
        .dout(ififo_dout_int),
        .full(ififo_full),
        .empty(ififo_empty)
    );

    assign {mode_w, absorb_w, last_w, ififo_dout} = ififo_dout_int;

    // Output FIFOs
    // The rebuilt streaming SHA adapter can have several XOF blocks in
    // flight; keep enough staging to avoid dropping a complete matrix block.
    // k=3 produces 9 matrix polynomials (9 * 128 packed words = 1152)
    // before all consumers have drained them.  Keep a power-of-two depth
    // above that peak so the final polynomial is not silently dropped.
    fifo_wrapper_24_16 #(.DEPTH(2048)) ofifo0_inst (
        .clk(clk),
        // A hard hash boundary on the Server also marks the end of the
        // previous Kyber phase.  Discard rejection-sampling surplus so CCA
        // NTT cannot consume key-generation coefficients first.
        .rst_n(~(rst | keccak_init_hard)),
        .wr_en(ofifo0_wen),
        .wr_data(ofifo0_din),
        .rd_en(ofifo0_req),
        .prog_full_thresh(ofifo0_prog_thresh),
        .dout(ofifo0_dout),
        .full(ofifo0_full),
        .empty(ofifo0_empty),
        .prog_full(ofifo0_prog_full)
    );

    fifo_wrapper_25_16 #(.DEPTH(256)) ofifo1_inst (
        .clk(clk),
        .rst_n(~(rst | keccak_init_hard)),
        .wr_en(ofifo1_wen),
        .wr_data(ofifo1_din),
        .rd_en(ofifo1_req),
        .prog_full_thresh(ofifo1_prog_thresh),
        .dout(ofifo1_dout),
        .full(ofifo1_full),
        .empty(ofifo1_empty),
        .prog_full(ofifo1_prog_full)
    );

    fifo_wrapper_40_32 #(.DEPTH(1024)) ofifo_inst (
        .clk(clk),
        .rst_n(~(rst | keccak_init_hard)),
        .wr_en(ofifo_wen),
        .wr_data(ofifo_din),
        .rd_en(decode_req),
        .dout(ofifo_dout),
        .full(ofifo_full),
        .empty(ofifo_empty)
    );

    decode_keccak decode(
        .clk(clk),
        .rst(rst | keccak_init_hard),
        .din(ofifo_dout[31:0]),
        .fifo_empty(ofifo_empty),
        .patt_bit(ofifo_dout[33]),
        .eta3_bit(ofifo_dout[32]),
        .stream_id(ofifo_dout[37:34]),
        .dout(decode_dout),
        .req(decode_req),
        .valid(decode_valid),
        .patt_out(decode_patt),
        .eta3_out(decode_eta3),
        .stream_out(decode_stream)
    );

endmodule
