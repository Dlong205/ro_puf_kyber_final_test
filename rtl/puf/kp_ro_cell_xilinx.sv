`timescale 1ns / 1ps

// Xilinx 7-series implementation.  Keep all vendor primitives in this file so
// it can be omitted completely from an ASIC source list.
(* KEEP_HIERARCHY = "yes" *)
module kp_ro_cell_xilinx #(
    parameter int FREQ_OFFSET = 0
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       en,
    input  logic [3:0] cfg,
    output logic       o
);
    (* DONT_TOUCH = "true" *) logic t0, t1, t2, t3;

    // clk/rst_n/FREQ_OFFSET belong to the common interface or simulation
    // model.  The physical FPGA oscillator itself is controlled only by en.
    (* DONT_TOUCH = "true" *) LUT6_L #(
        .INIT(64'h8888888888888888)
    ) LUT6_NAND0 (
        .LO(t0), .I0(en), .I1(t3), .I2(cfg[0]),
        .I3(1'b0), .I4(1'b0), .I5(1'b0)
    );

    (* DONT_TOUCH = "true" *) LUT6_L #(
        .INIT(64'h5555555555555555)
    ) LUT6_INV0 (
        .LO(t1), .I0(t0), .I1(cfg[1]), .I2(1'b0),
        .I3(1'b0), .I4(1'b0), .I5(1'b0)
    );

    (* DONT_TOUCH = "true" *) LUT6_L #(
        .INIT(64'h5555555555555555)
    ) LUT6_INV1 (
        .LO(t2), .I0(t1), .I1(cfg[2]), .I2(1'b0),
        .I3(1'b0), .I4(1'b0), .I5(1'b0)
    );

    (* DONT_TOUCH = "true" *) LUT6_L #(
        .INIT(64'h5555555555555555)
    ) LUT6_INV2 (
        .LO(t3), .I0(t2), .I1(cfg[3]), .I2(1'b0),
        .I3(1'b0), .I4(1'b0), .I5(1'b0)
    );

    assign o = t3;
endmodule
