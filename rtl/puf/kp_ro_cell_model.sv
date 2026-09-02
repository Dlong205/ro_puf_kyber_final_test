`timescale 1ns / 1ps

// Deterministic digital model used only by RTL simulation.  FREQ_OFFSET gives
// each logical RO a repeatable frequency ordering; it does not model silicon
// process variation or replace characterization of the physical RO macro.
module kp_ro_cell_model #(
    parameter int FREQ_OFFSET = 0
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       en,
    input  logic [3:0] cfg,
    output logic       o
);
    logic [15:0] div_cnt;
    logic [15:0] div_val;
    always_comb begin
        div_val = 16'd1 + (FREQ_OFFSET[15:0] & 16'h3);
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            o <= 1'b0;
            div_cnt <= 16'd0;
        end else if (en) begin
            if (div_cnt >= div_val) begin
                o <= ~o;
                div_cnt <= 16'd0;
            end else begin
                div_cnt <= div_cnt + 1'b1;
            end
        end else begin
            o <= 1'b0;
            div_cnt <= 16'd0;
        end
    end
endmodule
