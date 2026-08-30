`timescale 1ns / 1ps

module c_shift_ram_0 (
    input  wire        CLK,
    input  wire [11:0] D,
    output wire [11:0] Q
);
    generic_srl #(
        .DEPTH(5),
        .WIDTH(12)
    ) inst (
        .clk(CLK),
        .en(1'b1),
        .din(D),
        .dout(Q)
    );
endmodule

module c_shift_ram_1 (
    input  wire        CLK,
    input  wire [3:0]  D,
    output wire [3:0]  Q
);
    generic_srl #(
        .DEPTH(6),
        .WIDTH(4)
    ) inst (
        .clk(CLK),
        .en(1'b1),
        .din(D),
        .dout(Q)
    );
endmodule

module c_shift_ram_2 (
    input  wire        CLK,
    input  wire [1:0]  D,
    output wire [1:0]  Q
);
    generic_srl #(
        .DEPTH(12),
        .WIDTH(2)
    ) inst (
        .clk(CLK),
        .en(1'b1),
        .din(D),
        .dout(Q)
    );
endmodule

module c_shift_ram_3 (
    input  wire        CLK,
    input  wire [5:0]  D,
    output wire [5:0]  Q
);
    generic_srl #(
        .DEPTH(10),
        .WIDTH(6)
    ) inst (
        .clk(CLK),
        .en(1'b1),
        .din(D),
        .dout(Q)
    );
endmodule

module c_shift_ram_3_5 (
    input  wire        CLK,
    input  wire [4:0]  D,
    output wire [4:0]  Q
);
    generic_srl #(
        .DEPTH(10),
        .WIDTH(5)
    ) inst (
        .clk(CLK),
        .en(1'b1),
        .din(D),
        .dout(Q)
    );
endmodule

module c_shift_ram_3_6 (
    input  wire        CLK,
    input  wire [5:0]  D,
    output wire [5:0]  Q
);
    generic_srl #(
        .DEPTH(10),
        .WIDTH(6)
    ) inst (
        .clk(CLK),
        .en(1'b1),
        .din(D),
        .dout(Q)
    );
endmodule

module c_shift_ram_4 (
    input  wire        CLK,
    input  wire [7:0]  D,
    output wire [7:0]  Q
);
    generic_srl #(
        .DEPTH(12),
        .WIDTH(8)
    ) inst (
        .clk(CLK),
        .en(1'b1),
        .din(D),
        .dout(Q)
    );
endmodule

module c_shift_ram_4_6 (
    input  wire        CLK,
    input  wire [5:0]  D,
    output wire [5:0]  Q
);
    generic_srl #(
        .DEPTH(12),
        .WIDTH(6)
    ) inst (
        .clk(CLK),
        .en(1'b1),
        .din(D),
        .dout(Q)
    );
endmodule

module c_shift_ram_5 (
    input  wire        CLK,
    input  wire [6:0]  D,
    output wire [6:0]  Q
);
    generic_srl #(
        .DEPTH(12),
        .WIDTH(7)
    ) inst (
        .clk(CLK),
        .en(1'b1),
        .din(D),
        .dout(Q)
    );
endmodule

module c_shift_ram_6 (
    input  wire        CLK,
    input  wire [23:0] D,
    output wire [23:0] Q
);
    generic_srl #(
        .DEPTH(10),
        .WIDTH(24)
    ) inst (
        .clk(CLK),
        .en(1'b1),
        .din(D),
        .dout(Q)
    );
endmodule

module c_shift_ram_7 (
    input  wire        CLK,
    input  wire [23:0] D,
    output wire [23:0] Q
);
    generic_srl #(
        .DEPTH(6),
        .WIDTH(24)
    ) inst (
        .clk(CLK),
        .en(1'b1),
        .din(D),
        .dout(Q)
    );
endmodule

module c_shift_ram_8 (
    input  wire        CLK,
    input  wire        D,
    output wire        Q
);
    generic_srl #(
        .DEPTH(9),
        .WIDTH(1)
    ) inst (
        .clk(CLK),
        .en(1'b1),
        .din(D),
        .dout(Q)
    );
endmodule

module c_shift_ram_9 (
    input  wire        CLK,
    input  wire [11:0] D,
    output wire [11:0] Q
);
    generic_srl #(
        .DEPTH(5),
        .WIDTH(12)
    ) inst (
        .clk(CLK),
        .en(1'b1),
        .din(D),
        .dout(Q)
    );
endmodule

module c_shift_ram_10 (
    input  wire        CLK,
    input  wire [4:0]  D,
    output wire [4:0]  Q
);
    generic_srl #(
        .DEPTH(6),
        .WIDTH(5)
    ) inst (
        .clk(CLK),
        .en(1'b1),
        .din(D),
        .dout(Q)
    );
endmodule

module c_shift_ram_11 (
    input  wire        CLK,
    input  wire        D,
    output wire        Q
);
    generic_srl #(
        .DEPTH(10),
        .WIDTH(1)
    ) inst (
        .clk(CLK),
        .en(1'b1),
        .din(D),
        .dout(Q)
    );
endmodule

module c_shift_ram_12 (
    input  wire        CLK,
    input  wire [3:0]  D,
    output wire [3:0]  Q
);
    generic_srl #(
        .DEPTH(12),
        .WIDTH(4)
    ) inst (
        .clk(CLK),
        .en(1'b1),
        .din(D),
        .dout(Q)
    );
endmodule
