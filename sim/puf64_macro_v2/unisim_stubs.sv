`timescale 1ns / 1ps
`default_nettype none

// Simulation-only functional stubs for the Xilinx primitives used by the
// macro-V2 netlist (explicit LUT1 inverters) and the golden RO backend.
// NEVER added to any synthesis file list; guarded so a synthesis run that
// somehow picks this file up fails loudly instead of shadowing UNISIM.
`ifdef SYNTHESIS
    `error "unisim_stubs.sv must never be synthesized"
`endif

module LUT1 #(
    parameter [1:0] INIT = 2'h0
) (
    input  wire I0,
    output wire O
);
    assign O = INIT[I0];
endmodule

module LUT6_L #(
    parameter [63:0] INIT = 64'h0
) (
    output wire LO,
    input  wire I0, I1, I2, I3, I4, I5
);
    assign LO = INIT[{I5, I4, I3, I2, I1, I0}];
endmodule

module FDCE (
    output reg  Q,
    input  wire C,
    input  wire CE,
    input  wire CLR,
    input  wire D
);
    always @(posedge C or posedge CLR) begin
        if (CLR)
            Q <= 1'b0;
        else if (CE)
            Q <= D;
    end
endmodule

`default_nettype wire
