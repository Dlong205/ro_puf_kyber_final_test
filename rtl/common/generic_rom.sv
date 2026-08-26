`timescale 1ns / 1ps

module generic_rom #(
  parameter int DEPTH = 256,
  parameter int WIDTH = 32,
  parameter INIT_FILE = ""
)(
  input  logic                    clk,
  input  logic                    en,
  input  logic [$clog2(DEPTH)-1:0] addr,
  output logic [WIDTH-1:0]        dout
);

  (* rom_style = "block" *) logic [WIDTH-1:0] mem [0:DEPTH-1];

  // Pre-initialization from file
  initial begin
    if (INIT_FILE != "") begin
      $readmemh(INIT_FILE, mem);
    end else begin
      for (int i = 0; i < DEPTH; i++) begin
        mem[i] = '0;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (en) begin
      dout <= mem[addr];
    end
  end

endmodule