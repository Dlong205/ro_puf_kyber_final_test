`timescale 1ns / 1ps

module generic_srl #(
  parameter DEPTH = 16,
  parameter WIDTH = 32
)(
  input  wire        clk,
  input  wire        en,
  input  wire [WIDTH-1:0] din,
  output wire [WIDTH-1:0] dout
);

  // SRL inference - Vivado will map to SRL16E/SRL32E or BRAM based on DEPTH
  (* sh_reg_extract = "yes" *) reg [WIDTH-1:0] shift_reg [0:DEPTH-1];

  genvar i;
  generate
    if (DEPTH == 1) begin : gen_depth1
      always @(posedge clk) begin
        if (en) begin
          shift_reg[0] <= din;
        end
      end
    end else begin : gen_depth_gt1
      integer i;
      always @(posedge clk) begin
        if (en) begin
          shift_reg[0] <= din;
          for (i = 1; i < DEPTH; i = i + 1) begin
            shift_reg[i] <= shift_reg[i-1];
          end
        end
      end
    end
  endgenerate

  assign dout = shift_reg[DEPTH-1];

endmodule