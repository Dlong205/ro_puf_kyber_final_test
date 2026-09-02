`timescale 1ns / 1ps

// Simulation/lint declaration for the Xilinx 7-series LUT6_L primitive.
// This file is never part of synthesis or ASIC source lists.
module LUT6_L #(
    parameter logic [63:0] INIT = 64'd0
)(
    output wire LO,
    input  wire I0,
    input  wire I1,
    input  wire I2,
    input  wire I3,
    input  wire I4,
    input  wire I5
);
    wire [5:0] lut_index = {I5, I4, I3, I2, I1, I0};
    assign LO = INIT[lut_index];
endmodule
