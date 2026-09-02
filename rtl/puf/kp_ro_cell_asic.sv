`timescale 1ns / 1ps

// Digital boundary for the physical ASIC ring-oscillator macro.  The macro
// must guarantee ro_clk=0 while en=0.  Its cell netlist, Liberty, LEF and GDS
// views are technology-specific and intentionally live outside generic RTL.
module kp_ro_cell_asic #(
    parameter int FREQ_OFFSET = 0
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       en,
    input  logic [3:0] cfg,
    output logic       o
);
    logic macro_enable;
    logic ro_clk;

    assign macro_enable = en & rst_n;

    kp_asic_ro_macro #(
        .CELL_ID(FREQ_OFFSET)
    ) u_ro_macro (
        .en     (macro_enable),
        .ro_clk (ro_clk)
    );

    assign o = ro_clk;
endmodule
