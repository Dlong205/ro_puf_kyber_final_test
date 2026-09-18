`timescale 1ns / 1ps
`default_nettype none

// Same-root verifier for the CPU-free Edge role (Phase 1 of
// docs/PUF_ROOT_BINDING_DESIGN.md).
//
// Computes KCV = SHAKE256(label || domain || root_key || kcv_ctx) with a
// fixed 48-byte message and compares it, in constant time, against a
// 28-byte public reference provisioned with the enrollment.  The reference
// is a public verifier, NOT a MAC: it detects wrong-helper/wrong-root
// errors but does not authenticate the record against an attacker who can
// also replace the reference.
//
// Message layout (48 bytes, SHAKE256, little-endian words):
//   word 0..2  "RO-PUF-KCV-v1" bytes 0..11 ("RO-P","UF-K","CV-v")
//   word 3     bytes 12..15 = '1' + 3 zero pad
//   word 4     bytes 16..19 = domain_sep 0x01, rec_ver, protocol, profile
//   word 5     bytes 20..23 = generation, fe_id, mapping_tag_lo, mapping_tag_hi
//   word 6..11 root_key 24 bytes (key byte 0 first)
// The final absorbed word carries wr_last; the sponge adds FIPS padding.
//
// Latency is fixed for pass and fail: absorb 12 words, one permutation,
// squeeze 7 words.  A mismatch never truncates the squeeze stream.
module edge_root_binding (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         zeroize,
    input  wire         start,
    input  wire [191:0] root_key,
    input  wire [55:0]  kcv_ctx,      // {generation[7:0], mapping_tag[15:0],
                                      //  fe_id[7:0], profile_id[7:0],
                                      //  protocol_version[7:0],
                                      //  record_version[7:0]}
    input  wire [223:0] kcv_ref,
    output wire         busy,
    output reg          done,
    output reg          kcv_pass,
    // Computed digest, independent of the comparison.  Enrollment uses this
    // to emit the KCV into the helper record; reconstruct ignores it.
    output reg  [223:0] kcv_out
);
    localparam [2:0] ST_IDLE    = 3'd0;
    localparam [2:0] ST_ABSORB  = 3'd1;
    localparam [2:0] ST_PERM    = 3'd2;
    localparam [2:0] ST_SQUEEZE = 3'd3;
    localparam [2:0] ST_DONE    = 3'd4;

    localparam [5:0] ABSORB_WORDS = 6'd12; // 48 bytes
    localparam [5:0] KCV_WORDS    = 6'd7;  // 28 bytes

    reg [2:0] state;
    reg [5:0] word_index;
    reg [223:0] kcv_acc;
    reg [191:0] key_latch;
    reg [55:0]  ctx_latch;
    reg [223:0] ref_latch;

    wire sponge_rst = ~rst_n | zeroize;

    // Message words are assembled combinationally from the latched inputs.
    // word 3 = '1' (label tail) + 3 zero bytes; word 4 = domain + rec/proto/
    // profile; word 5 = gen/fe/tag_lo/tag_hi; words 6..11 = key bytes.
    function automatic [31:0] msg_word_fn;
        input [5:0] idx;
        begin
            if (idx == 6'd0)      msg_word_fn = 32'h502D4F52;         // "RO-P"
            else if (idx == 6'd1) msg_word_fn = 32'h4B2D4655;         // "UF-K"
            else if (idx == 6'd2) msg_word_fn = 32'h762D5643;         // "CV-v"
            else if (idx == 6'd3) msg_word_fn = 32'h00000031;         // "1"+3x00
            else if (idx == 6'd4) msg_word_fn = {ctx_latch[23:16],
                                                 ctx_latch[15:8],
                                                 ctx_latch[7:0],
                                                 8'h01};
            else if (idx == 6'd5) msg_word_fn = {ctx_latch[47:40],
                                                 ctx_latch[39:32],
                                                 ctx_latch[31:24],
                                                 ctx_latch[55:48]};
            else if (idx <= 6'd11) msg_word_fn = key_latch[(idx-6'd6)*32 +: 32];
            else                  msg_word_fn = 32'h00000000;
        end
    endfunction

    wire [31:0] msg_word = msg_word_fn(word_index);

    wire msg_last = (word_index == ABSORB_WORDS - 6'd1);

    sha3_shake_core u_sponge (
        .clk        (clk),
        .rst        (sponge_rst),
        .scrub      (zeroize),
        .init       (state == ST_IDLE && start),
        .hard_init  (1'b0),
        .mode       (2'd1),          // SHAKE256
        .pre_padded (1'b0),          // let the sponge generate FIPS padding
        .wr_en      (state == ST_ABSORB),
        .din        (msg_word),
        .wr_xor     (1'b0),
        .wr_last    (msg_last),
        .busy       (),
        .rd_en      (state == ST_SQUEEZE && sponge_valid),
        .rd_extend  (1'b0),
        .dout       (sponge_word),
        .dout_valid (sponge_valid),
        .done       (),
        .done_extend(),
        .dout_rate_words()
    );

    wire [31:0] sponge_word;
    wire sponge_valid;

    always @(posedge clk) begin
        if (!rst_n) begin
            state      <= ST_IDLE;
            done       <= 1'b0;
            kcv_pass   <= 1'b0;
            kcv_out    <= 224'd0;
            kcv_acc    <= 224'd0;
            word_index <= 6'd0;
            key_latch  <= 192'd0;
            ctx_latch  <= 56'd0;
            ref_latch  <= 224'd0;
        end else if (zeroize) begin
            state      <= ST_IDLE;
            done       <= 1'b0;
            kcv_pass   <= 1'b0;
            kcv_out    <= 224'd0;
            kcv_acc    <= 224'd0;
            word_index <= 6'd0;
            key_latch  <= 192'd0;
            ctx_latch  <= 56'd0;
            ref_latch  <= 224'd0;
        end else begin
            done <= 1'b0;

            case (state)
                ST_IDLE: begin
                    kcv_pass <= 1'b0;
                    if (start) begin
                        kcv_out    <= 224'd0;
                        key_latch  <= root_key;
                        ctx_latch  <= kcv_ctx;
                        ref_latch  <= kcv_ref;
                        kcv_acc    <= 224'd0;
                        word_index <= 6'd0;
                        state      <= ST_ABSORB;
                    end
                end

                ST_ABSORB: begin
                    word_index <= word_index + 6'd1;
                    if (msg_last)
                        state <= ST_PERM;
                end

                ST_PERM: begin
                    if (sponge_valid) begin
                        word_index <= 6'd0;
                        state      <= ST_SQUEEZE;
                    end
                end

                ST_SQUEEZE: begin
                    if (sponge_valid) begin
                        kcv_acc[word_index*32 +: 32] <= sponge_word;
                        word_index <= word_index + 6'd1;
                        if (word_index == KCV_WORDS - 6'd1) begin
                            // Full 224-bit XOR against the latched
                            // reference; see kcv_diff below.
                            kcv_pass <= ~|kcv_diff;
                            kcv_out  <= kcv_final;
                            state <= ST_DONE;
                        end
                    end
                end

                ST_DONE: begin
                    done <= 1'b1;
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

    // Full 224-bit constant-time compare.  On the final squeeze word,
    // kcv_acc holds words 0..5 and sponge_word is word 6.  Assemble the
    // computed digest in reference layout (word 0 at [31:0], word 6 at
    // [223:192]) and XOR it against the latched reference in a single
    // reduction.  Every one of the 224 bits participates: an earlier revision
    // folded only six words and let reference corruption in kcv_acc[191:160]
    // pass the gate (security review finding).
    wire [223:0] kcv_final = {sponge_word, kcv_acc[191:0]};
    wire [223:0] kcv_diff = kcv_final ^ ref_latch;

    assign busy = (state != ST_IDLE) && (state != ST_DONE);

endmodule

`default_nettype wire
