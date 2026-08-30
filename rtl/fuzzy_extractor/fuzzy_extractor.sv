`timescale 1ns / 1ps

module fuzzy_extractor #(
    parameter int T         = 8,
    parameter int DATA_BITS = 192,
    parameter int N         = 264,
    parameter int BITS      = 8
)(
    input  logic                  clk,
    input  logic                  rst_n,

    input  logic                  start,
    input  logic                  mode,            // 0: enroll (encode), 1: reconstruct (decode)

    input  logic [N-1:0]          response_in,     // PUF response (noisy or not)
    input  logic [N-1:0]          helper_in,       // stored helper data (decode only)

    output logic [N-1:0]          helper_out,      // generated helper data (enroll)
    output logic [DATA_BITS-1:0]  key_out,         // extracted key
    output logic                  busy,
    output logic                  done,
    output logic                  success          // decode: corrected word is a valid codeword
);

    localparam int DATA_WORDS = DATA_BITS / BITS;
    localparam int CODE_WORDS = N / BITS;

    typedef enum logic [3:0] {
        S_IDLE       = 4'd0,
        S_ENC        = 4'd1,
        S_HELPER     = 4'd2,
        S_DEC_FEED   = 4'd3,
        S_DEC_WAIT   = 4'd4,
        S_DEC_CAP    = 4'd5,
        S_KEYOUT     = 4'd6,
        S_VERIFY_ENC = 4'd7,
        S_VERIFY_CMP = 4'd8
    } state_t;

    state_t state, next_state;

    logic [5:0]            word_cnt;
    logic                  cap;
    logic [N-1:0]          resp_reg;
    logic [N-1:0]          helper_reg;
    logic [N-1:0]          r_reg;
    logic [DATA_BITS-1:0]  key_reg;
    logic [N-1:0]          cw_reg;
    logic [N-1:0]          err_reg;
    logic [N-1:0]          corrected;
    logic [N-1:0]          dec_word;
    logic [DATA_BITS-1:0]  dec_key;
    logic                  done_reg;
    logic                  success_reg;

    // ---- encoder / decoder wireups ----
    logic [BITS-1:0] enc_data_in;
    logic            enc_start;
    logic            enc_ce;
    logic            enc_ready;
    logic [BITS-1:0] enc_data_out;
    logic            enc_first;
    logic            enc_last;
    logic            enc_data_bits;
    logic            enc_ecc_bits;

    logic [BITS-1:0] dec_data_in;
    logic            dec_start_in;
    logic [BITS-1:0] dec_err_out;
    logic            dec_first_out;

    xilinx_encode #(
        .T(T),
        .DATA_BITS(DATA_BITS),
        .BITS(BITS),
        .PIPELINE_STAGES(0)
    ) u_encode (
        .data_in   (enc_data_in),
        .clk_in    (clk),
        .start     (enc_start),
        .ce        (enc_ce),
        .ready     (enc_ready),
        .data_out  (enc_data_out),
        .first     (enc_first),
        .last      (enc_last),
        .data_bits (enc_data_bits),
        .ecc_bits  (enc_ecc_bits)
    );

    xilinx_decoder #(
        .T(T),
        .DATA_BITS(DATA_BITS),
        .BITS(BITS),
        .SYN_REG_RATIO(1),
        .ERR_REG_RATIO(1),
        .SYN_PIPELINE_STAGES(0),
        .ERR_PIPELINE_STAGES(0),
        .ACCUM(1)
    ) u_decode (
        .data_in   (dec_data_in),
        .clk_in    (clk),
        .start_in  (dec_start_in),
        .err_out   (dec_err_out),
        .first_out (dec_first_out)
    );

    // ------------------------------------------------
    // FSM
    // ------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            word_cnt    <= '0;
            cap         <= 1'b0;
            resp_reg    <= '0;
            helper_reg  <= '0;
            r_reg       <= '0;
            key_reg     <= '0;
            cw_reg      <= '0;
            err_reg     <= '0;
            corrected   <= '0;
            done_reg    <= 1'b0;
            success_reg <= 1'b0;
            helper_out  <= '0;
            key_out     <= '0;
        end else begin
            state    <= next_state;
            done_reg <= 1'b0;

            case (state)
                S_IDLE: begin
                    word_cnt <= '0;
                    cap      <= 1'b0;
                    cw_reg   <= '0;
                    if (start) begin
                        resp_reg   <= response_in;
                        helper_reg <= helper_in;
                        r_reg      <= helper_in ^ response_in;
                        key_reg    <= response_in[N-1 -: DATA_BITS];
                    end
                end

                S_ENC: begin
                    if (word_cnt < DATA_WORDS)
                        word_cnt <= word_cnt + 1'b1;
                    if (enc_first)
                        cap <= 1'b1;
                    if (cap || enc_first)
                        cw_reg <= {cw_reg[N-BITS-1:0], enc_data_out};
                    if (enc_last)
                        cap <= 1'b0;
                end

                S_HELPER: begin
                    helper_out <= cw_reg ^ resp_reg;
                    key_out    <= key_reg;
                    success_reg <= 1'b1;
                    done_reg    <= 1'b1;
                end

                S_DEC_FEED: begin
                    if (word_cnt < CODE_WORDS - 1)
                        word_cnt <= word_cnt + 1'b1;
                end

                S_DEC_WAIT: begin
                    word_cnt <= '0;
                    if (dec_first_out)
                        err_reg <= {err_reg[N-BITS-1:0], dec_err_out};
                end

                S_DEC_CAP: begin
                    err_reg <= {err_reg[N-BITS-1:0], dec_err_out};
                    if (word_cnt < CODE_WORDS - 1)
                        word_cnt <= word_cnt + 1'b1;
                end

                S_KEYOUT: begin
                    corrected <= r_reg ^ err_reg;
                    key_reg   <= dec_key;
                    key_out   <= dec_key;
                    word_cnt  <= '0;
                    cap       <= 1'b0;
                    cw_reg    <= '0;
                end

                S_VERIFY_ENC: begin
                    if (word_cnt < DATA_WORDS)
                        word_cnt <= word_cnt + 1'b1;
                    if (enc_first)
                        cap <= 1'b1;
                    if (cap || enc_first)
                        cw_reg <= {cw_reg[N-BITS-1:0], enc_data_out};
                    if (enc_last)
                        cap <= 1'b0;
                end

                S_VERIFY_CMP: begin
                    success_reg <= (cw_reg == corrected);
                    done_reg    <= 1'b1;
                end

                default: ;
            endcase
        end
    end

    // ------------------------------------------------
    // Combinational: next state + encoder/decoder drive
    // ------------------------------------------------
    always_comb begin
        next_state = state;
        enc_start  = 1'b0;
        enc_ce     = 1'b0;
        enc_data_in = '0;
        dec_data_in = '0;
        dec_start_in = 1'b0;

        case (state)
            S_IDLE: begin
                if (start)
                    next_state = mode ? S_DEC_FEED : S_ENC;
            end

            S_ENC: begin
                enc_ce     = 1'b1;
                enc_start  = (word_cnt == 0);
                if (word_cnt < DATA_WORDS)
                    enc_data_in = key_reg[(DATA_BITS-1) - 8*word_cnt[4:0] -: 8];
                if (enc_last)
                    next_state = S_HELPER;
            end

            S_HELPER: begin
                next_state = S_IDLE;
            end

            S_DEC_FEED: begin
                dec_data_in = r_reg[(N-1) - 8*word_cnt -: 8];
                dec_start_in = (word_cnt == 0);
                if (word_cnt == CODE_WORDS - 1)
                    next_state = S_DEC_WAIT;
            end

            S_DEC_WAIT: begin
                if (dec_first_out)
                    next_state = S_DEC_CAP;
            end

            S_DEC_CAP: begin
                if (word_cnt == CODE_WORDS - 2)
                    next_state = S_KEYOUT;
            end

            S_KEYOUT: begin
                next_state = S_VERIFY_ENC;
            end

            S_VERIFY_ENC: begin
                enc_ce     = 1'b1;
                enc_start  = (word_cnt == 0);
                if (word_cnt < DATA_WORDS)
                    enc_data_in = key_reg[(DATA_BITS-1) - 8*word_cnt[4:0] -: 8];
                if (enc_last)
                    next_state = S_VERIFY_CMP;
            end

            S_VERIFY_CMP: begin
                next_state = S_IDLE;
            end

            default: ;
        endcase
    end

    assign busy    = (state != S_IDLE);
    assign done    = done_reg;
    assign success = success_reg;

    assign dec_word = r_reg ^ err_reg;
    assign dec_key  = dec_word[N-1 -: DATA_BITS];

endmodule