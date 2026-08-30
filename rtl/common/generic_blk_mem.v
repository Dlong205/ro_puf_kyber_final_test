`timescale 1ns / 1ps

module blk_mem_gen_0 (
    input  logic        clka,
    input  logic        wea,
    input  logic [8:0]  addra,
    input  logic [31:0] dina,
    input  logic        clkb,
    input  logic [8:0]  addrb,
    output logic [31:0] doutb
);
    generic_bram #(
        .DEPTH(512),
        .WIDTH(32),
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
        .din_b(32'h0),
        .dout_b(doutb)
    );

    assign clka = clk;
    assign clkb = clk;
    assign wea = wea;
    assign addra = addra;
    assign dina = dina;
    assign addrb = addrb;
    assign doutb = doutb;
endmodule

module blk_mem_gen_1 (
    input  logic        clka,
    input  logic        wea,
    input  logic [8:0]  addra,
    input  logic [31:0] dina,
    input  logic        clkb,
    input  logic [8:0]  addrb,
    output logic [31:0] doutb
);

    generic_bram #(
        .DEPTH(512),
        .WIDTH(32),
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
        .din_b(32'h0),
        .dout_b(doutb)
    );

    assign clka = clk;
    assign clkb = clk;
    assign wea = wea;
    assign addra = addra;
    assign dina = dina;
    assign addrb = addrb;
    assign doutb = doutb;
endmodule

module blk_mem_gen_2 (
    input  logic        clka,
    input  logic        wea,
    input  logic [9:0]  addra,
    input  logic [31:0] dina,
    input  logic        clkb,
    input  logic [9:0]  addrb,
    output logic [31:0] doutb
);

    generic_bram #(
        .DEPTH(1024),
        .WIDTH(32),
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
        .din_b(32'h0),
        .dout_b(doutb)
    );

    assign clka = clk;
    assign clkb = clk;
    assign wea = wea;
    assign addra = addra;
    assign dina = dina;
    assign addrb = addrb;
    assign doutb = doutb;
endmodule

module blk_mem_gen_1 (
    input  logic        clka,
    input  logic        wea,
    input  logic [9:0]  addra,
    input  logic [31:0] dina,
    input  logic        clkb,
    input  logic [9:0]  addrb,
    output logic [31:0] doutb
);

    generic_bram #(
        .DEPTH(1024),
        .WIDTH(32),
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
        .din_b(32'h0),
        .dout_b(doutb)
    );

    assign clka = clk;
    assign clkb = clk;
    assign wea = wea;
    assign addra = addra;
    assign dina = dina;
    assign addrb = addrb;
    assign doutb = doutb;
endmodule

module blk_mem_gen_0 (
    input  logic        clka,
    input  logic        wea,
    input  logic [9:0]  addra,
    input  logic [31:0] dina,
    input  logic        clkb,
    input  logic [9:0]  addrb,
    output logic [31:0] doutb
);

    generic_bram #(
        .DEPTH(1024),
        .WIDTH(32),
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
        .din_b(32'h0),
        .dout_b(doutb)
    );

    assign clka = clk;
    assign clkb = clk;
    assign wea = wea;
    assign addra = addra;
    assign dina = dina;
    assign addrb = addrb;
    assign doutb = doutb;
endmodule