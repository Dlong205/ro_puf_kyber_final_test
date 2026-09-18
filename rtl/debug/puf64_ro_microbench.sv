`timescale 1ns / 1ps

// C0 measurement core: one production-topology RO, one explicit FDCE
// divide-by-two prescaler, and a LOCAL RIPPLE counter built from explicit
// FDCE stages so every clock net has fanout 1 and no RO/prescaler net is
// promoted to BUFG/BUFH or converted to a 100 MHz clock-enable.
module puf64_ro_microbench #(
    parameter integer REF_CYCLES = 1023,
    parameter integer CLEAR_CYCLES = 8,
    parameter integer SETTLE_CYCLES = 8,
    parameter integer CAPTURE_TIMEOUT = 1024,
    parameter integer RO_FREQ_OFFSET = 1,
    parameter integer WIDTH = 16
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
    logic [4:0] settle_cnt;
    logic [11:0] timeout_cnt;
    reg async_clear;
    reg ro_en_r;
    reg count_en_r;

    (* keep = "true" *) wire ro_tap;
    kp_ro_cell #(.FREQ_OFFSET(RO_FREQ_OFFSET)) ro0 (
        .clk(clk), .rst_n(rst_n), .en(ro_en_r), .cfg(4'd0), .o(ro_tap)
    );

    wire presc_q;
    wire [WIDTH-1:0] ripple_q;
    kp_ripple_counter #(.WIDTH(WIDTH)) ripple (
        .clk(ro_tap), .clear(async_clear), .q(ripple_q), .presc_q(presc_q)
    );

    reg [WIDTH-1:0] cap_s1, cap_s2, cap_s3;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cap_s1 <= '0; cap_s2 <= '0; cap_s3 <= '0;
        end else begin
            cap_s1 <= ripple_q; cap_s2 <= cap_s1; cap_s3 <= cap_s2;
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
                    if (cap_s2 == cap_s3) begin
                        captured_measure <= {{(32-WIDTH){1'b0}}, cap_s2};
                        captured_free <= {{(32-WIDTH){1'b0}}, cap_s2};
                        capture_stable <= 1'b1;
                        state <= S_DONE;
                    end else if (timeout_cnt == CAPTURE_TIMEOUT - 1) begin
                        captured_measure <= {{(32-WIDTH){1'b0}}, cap_s2};
                        captured_free <= {{(32-WIDTH){1'b0}}, cap_s2};
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
