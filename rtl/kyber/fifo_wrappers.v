`timescale 1ns / 1ps

// FIFO Wrapper to match original Xilinx FIFO Generator interface
module fifo_wrapper_36_32 (
    input wire clk,
    input wire rst_n,
    input wire wr_en,
    input wire [35:0] wr_data,
    input wire rd_en,
    output wire [35:0] dout,
    output wire full,
    output wire empty
);
    wire wr_full, rd_empty;
    wire [35:0] rd_data;
    
    generic_fifo_sync #(
        .DEPTH(64),
        .WIDTH(36)
    ) inst (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(wr_en),
        .wr_data(wr_data),
        .wr_full(full),
        .wr_almost_full(),
        .wr_count(),
        .rd_en(rd_en),
        .rd_data(dout),
        .rd_empty(empty),
        .rd_almost_empty(),
        .rd_count()
    );
    
    assign full = wr_full;
    assign empty = rd_empty;
    assign dout = rd_data;
endmodule


module fifo_wrapper_25_16 (
    input wire clk,
    input wire rst_n,
    input wire wr_en,
    input wire [24:0] wr_data,
    input wire rd_en,
    input wire [8:0] prog_full_thresh,
    output wire [24:0] dout,
    output wire full,
    output wire empty,
    output wire prog_full
);
    parameter integer DEPTH = 256;
    wire wr_full, rd_empty;
    wire [24:0] rd_data;
    wire [$clog2(DEPTH):0] wcount;
    
    generic_fifo_sync #(
        .DEPTH(DEPTH),
        .WIDTH(25)
    ) inst (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(wr_en),
        .wr_data(wr_data),
        .wr_full(full),
        .wr_almost_full(),
        .wr_count(wcount),
        .rd_en(rd_en),
        .rd_data(dout),
        .rd_empty(empty),
        .rd_almost_empty(),
        .rd_count()
    );
    
    assign prog_full = (wcount >= prog_full_thresh);
    
    assign full = wr_full;
    assign empty = rd_empty;
    assign dout = rd_data;
endmodule


module fifo_wrapper_24_16 (
    input wire clk,
    input wire rst_n,
    input wire wr_en,
    input wire [23:0] wr_data,
    input wire rd_en,
    input wire [8:0] prog_full_thresh,
    output wire [23:0] dout,
    output wire full,
    output wire empty,
    output wire prog_full
);
    parameter integer DEPTH = 1024;
    wire wr_full, rd_empty;
    wire [23:0] rd_data;
    wire [$clog2(DEPTH):0] wcount;
    
    generic_fifo_sync #(
        .DEPTH(DEPTH),
        .WIDTH(24)
    ) inst (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(wr_en),
        .wr_data(wr_data),
        .wr_full(full),
        .wr_almost_full(),
        .wr_count(wcount),
        .rd_en(rd_en),
        .rd_data(dout),
        .rd_empty(empty),
        .rd_almost_empty(),
        .rd_count()
    );
    
    assign full = wr_full;
    assign empty = rd_empty;
    assign dout = rd_data;
    assign prog_full = wcount > prog_full_thresh;
endmodule


module fifo_wrapper_32_16 (
    input wire clk,
    input wire rst_n,
    input wire wr_en,
    input wire [31:0] wr_data,
    input wire rd_en,
    output wire [31:0] dout,
    output wire full,
    output wire empty
);
    wire wr_full, rd_empty;
    wire [31:0] rd_data;
    
    generic_fifo_sync #(
        .DEPTH(1024),
        .WIDTH(32)
    ) inst (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(wr_en),
        .wr_data(wr_data),
        .wr_full(full),
        .wr_almost_full(),
        .wr_count(),
        .rd_en(rd_en),
        .rd_data(dout),
        .rd_empty(empty),
        .rd_almost_empty(),
        .rd_count()
    );
    
    assign full = wr_full;
    assign empty = rd_empty;
    assign dout = rd_data;
endmodule


module fifo_wrapper_33_16 (
    input wire clk,
    input wire rst_n,
    input wire wr_en,
    input wire [32:0] wr_data,
    input wire rd_en,
    output wire [32:0] dout,
    output wire full,
    output wire empty
);
    wire wr_full, rd_empty;
    wire [32:0] rd_data;
    
    generic_fifo_sync #(
        .DEPTH(1024),
        .WIDTH(33)
    ) inst (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(wr_en),
        .wr_data(wr_data),
        .wr_full(full),
        .wr_almost_full(),
        .wr_count(),
        .rd_en(rd_en),
        .rd_data(dout),
        .rd_empty(empty),
        .rd_almost_empty(),
        .rd_count()
    );
    
    assign full = wr_full;
    assign empty = rd_empty;
    assign dout = rd_data;
endmodule


module fifo_wrapper_34_16 (
    input wire clk,
    input wire rst_n,
    input wire wr_en,
    input wire [33:0] wr_data,
    input wire rd_en,
    output wire [33:0] dout,
    output wire full,
    output wire empty
);
    wire wr_full, rd_empty;
    wire [33:0] rd_data;
    
    generic_fifo_sync #(
        .DEPTH(1024),
        .WIDTH(34)
    ) inst (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(wr_en),
        .wr_data(wr_data),
        .wr_full(full),
        .wr_almost_full(),
        .wr_count(),
        .rd_en(rd_en),
        .rd_data(dout),
        .rd_empty(empty),
        .rd_almost_empty(),
        .rd_count()
    );
    
    assign full = wr_full;
    assign empty = rd_empty;
    assign dout = rd_data;
endmodule


module fifo_wrapper_10_16 (
    input wire clk,
    input wire rst_n,
    input wire wr_en,
    input wire [9:0] wr_data,
    input wire rd_en,
    output wire [9:0] dout,
    output wire full,
    output wire empty
);
    wire wr_full, rd_empty;
    wire [9:0] rd_data;
    
    generic_fifo_sync #(
        .DEPTH(1024),
        .WIDTH(10)
    ) inst (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(wr_en),
        .wr_data(wr_data),
        .wr_full(full),
        .wr_almost_full(),
        .wr_count(),
        .rd_en(rd_en),
        .rd_data(dout),
        .rd_empty(empty),
        .rd_almost_empty(),
        .rd_count()
    );
    
    assign full = wr_full;
    assign empty = rd_empty;
    assign dout = rd_data;
endmodule