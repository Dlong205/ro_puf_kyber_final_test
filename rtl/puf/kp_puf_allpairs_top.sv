`timescale 1ns / 1ps

// Characterization-only all-pairs engine, parameterized by NUM_RO.
//
// The release kp_puf_top deliberately remains unchanged.  This diagnostic
// engine enumerates every unordered pair (a,b), 0 <= a < b < NUM_RO, exactly
// once so a host can select a reliability-aware 264-position mapping from a
// pool of C(NUM_RO,2) candidates.  Both mux inputs see all NUM_RO ROs, giving
// each RO the same logical fanout in this image.  NUM_RO=32 reproduces the
// established 128-LUT placement map byte for byte; NUM_RO=64 provides the
// larger 2016-candidate pool used by the PUF64 qualification phase.
module kp_puf_allpairs_top #(
    parameter int NUM_RO = 32,
    parameter int PAIR_COUNT = 496,
    parameter int REF_CYCLES = 255,
    parameter int RESET_CYCLES = 8,
    parameter int SETTLE_CYCLES = 4,
    parameter int USE_PRESCALER = 1
)(
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  zeroize,
    input  logic                  start,
    output logic                  busy,
    output logic                  done,
    output logic [PAIR_COUNT-1:0] response,
    output logic                  telemetry_valid,
    output logic [IDX_W-1:0]      telemetry_index,
    output logic [RO_BITS-1:0]    telemetry_pair_a,
    output logic [RO_BITS-1:0]    telemetry_pair_b,
    output logic [31:0]           telemetry_count0,
    output logic [31:0]           telemetry_count1,
    output logic                  telemetry_winner
);
    localparam int RO_BITS = (NUM_RO <= 1) ? 1 : $clog2(NUM_RO);
    localparam int IDX_W = (PAIR_COUNT <= 1) ? 1 : $clog2(PAIR_COUNT);

    logic count_en, sr_en, ro_en, cnt_rst;
    logic unused_lfsr_dv, unused_ref_en, unused_lfsr_en;
    logic [RO_BITS-1:0] pair_a, pair_b;
    logic [NUM_RO-1:0] ro_out;
    logic [NUM_RO-1:0] pre_clk;
    logic [31:0] cnt_all [0:NUM_RO-1];
    logic [31:0] cnt0, cnt1;
    logic winner;
    (* ASYNC_REG = "TRUE" *) logic winner_meta, winner_sync;
    logic [31:0] cnt0_quiet_q1, cnt0_quiet_q2, cnt0_quiet_q3;
    logic [31:0] cnt1_quiet_q1, cnt1_quiet_q2, cnt1_quiet_q3;
    logic [IDX_W-1:0] telemetry_next_index;
    wire puf_rst_n = rst_n & ~zeroize;
    wire presc_rst_n = puf_rst_n & ~cnt_rst;
    wire cnt_stable = (cnt0_quiet_q2 == cnt0_quiet_q3) &&
                      (cnt1_quiet_q2 == cnt1_quiet_q3);

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
    // (0,1)..(0,NUM_RO-1),(1,2)..(1,NUM_RO-1),...,(NUM_RO-2,NUM_RO-1).
    // Pair changes occur only in S_CAPTURE, while every RO is disabled.
    always_ff @(posedge clk or negedge puf_rst_n) begin
        if (!puf_rst_n) begin
            pair_a <= '0;
            pair_b <= 'd1;
        end else if (start) begin
            pair_a <= '0;
            pair_b <= 'd1;
        end else if (sr_en && telemetry_next_index != PAIR_COUNT - 1) begin
            if (pair_b == NUM_RO - 1) begin
                pair_a <= pair_a + 1'b1;
                pair_b <= pair_a + 2'd2;
            end else begin
                pair_b <= pair_b + 1'b1;
            end
        end
    end

    genvar i;
    generate
        // Preserve the release hierarchy names so the physical placement map
        // (128 LUTs at NUM_RO=32, 256 LUTs at NUM_RO=64) is auditable against
        // this diagnostic image.
        for (i = 0; i < NUM_RO / 2; i++) begin : ring0
            wire ro_en_i = ro_en && ((pair_a == i) || (pair_b == i));
            kp_ro_cell #(.FREQ_OFFSET(i * 3 + 1)) ro0 (
                .clk(clk), .rst_n(puf_rst_n), .en(ro_en_i),
                .cfg(4'd0), .o(ro_out[i])
            );
            if (USE_PRESCALER) begin : presc
                (* DONT_TOUCH = "true" *) kp_ro_prescaler presc_i (
                    .clk(ro_out[i]), .rst_n(presc_rst_n), .q(pre_clk[i])
                );
            end else begin : no_presc
                assign pre_clk[i] = ro_out[i];
            end
            kp_counter_puf #(.SIZE(32)) counter_i (
                .clk(pre_clk[i]), .en(count_en), .rst_n(puf_rst_n),
                .cnt_rst(cnt_rst), .q(cnt_all[i])
            );
        end
        for (i = 0; i < NUM_RO / 2; i++) begin : ring1
            localparam int RO_INDEX = NUM_RO / 2 + i;
            wire ro_en_i = ro_en && ((pair_a == RO_INDEX) || (pair_b == RO_INDEX));
            kp_ro_cell #(.FREQ_OFFSET(i * 3 + 17)) ro1 (
                .clk(clk), .rst_n(puf_rst_n), .en(ro_en_i),
                .cfg(4'd0), .o(ro_out[RO_INDEX])
            );
            if (USE_PRESCALER) begin : presc
                (* DONT_TOUCH = "true" *) kp_ro_prescaler presc_i (
                    .clk(ro_out[RO_INDEX]), .rst_n(presc_rst_n),
                    .q(pre_clk[RO_INDEX])
                );
            end else begin : no_presc
                assign pre_clk[RO_INDEX] = ro_out[RO_INDEX];
            end
            kp_counter_puf #(.SIZE(32)) counter_i (
                .clk(pre_clk[RO_INDEX]), .en(count_en), .rst_n(puf_rst_n),
                .cnt_rst(cnt_rst), .q(cnt_all[RO_INDEX])
            );
        end
    endgenerate

    always_comb begin
        cnt0 = cnt_all[pair_a];
        cnt1 = cnt_all[pair_b];
    end

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
            cnt0_quiet_q3 <= '0;
            cnt1_quiet_q1 <= '0;
            cnt1_quiet_q2 <= '0;
            cnt1_quiet_q3 <= '0;
        end else begin
            winner_meta <= winner;
            winner_sync <= winner_meta;
            cnt0_quiet_q1 <= cnt0;
            cnt0_quiet_q2 <= cnt0_quiet_q1;
            cnt0_quiet_q3 <= cnt0_quiet_q2;
            cnt1_quiet_q1 <= cnt1;
            cnt1_quiet_q2 <= cnt1_quiet_q1;
            cnt1_quiet_q3 <= cnt1_quiet_q2;
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
                if (cnt_stable) begin
                    telemetry_valid      <= 1'b1;
                    telemetry_index      <= telemetry_next_index;
                    telemetry_pair_a     <= pair_a;
                    telemetry_pair_b     <= pair_b;
                    telemetry_count0     <= cnt0_quiet_q2;
                    telemetry_count1     <= cnt1_quiet_q2;
                    telemetry_winner     <= (cnt0_quiet_q2 > cnt1_quiet_q2) ? 1'b0 : 1'b1;
                end
                telemetry_next_index <= telemetry_next_index + 1'b1;
            end
        end
    end

    kp_shiftReg #(.WIDTH(PAIR_COUNT)) shiftreg_inst (
        .clk(clk), .rst_n(puf_rst_n), .en(sr_en),
        .s_in(winner_sync), .p_out(response)
    );

`ifndef SYNTHESIS
    initial begin
        if (NUM_RO < 4 || (NUM_RO % 2) != 0)
            $error("all-pairs NUM_RO must be even and at least 4");
        if (PAIR_COUNT != NUM_RO * (NUM_RO - 1) / 2)
            $error("all-pairs PAIR_COUNT must equal C(NUM_RO,2)");
    end
    logic [RO_BITS-1:0] pair_a_prev, pair_b_prev;
    always_ff @(posedge clk or negedge puf_rst_n) begin
        if (!puf_rst_n) begin
            pair_a_prev <= '0;
            pair_b_prev <= 'd1;
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
