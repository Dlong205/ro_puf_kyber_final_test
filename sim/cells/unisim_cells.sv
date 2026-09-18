`timescale 1ns / 1ps

// Minimal simulation models for the Xilinx primitives used by the local ripple
// counter, so Verilator lint/simulation can elaborate the RTL.
module FDCE #(
    parameter INIT = 1'b0
)(
    input  wire C,
    input  wire CE,
    input  wire CLR,
    input  wire D,
    output reg  Q
);
    initial Q = INIT;
    always @(posedge C or posedge CLR) begin
        if (CLR)
            Q <= 1'b0;
        else if (CE)
            Q <= D;
    end
endmodule
