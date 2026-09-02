`timescale 1ns / 1ps

// Placeholder used for ASIC-generic elaboration before a PDK is selected.
// Replace this definition with the foundry-specific RO macro views during
// synthesis and physical design.  The physical macro must stop low when en=0.
(* blackbox *)
module kp_asic_ro_macro #(
    parameter int CELL_ID = 0
)(
    input  wire en,
    output wire ro_clk
);
endmodule
