`timescale 1ns / 1ps

module generic_mult #(
  parameter WIDTH_A = 32,
  parameter WIDTH_B = 32
)(
  input  wire                   clk,
  input  wire                   rst_n,
  input  wire                   en,
  input  wire [WIDTH_A-1:0]     a,
  input  wire [WIDTH_B-1:0]     b,
  output wire [WIDTH_A+WIDTH_B-1:0] p
);

  reg [WIDTH_A+WIDTH_B-1:0] product_reg;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      product_reg <= '0;
    end else if (en) begin
      product_reg <= a * b;
    end
  end

  assign p = product_reg;

endmodule

// Xilinx mult_gen_0 compatible wrapper
module mult_gen_0 (
  input  wire        CLK,
  input  wire [11:0] A,
  input  wire [11:0] B,
  output wire [23:0] P
);
  generic_mult #(
    .WIDTH_A(12),
    .WIDTH_B(12)
  ) inst (
    .clk(CLK),
    .rst_n(1'b1),
    .en(1'b1),
    .a(A),
    .b(B),
    .p(P)
  );
endmodule