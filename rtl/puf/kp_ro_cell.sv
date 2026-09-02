`timescale 1ns / 1ps

// Target-neutral RO wrapper.
//
// Default:              physical Xilinx LUT implementation (FPGA build)
// KP_RO_BEHAVIORAL:     deterministic clocked model (RTL simulation)
// KP_TARGET_ASIC:       physical ASIC RO macro boundary
module kp_ro_cell #(
    parameter int FREQ_OFFSET = 0
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       en,
    input  logic [3:0] cfg,
    output logic       o
);
`ifdef KP_RO_BEHAVIORAL
    kp_ro_cell_model #(
        .FREQ_OFFSET(FREQ_OFFSET)
    ) u_backend (
        .clk   (clk),
        .rst_n (rst_n),
        .en    (en),
        .cfg   (cfg),
        .o     (o)
    );
`elsif KP_TARGET_ASIC
    kp_ro_cell_asic #(
        .FREQ_OFFSET(FREQ_OFFSET)
    ) u_backend (
        .clk   (clk),
        .rst_n (rst_n),
        .en    (en),
        .cfg   (cfg),
        .o     (o)
    );
`else
    kp_ro_cell_xilinx #(
        .FREQ_OFFSET(FREQ_OFFSET)
    ) u_backend (
        .clk   (clk),
        .rst_n (rst_n),
        .en    (en),
        .cfg   (cfg),
        .o     (o)
    );
`endif
endmodule
