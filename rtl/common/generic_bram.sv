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
  output logic [WIDTH-1:0] dout_b,
  // Optional common scrub port.  A top-level controller walks scrub_addr
  // through every address while normal clients are held in reset.  Keeping
  // the erase as an ordinary sequential write preserves BRAM/SRAM inference.
  input  logic        scrub_en,
  input  logic [10:0] scrub_addr
);

  localparam int ADDR_WIDTH = $clog2(DEPTH);

  (* ram_style = "block" *) logic [WIDTH-1:0] mem [0:DEPTH-1];

  // Keep exactly one syntactic write address per RAM port.  Writing mem once
  // with addr_a and once with scrub_addr in the same process makes Vivado
  // dissolve the complete memory into registers.  These muxes preserve the
  // ordinary true-dual-port inference template while retaining sequential
  // physical erase.
  wire                  scrub_addr_valid = (scrub_addr < DEPTH);
  wire                  port_a_en = scrub_en || en_a;
  wire                  port_a_we = scrub_en ? scrub_addr_valid : we_a;
  wire [ADDR_WIDTH-1:0] port_a_addr = scrub_en ?
      (scrub_addr_valid ? scrub_addr[ADDR_WIDTH-1:0] : {ADDR_WIDTH{1'b0}}) :
      addr_a;
  wire [WIDTH-1:0]      port_a_din = scrub_en ? {WIDTH{1'b0}} : din_a;

  // Port B never participates in erase.  During scrub it reads address zero
  // and clears its output register, so no stale read value survives DONE.
  wire                  port_b_en = scrub_en || en_b;
  wire                  port_b_we = scrub_en ? 1'b0 : we_b;
  wire [ADDR_WIDTH-1:0] port_b_addr = scrub_en ? {ADDR_WIDTH{1'b0}} : addr_b;
  wire [WIDTH-1:0]      port_b_din = scrub_en ? {WIDTH{1'b0}} : din_b;

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
    if (port_a_en) begin
      if (port_a_we) mem[port_a_addr] <= port_a_din;
      if (scrub_en)
        dout_a <= '0;
      else
        dout_a <= mem[port_a_addr];
    end
  end

  // Port B
  always_ff @(posedge clk) begin
    if (port_b_en) begin
      if (port_b_we) mem[port_b_addr] <= port_b_din;
      if (scrub_en)
        dout_b <= '0;
      else
        dout_b <= mem[port_b_addr];
    end
  end

endmodule
