`timescale 1ns / 1ps

// C1-C4 parameterized single-topology benchmark.  Every RO uses the same
// production RO cell and the same kp_ripple_counter instance; only the two ROs
// of the selected pair are enabled, and only those two ripple counters are
// read through a data mux.  Telemetry matches the all-pairs UART interface.
module puf64_ro_bench #(
    parameter integer NUM_RO = 4,
    parameter integer WIDTH = 16,
    parameter integer REF_CYCLES = 1023,
    parameter integer CLEAR_CYCLES = 8,
    parameter integer SETTLE_CYCLES = 8,
    parameter integer CAPTURE_TIMEOUT = 1024,
    parameter integer PAIR_COUNT = (NUM_RO * (NUM_RO - 1)) / 2,
    parameter integer RO_BITS = (NUM_RO <= 1) ? 1 : $clog2(NUM_RO),
    parameter integer IDX_W = (PAIR_COUNT <= 1) ? 1 : $clog2(PAIR_COUNT)
)(
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  zeroize,
    input  logic                  start,
    output logic                  busy,
    output logic                  done,
    output logic [PAIR_COUNT-1:0] response,
    output logic                  telemetry_valid,
    output logic                  telemetry_stable,
    output logic                  telemetry_timeout,
    output logic                  telemetry_overflow_a,
    output logic                  telemetry_overflow_b,
    output logic [IDX_W-1:0]      telemetry_index,
    output logic [RO_BITS-1:0]    telemetry_pair_a,
    output logic [RO_BITS-1:0]    telemetry_pair_b,
    output logic [31:0]           telemetry_count0,
    output logic [31:0]           telemetry_count1,
    output logic                  telemetry_winner
);
    localparam logic [1:0] S_IDLE = 2'd0;
    localparam logic [1:0] S_CLEAR = 2'd1;
    localparam logic [1:0] S_MEASURE = 2'd2;
    localparam logic [1:0] S_CAPTURE = 2'd3;

    logic [1:0] state_r;
    logic [15:0] cnt_window;
    logic [4:0] cnt_settle;
    logic clear_r;
    logic ro_en_r;
    logic [RO_BITS-1:0] pair_a, pair_b;
    logic [IDX_W-1:0] pair_index;
    logic done_r;
    logic [15:0] cnt_timeout;

    wire puf_rst_n = rst_n & ~zeroize;

    (* keep = "true" *) wire [WIDTH-1:0] ripple_q [0:NUM_RO-1];
    wire [NUM_RO-1:0] ovf;
    (* keep = "true" *) wire [NUM_RO-1:0] ro_en_i;

    genvar i;
    generate
        for (i = 0; i < NUM_RO; i = i + 1) begin : ro
            (* keep = "true" *) wire ro_tap_i;
            assign ro_en_i[i] = ro_en_r && ((pair_a == i) || (pair_b == i));
            kp_ro_cell #(.FREQ_OFFSET(i * 3 + 1)) ro_cell (
                .clk(clk), .rst_n(puf_rst_n), .en(ro_en_i[i]),
                .cfg(4'd0), .o(ro_tap_i)
            );
            kp_ripple_counter #(.WIDTH(WIDTH)) counter (
                .clk(ro_tap_i), .clear(clear_r),
                .q(ripple_q[i]), .overflow(ovf[i]), .presc_q()
            );
        end
    endgenerate

    logic [WIDTH-1:0] cnt_a, cnt_b;
    wire ovf_a = ovf[pair_a];
    wire ovf_b = ovf[pair_b];
    always_comb begin
        cnt_a = ripple_q[pair_a];
        cnt_b = ripple_q[pair_b];
    end

    logic [WIDTH-1:0] a_s1, a_s2, a_s3, b_s1, b_s2, b_s3;
    reg oa1, oa2, oa3, ob1, ob2, ob3;
    always_ff @(posedge clk or negedge puf_rst_n) begin
        if (!puf_rst_n) begin
            a_s1 <= '0; a_s2 <= '0; a_s3 <= '0;
            b_s1 <= '0; b_s2 <= '0; b_s3 <= '0;
            oa1 <= 1'b0; oa2 <= 1'b0; oa3 <= 1'b0;
            ob1 <= 1'b0; ob2 <= 1'b0; ob3 <= 1'b0;
        end else begin
            a_s1 <= cnt_a; a_s2 <= a_s1; a_s3 <= a_s2;
            b_s1 <= cnt_b; b_s2 <= b_s1; b_s3 <= b_s2;
            oa1 <= ovf_a; oa2 <= oa1; oa3 <= oa2;
            ob1 <= ovf_b; ob2 <= ob1; ob3 <= ob2;
        end
    end

    logic [PAIR_COUNT-1:0] resp_shift;

    always_ff @(posedge clk or negedge puf_rst_n) begin
        if (!puf_rst_n) begin
            state_r <= S_IDLE;
            cnt_window <= '0;
            cnt_settle <= '0;
            clear_r <= 1'b1;
            ro_en_r <= 1'b0;
            pair_a <= '0;
            pair_b <= 'd1;
            pair_index <= '0;
            done_r <= 1'b0;
            telemetry_valid <= 1'b0;
            telemetry_stable <= 1'b0;
            telemetry_timeout <= 1'b0;
            telemetry_overflow_a <= 1'b0;
            telemetry_overflow_b <= 1'b0;
            telemetry_index <= '0;
            telemetry_pair_a <= '0;
            telemetry_pair_b <= '0;
            telemetry_count0 <= '0;
            telemetry_count1 <= '0;
            telemetry_winner <= 1'b0;
            cnt_timeout <= '0;
            resp_shift <= '0;
        end else begin
            done_r <= 1'b0;
            telemetry_valid <= 1'b0;
            case (state_r)
                S_IDLE: begin
                    if (start) begin
                        pair_a <= '0;
                        pair_b <= 'd1;
                        pair_index <= '0;
                        cnt_window <= '0;
                        cnt_settle <= '0;
                        clear_r <= 1'b1;
                        ro_en_r <= 1'b0;
                        cnt_timeout <= '0;
                        resp_shift <= '0;
                        state_r <= S_CLEAR;
                    end
                end
                S_CLEAR: begin
                    if (cnt_window == CLEAR_CYCLES - 1) begin
                        cnt_window <= '0;
                        clear_r <= 1'b0;
                        ro_en_r <= 1'b1;
                        state_r <= S_MEASURE;
                    end else begin
                        cnt_window <= cnt_window + 1'b1;
                    end
                end
                S_MEASURE: begin
                    if (cnt_window == REF_CYCLES - 1) begin
                        cnt_window <= '0;
                        ro_en_r <= 1'b0;
                        cnt_settle <= '0;
                        state_r <= S_CAPTURE;
                    end else begin
                        cnt_window <= cnt_window + 1'b1;
                    end
                end
                S_CAPTURE: begin
                    if (cnt_settle != SETTLE_CYCLES - 1) begin
                        cnt_settle <= cnt_settle + 1'b1;
                    end else if ((a_s2 == a_s3 && b_s2 == b_s3) ||
                                 cnt_timeout == CAPTURE_TIMEOUT - 1) begin
                        telemetry_valid <= 1'b1;
                        telemetry_stable <= (a_s2 == a_s3 && b_s2 == b_s3);
                        telemetry_timeout <= !(a_s2 == a_s3 && b_s2 == b_s3);
                        telemetry_overflow_a <= oa2;
                        telemetry_overflow_b <= ob2;
                        telemetry_index <= pair_index;
                        telemetry_pair_a <= pair_a;
                        telemetry_pair_b <= pair_b;
                        telemetry_count0 <= {{(32-WIDTH){1'b0}}, a_s2};
                        telemetry_count1 <= {{(32-WIDTH){1'b0}}, b_s2};
                        telemetry_winner <= (a_s2 > b_s2) ? 1'b0 : 1'b1;
                        resp_shift <= {resp_shift[PAIR_COUNT-2:0],
                                       (a_s2 > b_s2) ? 1'b0 : 1'b1};
                        if (pair_index == PAIR_COUNT - 1) begin
                            done_r <= 1'b1;
                            state_r <= S_IDLE;
                        end else begin
                            pair_index <= pair_index + 1'b1;
                            if (pair_b == NUM_RO - 1) begin
                                pair_a <= pair_a + 1'b1;
                                pair_b <= pair_a + 2'd2;
                            end else begin
                                pair_b <= pair_b + 1'b1;
                            end
                            clear_r <= 1'b1;
                            cnt_window <= '0;
                            cnt_timeout <= '0;
                            state_r <= S_CLEAR;
                        end
                    end else begin
                        cnt_timeout <= cnt_timeout + 1'b1;
                    end
                end
                default: state_r <= S_IDLE;
            endcase
        end
    end

    assign busy = (state_r != S_IDLE) || done_r;
    assign done = done_r;
    assign response = resp_shift;

`ifndef SYNTHESIS
    initial begin
        if (PAIR_COUNT != NUM_RO * (NUM_RO - 1) / 2)
            $error("ro_bench PAIR_COUNT mismatch");
        if (NUM_RO < 2)
            $error("ro_bench NUM_RO must be >= 2");
    end
`endif
endmodule
