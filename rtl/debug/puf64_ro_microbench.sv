`timescale 1ns / 1ps

// Phase B microbenchmark core: one production-topology RO, one explicit FDCE
// divide-by-two prescaler (D = ~Q), a free-running toggle counter and a
// windowed measurement counter, all captured into the system clock domain
// after the RO is stopped (stop-then-capture).
module puf64_ro_microbench #(
    parameter integer REF_CYCLES = 1023,
    parameter integer CLEAR_CYCLES = 8,
    parameter integer SETTLE_CYCLES = 4,
    parameter integer CAPTURE_TIMEOUT = 1024,
    parameter integer RO_FREQ_OFFSET = 1
)(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    output logic        busy,
    output logic        done,
    output logic        capture_stable,
    output logic        capture_timeout,
    output logic [31:0] captured_free,
    output logic [31:0] captured_measure,
    output logic [15:0] ref_cycles_obs,
    output logic        presc_q_obs,
    output logic        ro_en_obs
);
    localparam logic [2:0] S_IDLE = 3'd0;
    localparam logic [2:0] S_CLEAR = 3'd1;
    localparam logic [2:0] S_MEASURE = 3'd2;
    localparam logic [2:0] S_QUIESCE = 3'd3;
    localparam logic [2:0] S_CAPTURE = 3'd4;
    localparam logic [2:0] S_DONE = 3'd5;

    logic [2:0] state;
    logic [15:0] window_cnt;
    logic [3:0] settle_cnt;
    logic [11:0] timeout_cnt;
    reg async_clear;
    reg ro_en_r;
    reg count_en_r;

    (* keep = "true" *) wire ro_tap;
    kp_ro_cell #(.FREQ_OFFSET(RO_FREQ_OFFSET)) ro0 (
        .clk(clk), .rst_n(rst_n), .en(ro_en_r), .cfg(4'd0), .o(ro_tap)
    );

    wire presc_q;
    (* DONT_TOUCH = "true" *) FDCE presc_fdce (
        .Q(presc_q), .C(ro_tap), .CE(1'b1), .CLR(async_clear), .D(~presc_q)
    );

    (* keep = "true" *) reg [31:0] free_q;
    (* keep = "true" *) reg [31:0] meas_q;
    always_ff @(posedge presc_q or posedge async_clear) begin
        if (async_clear) free_q <= '0;
        else free_q <= free_q + 1'b1;
    end
    always_ff @(posedge presc_q or posedge async_clear) begin
        if (async_clear) meas_q <= '0;
        else if (count_en_r) meas_q <= meas_q + 1'b1;
    end

    reg [31:0] free_s1, free_s2, free_s3;
    reg [31:0] meas_s1, meas_s2, meas_s3;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            free_s1 <= '0; free_s2 <= '0; free_s3 <= '0;
            meas_s1 <= '0; meas_s2 <= '0; meas_s3 <= '0;
        end else begin
            free_s1 <= free_q; free_s2 <= free_s1; free_s3 <= free_s2;
            meas_s1 <= meas_q; meas_s2 <= meas_s1; meas_s3 <= meas_s2;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            window_cnt <= '0;
            settle_cnt <= '0;
            timeout_cnt <= '0;
            async_clear <= 1'b1;
            ro_en_r <= 1'b0;
            count_en_r <= 1'b0;
            done <= 1'b0;
            capture_stable <= 1'b0;
            capture_timeout <= 1'b0;
            captured_free <= '0;
            captured_measure <= '0;
        end else begin
            done <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (start) begin
                        async_clear <= 1'b1;
                        ro_en_r <= 1'b0;
                        count_en_r <= 1'b0;
                        window_cnt <= '0;
                        settle_cnt <= '0;
                        timeout_cnt <= '0;
                        capture_stable <= 1'b0;
                        capture_timeout <= 1'b0;
                        state <= S_CLEAR;
                    end
                end
                S_CLEAR: begin
                    if (window_cnt == CLEAR_CYCLES - 1) begin
                        window_cnt <= '0;
                        async_clear <= 1'b0;
                        ro_en_r <= 1'b1;
                        count_en_r <= 1'b1;
                        state <= S_MEASURE;
                    end else begin
                        window_cnt <= window_cnt + 1'b1;
                    end
                end
                S_MEASURE: begin
                    if (window_cnt == REF_CYCLES - 1) begin
                        window_cnt <= '0;
                        ro_en_r <= 1'b0;
                        count_en_r <= 1'b0;
                        settle_cnt <= '0;
                        timeout_cnt <= '0;
                        state <= S_QUIESCE;
                    end else begin
                        window_cnt <= window_cnt + 1'b1;
                    end
                end
                S_QUIESCE: begin
                    if (settle_cnt == SETTLE_CYCLES - 1)
                        state <= S_CAPTURE;
                    else
                        settle_cnt <= settle_cnt + 1'b1;
                end
                S_CAPTURE: begin
                    if (free_s2 == free_s3 && meas_s2 == meas_s3) begin
                        captured_free <= free_s2;
                        captured_measure <= meas_s2;
                        capture_stable <= 1'b1;
                        state <= S_DONE;
                    end else if (timeout_cnt == CAPTURE_TIMEOUT - 1) begin
                        captured_free <= free_s2;
                        captured_measure <= meas_s2;
                        capture_stable <= 1'b0;
                        capture_timeout <= 1'b1;
                        state <= S_DONE;
                    end else begin
                        timeout_cnt <= timeout_cnt + 1'b1;
                    end
                end
                S_DONE: begin
                    done <= 1'b1;
                    state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end

    assign busy = (state != S_IDLE);
    assign ref_cycles_obs = REF_CYCLES[15:0];
    assign presc_q_obs = presc_q;
    assign ro_en_obs = ro_en_r;
endmodule
