`timescale 1ns / 1ps

module kp_puf_top #(
    parameter int BIT_COUNT = 264,
    parameter int REF_CYCLES = 255,
    parameter int RESET_CYCLES = 8,
    parameter int SETTLE_CYCLES = 2
)(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        zeroize,
    input  logic        start,
    input  logic [7:0]  seed,
    output logic        busy,
    output logic        done,
    output logic [BIT_COUNT-1:0] response,

    // Characterization-only bundled-data snapshot.  The counters are clocked
    // by the selected ROs, so these values are not sampled while either RO is
    // running.  The controller first disables both ROs, waits SETTLE_CYCLES,
    // and only then asserts telemetry_valid for one system-clock cycle.
    output logic        telemetry_valid,
    output logic [8:0]  telemetry_index,
    output logic [7:0]  telemetry_challenge,
    output logic [31:0] telemetry_count0,
    output logic [31:0] telemetry_count1,
    output logic        telemetry_winner
);

    logic        lfsr_dv, count_en, ref_en, lfsr_en, sr_en, ro_en, cnt_rst;
    logic [7:0]  challenge;
    logic [15:0] ro_out0, ro_out1;
    logic        mux0_out, mux1_out;
    logic [31:0] cnt0, cnt1;
    logic        winner;
    (* ASYNC_REG = "TRUE" *) logic winner_meta;
    (* ASYNC_REG = "TRUE" *) logic winner_sync;
    // Bundled multi-bit CDC: cnt*_quiet_q* are only consumed after the source
    // clocks have been stopped for the controller's quiesce interval.  They
    // are deliberately not marked ASYNC_REG because independent per-bit
    // synchronizers would not provide counter-word coherence.
    logic [31:0] cnt0_quiet_q1, cnt0_quiet_q2;
    logic [31:0] cnt1_quiet_q1, cnt1_quiet_q2;
    logic [8:0]  telemetry_next_index;
    logic        lfsr_done;
    wire         puf_rst_n = rst_n & ~zeroize;

    kp_puf_control #(
        .BIT_COUNT(BIT_COUNT),
        .REF_CYCLES(REF_CYCLES),
        .RESET_CYCLES(RESET_CYCLES),
        .SETTLE_CYCLES(SETTLE_CYCLES)
    ) ctrl_inst (
        .clk      (clk),
        .rst_n    (puf_rst_n),
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
        .rst_n     (puf_rst_n),
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
                .rst_n (puf_rst_n),
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
                .rst_n (puf_rst_n),
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
        .rst_n  (puf_rst_n),
        .cnt_rst(cnt_rst),
        .q      (cnt0)
    );

    kp_counter_puf #(
        .SIZE(32)
    ) counter1 (
        .clk    (mux1_out),
        .en     (count_en),
        .rst_n  (puf_rst_n),
        .cnt_rst(cnt_rst),
        .q      (cnt1)
    );

    kp_comparator comp_inst (
        .count0 (cnt0),
        .count1 (cnt1),
        .winner (winner)
    );

    // The RO counters are asynchronous to clk.  The FSM first disables both
    // ROs and waits SETTLE_CYCLES; this two-flop path then transfers the now
    // stable comparator result into the system-clock domain before capture.
    always_ff @(posedge clk or negedge puf_rst_n) begin
        if (!puf_rst_n) begin
            winner_meta <= 1'b0;
            winner_sync <= 1'b0;
            cnt0_quiet_q1 <= '0;
            cnt0_quiet_q2 <= '0;
            cnt1_quiet_q1 <= '0;
            cnt1_quiet_q2 <= '0;
        end else begin
            winner_meta <= winner;
            winner_sync <= winner_meta;
            cnt0_quiet_q1 <= cnt0;
            cnt0_quiet_q2 <= cnt0_quiet_q1;
            cnt1_quiet_q1 <= cnt1;
            cnt1_quiet_q2 <= cnt1_quiet_q1;
        end
    end

    // Publish exactly one coherent record for every captured response bit.
    // At S_CAPTURE, cnt*_quiet_q2 contains a word observed after the RO clocks
    // were quiescent; the challenge is still the one used for that measurement
    // because the LFSR advances on the same closing edge.
    // Telemetry is diagnostic state in the system-clock domain.  Reset it
    // synchronously so telemetry_valid can safely drive a characterization
    // BRAM write enable without introducing an asynchronous RAM control path.
    // The PUF measurement/control path keeps its original reset semantics.
    always_ff @(posedge clk) begin
        if (!puf_rst_n) begin
            telemetry_valid      <= 1'b0;
            telemetry_next_index <= '0;
            telemetry_index      <= '0;
            telemetry_challenge  <= '0;
            telemetry_count0     <= '0;
            telemetry_count1     <= '0;
            telemetry_winner     <= 1'b0;
        end else begin
            telemetry_valid <= 1'b0;
            if (start)
                telemetry_next_index <= '0;
            if (sr_en) begin
                telemetry_valid      <= 1'b1;
                telemetry_index      <= telemetry_next_index;
                telemetry_challenge  <= challenge;
                telemetry_count0     <= cnt0_quiet_q2;
                telemetry_count1     <= cnt1_quiet_q2;
                telemetry_winner     <= (cnt0_quiet_q2 > cnt1_quiet_q2) ? 1'b0 : 1'b1;
                telemetry_next_index <= telemetry_next_index + 1'b1;
            end
        end
    end

    kp_shiftReg #(
        .WIDTH(BIT_COUNT)
    ) shiftreg_inst (
        .clk   (clk),
        .rst_n (puf_rst_n),
        .en    (sr_en),
        .s_in  (winner_sync),
        .p_out (response)
    );

`ifndef SYNTHESIS
    // Switching the selected oscillator while an RO is active can create a
    // runt pulse on the muxed clock.  The controller must settle challenge
    // only while ro_en is low.
    logic [7:0] challenge_prev;
    always_ff @(posedge clk or negedge puf_rst_n) begin
        if (!puf_rst_n) begin
            challenge_prev <= '0;
        end else begin
            if (ro_en && challenge != challenge_prev)
                $error("PUF challenge changed while ring oscillators were enabled");
            if (telemetry_valid && telemetry_index >= BIT_COUNT)
                $error("PUF telemetry index exceeded configured response width");
            challenge_prev <= challenge;
        end
    end
`endif

endmodule
