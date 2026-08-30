`timescale 1ns / 1ps

// 256x24 Block RAM wrapper (RAM0/RAM1).
module blk_mem_gen_0 (
    input  wire        clka,
    input  wire        wea,
    input  wire [7:0]  addra,
    input  wire [23:0] dina,
    input  wire        clkb,
    input  wire [7:0]  addrb,
    output wire [23:0] doutb
);
    generic_bram #(
        .DEPTH(256),
        .WIDTH(24),
        .INIT_FILE("")
    ) inst (
        .clk(clka),
        .en_a(1'b1),
        .we_a(wea),
        .addr_a(addra),
        .din_a(dina),
        .dout_a(),
        .en_b(1'b1),
        .we_b(1'b0),
        .addr_b(addrb),
        .din_b(24'h0),
        .dout_b(doutb)
    );
endmodule

// 128x48 Block RAM wrapper (RAM4).
module blk_mem_gen_1 (
    input  wire        clka,
    input  wire        wea,
    input  wire [6:0]  addra,
    input  wire [47:0] dina,
    input  wire        clkb,
    input  wire [6:0]  addrb,
    output wire [47:0] doutb
);

    generic_bram #(
        .DEPTH(128),
        .WIDTH(48),
        .INIT_FILE("")
    ) inst (
        .clk(clka),
        .en_a(1'b1),
        .we_a(wea),
        .addr_a(addra),
        .din_a(dina),
        .dout_a(),
        .en_b(1'b1),
        .we_b(1'b0),
        .addr_b(addrb),
        .din_b(48'h0),
        .dout_b(doutb)
    );
endmodule

// 64x24 Block RAM wrapper (RAM2/RAM3).
module blk_mem_gen_2 (
    input  wire        clka,
    input  wire        wea,
    input  wire [5:0]  addra,
    input  wire [23:0] dina,
    input  wire        clkb,
    input  wire [5:0]  addrb,
    output wire [23:0] doutb
);

    generic_bram #(
        .DEPTH(64),
        .WIDTH(24),
        .INIT_FILE("")
    ) inst (
        .clk(clka),
        .en_a(1'b1),
        .we_a(wea),
        .addr_a(addra),
        .din_a(dina),
        .dout_a(),
        .en_b(1'b1),
        .we_b(1'b0),
        .addr_b(addrb),
        .din_b(24'h0),
        .dout_b(doutb)
    );
endmodule
