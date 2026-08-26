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

module hash_core_Client(
    input wire clk,
    input wire rst,
    input wire keccak_init,
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

    // Pause popping while the sponge is busy or already holds an unaccepted
    // pending word.
    assign ififo_req = ~(ififo_empty | core_busy | core_word_accept);

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
        .mode       (core_mode),
        .wr_en      (core_word_accept),
        .din        (core_din),
        .wr_last    (core_last),
        .busy       (core_busy),
        .rd_en      (sponge_rd_en),
        .dout       (sponge_dout),
        .dout_valid (sponge_valid),
        .done       (sponge_done)
    );

    // Accept a popped word whenever the FIFO offers one while not mid-block.
    // (Absorb never overlaps permutation in the Kyber flow.)
    reg word_pend;
    always @(posedge clk) begin
        if (rst) begin
            word_pend <= 1'b0;
        end else if (sponge_init) begin
            word_pend <= 1'b0;
        end else if (ififo_req) begin
            word_pend <= 1'b1;          // word arrives next cycle on ififo_dout
        end else if (core_word_accept) begin
            word_pend <= 1'b0;
        end
    end
    assign core_word_accept = word_pend && !core_busy;

    // ------------------------------------------------------------------
    // Squeeze streaming
    // ------------------------------------------------------------------
    // Consumers (rho/sigma fill, hash_pk/hash_c/K capture, ofifo routing)
    // sample every cycle inside their windows. We therefore accept EVERY
    // valid word immediately and count it, keeping squeeze_ctr aligned with
    // what consumers see on keccak_dout this cycle.
    assign sponge_rd_en   = sponge_valid;
    assign keccak_squeeze = sponge_valid;
    assign keccak_dout    = sponge_dout;
    assign keccak_ready   = sponge_done;     // 1-clk pulse per completed block

    always @(posedge clk) begin
        if (rst)
            squeeze_ctr <= 6'h0;
        else if (keccak_init || (~extend & extend_r1))
            squeeze_ctr <= 6'h0;
        else if (sponge_valid)
            squeeze_ctr <= squeeze_ctr + 6'h1;
    end
    reg extend_r1;
    always @(posedge clk) extend_r1 <= extend;

    // ------------------------------------------------------------------
    // ofifo0/ofifo1 routing (unchanged semantics, new strobe source)
    // ------------------------------------------------------------------
    reg ofifo_ena_r1, ofifo_ena_r2;
    reg ofifo_wen;
    wire [31:0] ofifo_din;
    wire [31:0] ofifo_dout;
    wire ofifo_full, ofifo_empty;

    wire decode_req;
    wire [23:0] decode_dout;
    wire decode_valid;

    wire ofifo_din_valid0, ofifo_din_valid1;
    reg fifo_data_parity;
    reg [11:0] fifo_data_dropped;
    wire ofifo0_wen, ofifo1_wen;
    reg [23:0] ofifo0_din;
    wire [24:0] ofifo1_din;
    reg ofifo1_full_r1;

    always @(posedge clk) begin
        if (rst) begin
            ofifo_ena_r1 <= 1'b0;
            ofifo_ena_r2 <= 1'b0;
        end else begin
            ofifo_ena_r1 <= ofifo_ena;
            ofifo_ena_r2 <= ofifo_ena_r1;
        end
    end

    assign ofifo_din = keccak_dout;

    always @(*) case (keccak_ctr)
        3'h1, 3'h2, 3'h3, 3'h4: ofifo_wen = ~ofifo_full & ofifo_ena_r2 & keccak_squeeze & ((patt_bit & ~eta3_bit) && ~squeeze_ctr[5] || eta3_bit && squeeze_ctr < 6'h22 || (~patt_bit&~eta3_bit) && squeeze_ctr < 6'h2A);
        3'h7: ofifo_wen = ~ofifo_full & ofifo_ena_r2 & keccak_squeeze & ((patt_bit & ~eta3_bit) && ~squeeze_ctr[5] || eta3_bit && squeeze_ctr < 6'h22 || (~patt_bit&~eta3_bit) && squeeze_ctr < 6'h2A);
        default: ofifo_wen = 1'b0;
    endcase

    assign ofifo_din_valid0 = decode_dout[11:0] < 12'hd01;
    assign ofifo_din_valid1 = decode_dout[23:12] < 12'hd01;

    always @(*) case ({ofifo_din_valid0, ofifo_din_valid1, fifo_data_parity})
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
        if(decode_valid & ~patt_bit & ~eta3_bit)
            case({ofifo_din_valid0,ofifo_din_valid1,fifo_data_parity})
            3'b 100 : fifo_data_dropped <= decode_dout[11:0];
            3'b 010, 3'b 111 : fifo_data_dropped <= decode_dout[23:12];
            default : fifo_data_dropped <= fifo_data_dropped;
            endcase
        else
            fifo_data_dropped <= fifo_data_dropped;
    end

    assign ofifo1_din = {eta3_bit, decode_dout};
    assign ofifo0_wen = ~patt_bit&~eta3_bit & decode_valid & ~fifo_GENA_ctr[7] & (ofifo_din_valid0 & ofifo_din_valid1 | (ofifo_din_valid0 ^ ofifo_din_valid1) & fifo_data_parity);
    assign ofifo1_wen = (patt_bit|eta3_bit) & decode_valid & ~ofifo1_full_r1;

    always @(posedge clk or posedge rst) begin
        if (rst)
            ofifo1_full_r1 <= 1'b0;
        else if (keccak_ready)
            ofifo1_full_r1 <= 1'b0;
        else if (ofifo1_full & eta3_bit)
            ofifo1_full_r1 <= 1'b1;
        else
            ofifo1_full_r1 <= ofifo1_full_r1;
    end

    always @(posedge clk) begin
        if (rst)
            fifo_data_parity <= 1'b0;
        else if (fifo_GENA_ctr[7] && keccak_ready)
            fifo_data_parity <= 1'b0;
        else if (ofifo_din_valid0 ^ ofifo_din_valid1 && decode_valid && (~patt_bit&~eta3_bit))
            fifo_data_parity <= ~fifo_data_parity;
        else
            fifo_data_parity <= fifo_data_parity;
    end

    always @(posedge clk) begin
        if (rst)
            fifo_GENA_ctr <= 8'h0;
        else if (fifo_GENA_ctr[7] && keccak_ready)
            fifo_GENA_ctr <= 8'h0;
        else if (decode_valid && (~patt_bit&~eta3_bit) && ofifo_ena && ~fifo_GENA_ctr[7])
            case ({ofifo_din_valid0, ofifo_din_valid1, fifo_data_parity})
                3'b110, 3'b111: fifo_GENA_ctr <= fifo_GENA_ctr + 1'h1;
                3'b101, 3'b011: fifo_GENA_ctr <= fifo_GENA_ctr + 1'h1;
                default: fifo_GENA_ctr <= fifo_GENA_ctr;
            endcase
        else
            fifo_GENA_ctr <= fifo_GENA_ctr;
    end

    // ------------------------------------------------------------------
    // FIFOs
    // ------------------------------------------------------------------
    wire [35:0] ififo_din_int = {ififo_mode, ififo_absorb, ififo_last, ififo_din};
    wire [35:0] ififo_dout_int;

    fifo_wrapper_36_32 ififo_inst (
        .clk(clk),
        .rst_n(~rst),
        .wr_en(ififo_wen),
        .wr_data(ififo_din_int),
        .rd_en(ififo_req),
        .dout(ififo_dout_int),
        .full(ififo_full),
        .empty(ififo_empty)
    );

    assign {mode_w, absorb_w, last_w, ififo_dout} = ififo_dout_int;

    // Output FIFOs
    fifo_wrapper_24_16 ofifo0_inst (
        .clk(clk),
        .rst_n(~rst),
        .wr_en(ofifo0_wen),
        .wr_data(ofifo0_din),
        .rd_en(ofifo0_req),
        .prog_full_thresh(ofifo0_prog_thresh),
        .dout(ofifo0_dout),
        .full(ofifo0_full),
        .empty(ofifo0_empty),
        .prog_full(ofifo0_prog_full)
    );

    fifo_wrapper_25_16 ofifo1_inst (
        .clk(clk),
        .rst_n(~rst),
        .wr_en(ofifo1_wen),
        .wr_data(ofifo1_din),
        .rd_en(ofifo1_req),
        .prog_full_thresh(ofifo1_prog_thresh),
        .dout(ofifo1_dout),
        .full(ofifo1_full),
        .empty(ofifo1_empty),
        .prog_full(ofifo1_prog_full)
    );

    fifo_wrapper_32_16 ofifo_inst (
        .clk(clk),
        .rst_n(~rst),
        .wr_en(ofifo_wen),
        .wr_data(ofifo_din),
        .rd_en(decode_req),
        .dout(ofifo_dout),
        .full(ofifo_full),
        .empty(ofifo_empty)
    );

    decode_keccak decode(
        .clk(clk),
        .rst(rst),
        .din(ofifo_dout),
        .fifo_empty(ofifo_empty),
        .patt_bit(patt_bit),
        .eta3_bit(eta3_bit),
        .dout(decode_dout),
        .req(decode_req),
        .valid(decode_valid)
    );

endmodule
