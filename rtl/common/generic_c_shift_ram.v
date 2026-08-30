`timescale 1ns / 1ps

module c_shift_ram_0 (
    input  logic        CLK,
    input  logic [7:0]  D,
    output logic [7:0]  Q
);
    generic_srl #(
        .DEPTH(1),
        .WIDTH(8)
    ) inst (
        .clk(CLK),
        .en(1'b1),
        .din(D),
        .dout(Q)
    );
endmodule

module c_shift_ram_1 (
    input  logic        CLK,
    input  logic [7:0]  D,
    output logic [7:0]  Q
);
    generic_srl #(
        .DEPTH(1),
        .WIDTH(8)
    ) inst (
        .clk(CLK),
        .en(1'b1),
        .din(D),
        .dout(Q)
    );
endmodule

module c_shift_ram_2 (
    input  logic        CLK,
    input  logic [7:0]  D,
    output logic [7:0]  Q
);
    generic_srl #(
        .DEPTH(2),
        .WIDTH(8)
    ) inst (
        .clk(CLK),
        .en(1'b1),
        .din(D),
        .dout(Q)
    );
endmodule

module c_shift_ram_3 (
    input  logic        CLK,
    input  logic [3:0]  D,
    output logic [3:0]  Q
);
    generic_srl #(
        .DEPTH(3),
        .WIDTH(4)
    ) inst (
        .clk(CLK),
        .en(1'b1),
        .din(D),
        .dout(Q)
    );
endmodule

module c_shift_ram_4 (
    input  logic        CLK,
    input  logic [9:0]  D,
    output logic [9:0]  Q
);
    generic_srl #(
        .DEPTH(4),
        .WIDTH(10)
    ) inst (
        .clk(CLK),
        .en(1'b1),
        .din(D),
        .dout(Q)
    );
endmodule

module c_shift_ram_5 (
    input  logic        CLK,
    input  logic [9:0]  D,
    output logic [9:0]  Q
);
    generic_srl #(
        .DEPTH(5),
        .WIDTH(10)
    ) inst (
        .clk(CLK),
        .en(1'b1),
        .din(D),
        .dout(Q)
    );
endmodule

module c_shift_ram_6 (
    input  logic        CLK,
    input  logic [7:0]  D,
    output logic [7:0]  Q
);
    generic_srl #(
        .DEPTH(6),
        .WIDTH(8)
    ) inst (
        .clk(CLK),
        .en(1'b1),
        .din(D),
        .dout(Q)
    );
endmodule

module c_shift_ram_7 (
    input  logic        CLK,
    input  logic [7:0]  D,
    output logic [7:0]  Q
);
    generic_srl #(
        .DEPTH(7),
        .WIDTH(8)
    ) inst (
        .clk(CLK),
        .en(1'b1),
        .din(D),
        .dout(Q)
    );
endmodule

module c_shift_ram_8 (
    input  logic        CLK,
    input  logic [7:0]  D,
    output logic [7:0]  Q
);
    generic_srl #(
        .DEPTH(8),
        .WIDTH(8)
    ) inst (
        .clk(CLK),
        .en(1'b1),
        .din(D),
        .dout(Q)
    );
endmodule

module c_shift_ram_9 (
    input  logic        CLK,
    input  logic [3:0]  D,
    output logic [3:0]  Q
);
    generic_srl #(
        .DEPTH(9),
        .WIDTH(4)
    ) inst (
        .clk(CLK),
        .en(1'b1),
        .din(D),
        .dout(Q)
    );
endmodule

module c_shift_ram_10 (
    input  logic        CLK,
    input  logic [7:0]  D,
    output logic [7:0]  Q
);
    generic_srl #(
        .DEPTH(10),
        .WIDTH(8)
    ) inst (
        .clk(CLK),
        .en(1'b1),
        .din(D),
        .dout(Q)
    );
endmodule

module c_shift_ram_11 (
    input  logic        CLK,
    input  logic [1:0]  D,
    output logic [1:0]  Q
);
    generic_srl #(
        .DEPTH(11),
        .WIDTH(2)
    ) inst (
        .clk(CLK),
        .en(1'b1),
        .din(D),
        .dout(Q)
    );
endmodule