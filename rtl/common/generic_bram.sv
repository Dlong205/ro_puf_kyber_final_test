`timescale 1ns / 1ps

module generic_bram #(
  parameter int DEPTH = 1024,
  parameter int WIDTH = 32,
  parameter INIT_FILE = ""
)(
  input  logic        clk,
  // Port A
  input  logic        en_a,
  input  logic        we_a,
  input  logic [$clog2(DEPTH)-1:0] addr_a,
  input  logic [WIDTH-1:0] din_a,
  output logic [WIDTH-1:0] dout_a,
  // Port B
  input  logic        en_b,
  input  logic        we_b,
  input  logic [$clog2(DEPTH)-1:0] addr_b,
  input  logic [WIDTH-1:0] din_b,
  output logic [WIDTH-1:0] dout_b
);

  (* ram_style = "block" *) logic [WIDTH-1:0] mem [0:DEPTH-1];

  // Pre-initialization
  initial begin
    if (INIT_FILE != "") begin
      $readmemh(INIT_FILE, mem);
    end else begin
      for (int i = 0; i < DEPTH; i++) begin
        mem[i] = '0;
      end
    end
  end

  // Port A
  always_ff @(posedge clk) begin
    if (en_a) begin
      if (we_a) mem[addr_a] <= din_a;
      dout_a <= mem[addr_a];
    end
  end

  // Port B
  always_ff @(posedge clk) begin
    if (en_b) begin
      if (we_b) mem[addr_b] <= din_b;
      dout_b <= mem[addr_b];
    end
  end

endmodule