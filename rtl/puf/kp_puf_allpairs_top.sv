`timescale 1ns / 1ps

// Characterization-only 32-RO all-pairs engine.
//
// The release kp_puf_top deliberately remains unchanged.  This diagnostic
// engine enumerates every unordered pair (a,b), 0 <= a < b < 32, exactly once
// so a host can select a reliability-aware 264-position mapping from a pool of
// C(32,2)=496 candidates.  Both mux inputs see all 32 ROs, giving each RO the
// same logical fanout in this image.
module kp_puf_allpairs_top #(
    parameter int PAIR_COUNT = 496,
    parameter int REF_CYCLES = 255,
    parameter int RESET_CYCLES = 8,
    parameter int SETTLE_CYCLES = 2
)(
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  zeroize,
    input  logic                  start,
    output logic                  busy,
    output logic                  done,
    output logic [PAIR_COUNT-1:0] response,
    output logic                  telemetry_valid,
    output logic [8:0]            telemetry_index,
    output logic [4:0]            telemetry_pair_a,
    output logic [4:0]            telemetry_pair_b,
    output logic [31:0]           telemetry_count0,
    output logic [31:0]           telemetry_count1,
    output logic                  telemetry_winner
);

    logic count_en, sr_en, ro_en, cnt_rst;
    logic unused_lfsr_dv, unused_ref_en, unused_lfsr_en;
    logic [4:0] pair_a, pair_b;
    logic [15:0] ro_out0, ro_out1;
    logic [31:0] ro_all;
    logic mux0_out, mux1_out;
    logic [31:0] cnt0, cnt1;
    logic winner;
    (* ASYNC_REG = "TRUE" *) logic winner_meta, winner_sync;
    logic [31:0] cnt0_quiet_q1, cnt0_quiet_q2;
    logic [31:0] cnt1_quiet_q1, cnt1_quiet_q2;
    logic [8:0] telemetry_next_index;
    wire puf_rst_n = rst_n & ~zeroize;

    kp_puf_control #(
        .BIT_COUNT(PAIR_COUNT),
        .REF_CYCLES(REF_CYCLES),
        .RESET_CYCLES(RESET_CYCLES),
        .SETTLE_CYCLES(SETTLE_CYCLES)
    ) ctrl_inst (
        .clk(clk), .rst_n(puf_rst_n), .start(start),
        .lfsr_dv(unused_lfsr_dv), .count_en(count_en),
        .ref_en(unused_ref_en), .lfsr_en(unused_lfsr_en),
        .sr_en(sr_en), .ro_en(ro_en), .cnt_rst(cnt_rst),
        .busy(busy), .done(done)
    );

    // Lexicographic unordered-pair schedule:
    // (0,1)..(0,31),(1,2)..(1,31),...,(30,31).
    // Pair changes occur only in S_CAPTURE, while every RO is disabled.
    always_ff @(posedge clk or negedge puf_rst_n) begin
        if (!puf_rst_n) begin
            pair_a <= 5'd0;
            pair_b <= 5'd1;
        end else if (start) begin
            pair_a <= 5'd0;
            pair_b <= 5'd1;
        end else if (sr_en && telemetry_next_index != PAIR_COUNT - 1) begin
            if (pair_b == 5'd31) begin
                pair_a <= pair_a + 1'b1;
                pair_b <= pair_a + 2'd2;
            end else begin
                pair_b <= pair_b + 1'b1;
            end
        end
    end

    genvar i;
    generate
        // Preserve the release hierarchy names so the existing 128-LUT
        // placement map can be audited against this diagnostic image.
        for (i = 0; i < 16; i++) begin : ring0
            kp_ro_cell #(.FREQ_OFFSET(i * 3 + 1)) ro0 (
                .clk(clk), .rst_n(puf_rst_n), .en(ro_en),
                .cfg(pair_a[3:0]), .o(ro_out0[i])
            );
        end
        for (i = 0; i < 16; i++) begin : ring1
            kp_ro_cell #(.FREQ_OFFSET(i * 3 + 17)) ro1 (
                .clk(clk), .rst_n(puf_rst_n), .en(ro_en),
                .cfg(pair_b[3:0]), .o(ro_out1[i])
            );
        end
    endgenerate

    assign ro_all = {ro_out1, ro_out0};
    assign mux0_out = ro_all[pair_a];
    assign mux1_out = ro_all[pair_b];

    kp_counter_puf #(.SIZE(32)) counter0 (
        .clk(mux0_out), .en(count_en), .rst_n(puf_rst_n),
        .cnt_rst(cnt_rst), .q(cnt0)
    );
    kp_counter_puf #(.SIZE(32)) counter1 (
        .clk(mux1_out), .en(count_en), .rst_n(puf_rst_n),
        .cnt_rst(cnt_rst), .q(cnt1)
    );
    kp_comparator comp_inst (
        .count0(cnt0), .count1(cnt1), .winner(winner)
    );

    // Bundled-data CDC: counters are sampled only after both RO clocks have
    // stopped and the controller has waited SETTLE_CYCLES.
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

    // Synchronous reset is intentional: telemetry_valid drives a BRAM write
    // enable in the UART endpoint and must not create an asynchronous control
    // path into the block RAM.
    always_ff @(posedge clk) begin
        if (!puf_rst_n) begin
            telemetry_valid      <= 1'b0;
            telemetry_next_index <= '0;
            telemetry_index      <= '0;
            telemetry_pair_a     <= '0;
            telemetry_pair_b     <= '0;
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
                telemetry_pair_a     <= pair_a;
                telemetry_pair_b     <= pair_b;
                telemetry_count0     <= cnt0_quiet_q2;
                telemetry_count1     <= cnt1_quiet_q2;
                telemetry_winner     <= (cnt0_quiet_q2 > cnt1_quiet_q2) ? 1'b0 : 1'b1;
                telemetry_next_index <= telemetry_next_index + 1'b1;
            end
        end
    end

    kp_shiftReg #(.WIDTH(PAIR_COUNT)) shiftreg_inst (
        .clk(clk), .rst_n(puf_rst_n), .en(sr_en),
        .s_in(winner_sync), .p_out(response)
    );

`ifndef SYNTHESIS
    logic [4:0] pair_a_prev, pair_b_prev;
    always_ff @(posedge clk or negedge puf_rst_n) begin
        if (!puf_rst_n) begin
            pair_a_prev <= '0;
            pair_b_prev <= 5'd1;
        end else begin
            if (ro_en && (pair_a != pair_a_prev || pair_b != pair_b_prev))
                $error("all-pairs selector changed while ROs were enabled");
            if (pair_a >= pair_b)
                $error("all-pairs scheduler emitted a non-canonical pair");
            if (telemetry_valid && telemetry_index >= PAIR_COUNT)
                $error("all-pairs telemetry index exceeded pool size");
            pair_a_prev <= pair_a;
            pair_b_prev <= pair_b;
        end
    end
`endif

endmodule
