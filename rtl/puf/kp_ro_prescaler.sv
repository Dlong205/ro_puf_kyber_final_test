`timescale 1ns / 1ps

module kp_ro_prescaler (
    input  logic clk,
    input  logic rst_n,
    output logic q
);
    logic q_reg;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            q_reg <= 1'b0;
        else
            q_reg <= ~q_reg;
    end
    assign q = q_reg;
endmodule
