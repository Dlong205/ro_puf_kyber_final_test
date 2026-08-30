`timescale 1ns / 1ps

// dist_mem_gen_5 wrapper (256x12 ROM)
module dist_mem_gen_5 (
    input  logic        clk,
    input  logic [7:0]  a,
    output logic [11:0] qspo
);
    generic_rom #(
        .DEPTH(256),
        .WIDTH(12),
        .INIT_FILE("")
    ) inst (
        .clk(clk),
        .en(1'b1),
        .addr(a),
        .dout(qspo)
    );
endmodule

// dist_mem_gen_6 wrapper (256x12 ROM)
module dist_mem_gen_6 (
    input  logic        clk,
    input  logic [7:0]  a,
    output logic [11:0] qspo
);
    generic_rom #(
        .DEPTH(256),
        .WIDTH(12),
        .INIT_FILE("")
    ) inst (
        .clk(clk),
        .en(1'b1),
        .addr(a),
        .dout(qspo)
    );
endmodule

// dist_mem_gen_7 wrapper (256x12 ROM)
module dist_mem_gen_7 (
    input  logic        clk,
    input  logic [7:0]  a,
    output logic [11:0] qspo
);
    generic_rom #(
        .DEPTH(256),
        .WIDTH(12),
        .INIT_FILE("")
    ) inst (
        .clk(clk),
        .en(1'b1),
        .addr(a),
        .dout(qspo)
    );
endmodule