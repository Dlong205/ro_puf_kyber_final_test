`timescale 1ns / 1ps

module kp_puf_top #(
    parameter int BIT_COUNT = 264,
    parameter int REF_CYCLES = 255
)(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    input  logic [7:0]  seed,
    output logic        busy,
    output logic        done,
    output logic [BIT_COUNT-1:0] response
);

    logic        lfsr_dv, count_en, ref_en, lfsr_en, sr_en, ro_en, cnt_rst;
    logic [7:0]  challenge;
    logic [15:0] ro_out0, ro_out1;
    logic        mux0_out, mux1_out;
    logic [31:0] cnt0, cnt1;
    logic        winner;
    logic        lfsr_done;

    kp_puf_control #(
        .BIT_COUNT(BIT_COUNT),
        .REF_CYCLES(REF_CYCLES)
    ) ctrl_inst (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (start),
        .lfsr_dv  (lfsr_dv),
        .count_en (count_en),
        .ref_en   (ref_en),
        .lfsr_en  (lfsr_en),
        .sr_en    (sr_en),
        .ro_en    (ro_en),
        .cnt_rst  (cnt_rst),
        .busy     (busy),
        .done     (done)
    );

    kp_lfsr #(
        .NUM_BITS(8)
    ) lfsr_inst (
        .clk       (clk),
        .rst_n     (rst_n),
        .en        (lfsr_en),
        .seed_dv   (lfsr_dv),
        .seed      (seed),
        .lfsr_data (challenge),
        .lfsr_done (lfsr_done)
    );

    genvar i;
    generate
        for (i = 0; i < 16; i++) begin : ring0
            kp_ro_cell #(
                .FREQ_OFFSET(i * 3 + 1)
            ) ro0 (
                .clk (clk),
                .rst_n (rst_n),
                .en  (ro_en),
                .cfg (challenge[3:0]),
                .o   (ro_out0[i])
            );
        end

        for (i = 0; i < 16; i++) begin : ring1
            kp_ro_cell #(
                .FREQ_OFFSET(i * 3 + 17)
            ) ro1 (
                .clk (clk),
                .rst_n (rst_n),
                .en  (ro_en),
                .cfg (challenge[7:4]),
                .o   (ro_out1[i])
            );
        end
    endgenerate

    kp_mux16to1 mux0 (
        .in    (ro_out0),
        .select(challenge[3:0]),
        .out   (mux0_out)
    );

    kp_mux16to1 mux1 (
        .in    (ro_out1),
        .select(challenge[7:4]),
        .out   (mux1_out)
    );

    kp_counter_puf #(
        .SIZE(32)
    ) counter0 (
        .clk    (mux0_out),
        .en     (count_en),
        .rst_n  (rst_n),
        .cnt_rst(cnt_rst),
        .q      (cnt0)
    );

    kp_counter_puf #(
        .SIZE(32)
    ) counter1 (
        .clk    (mux1_out),
        .en     (count_en),
        .rst_n  (rst_n),
        .cnt_rst(cnt_rst),
        .q      (cnt1)
    );

    kp_comparator comp_inst (
        .count0 (cnt0),
        .count1 (cnt1),
        .winner (winner)
    );

    kp_shiftReg #(
        .WIDTH(BIT_COUNT)
    ) shiftreg_inst (
        .clk   (clk),
        .rst_n (rst_n),
        .en    (sr_en),
        .s_in  (winner),
        .p_out (response)
    );

endmodule