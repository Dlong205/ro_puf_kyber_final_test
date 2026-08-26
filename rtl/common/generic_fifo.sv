`timescale 1ns / 1ps

module generic_fifo #(
    parameter int DEPTH = 512,
    parameter int WIDTH = 64,
    parameter int ASYNC = 0,
    parameter int ALMOST_FULL_THRESH  = DEPTH - 4,
    parameter int ALMOST_EMPTY_THRESH = 4
)(
    input  logic                   wr_clk,
    input  logic                   wr_rst_n,
    input  logic                   wr_en,
    input  logic [WIDTH-1:0]       wr_data,
    output logic                   wr_full,
    output logic                   wr_almost_full,
    output logic [$clog2(DEPTH):0] wr_count,
    
    input  logic                   rd_clk,
    input  logic                   rd_rst_n,
    input  logic                   rd_en,
    output logic [WIDTH-1:0]       rd_data,
    output logic                   rd_empty,
    output logic                   rd_almost_empty,
    output logic [$clog2(DEPTH):0] rd_count
);

    localparam int ADDR_WIDTH = $clog2(DEPTH);
    
    logic [WIDTH-1:0] mem [0:DEPTH-1];
    
    logic [ADDR_WIDTH:0] wr_ptr;
    logic [ADDR_WIDTH:0] rd_ptr;
    logic [ADDR_WIDTH:0] wr_ptr_gray;
    logic [ADDR_WIDTH:0] rd_ptr_gray;
    logic [ADDR_WIDTH:0] wr_ptr_gray_sync1;
    logic [ADDR_WIDTH:0] wr_ptr_gray_sync2;
    logic [ADDR_WIDTH:0] rd_ptr_gray_sync1;
    logic [ADDR_WIDTH:0] rd_ptr_gray_sync2;
    
    logic wr_full_int;
    logic rd_empty_int;
    
    // Gray code conversion
    function automatic logic [ADDR_WIDTH:0] bin2gray(input logic [ADDR_WIDTH:0] bin);
        return bin ^ (bin >> 1);
    endfunction
    
    // Write pointer logic
    always_ff @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_ptr <= '0;
        end else if (wr_en && !wr_full_int) begin
            wr_ptr <= wr_ptr + 1'b1;
        end
    end
    
    // Write data
    always_ff @(posedge wr_clk) begin
        if (wr_en && !wr_full_int) begin
            mem[wr_ptr[ADDR_WIDTH-1:0]] <= wr_data;
        end
    end
    
    // Read pointer logic
    always_ff @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_ptr <= '0;
        end else if (rd_en && !rd_empty_int) begin
            rd_ptr <= rd_ptr + 1'b1;
        end
    end
    
    // Read data
    always_ff @(posedge rd_clk) begin
        if (rd_en && !rd_empty_int) begin
            rd_data <= mem[rd_ptr[ADDR_WIDTH-1:0]];
        end
    end
    
    // Gray code pointers
    always_comb begin
        wr_ptr_gray = bin2gray(wr_ptr);
        rd_ptr_gray = bin2gray(rd_ptr);
    end
    
    // CDC synchronization (if ASYNC=1)
    generate
        if (ASYNC) begin : gen_async_cdc
            // wr_clk domain -> rd_clk domain
            always_ff @(posedge rd_clk or negedge rd_rst_n) begin
                if (!rd_rst_n) begin
                    wr_ptr_gray_sync1 <= '0;
                    wr_ptr_gray_sync2 <= '0;
                end else begin
                    wr_ptr_gray_sync1 <= wr_ptr_gray;
                    wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
                end
            end
            
            // rd_clk domain -> wr_clk domain
            always_ff @(posedge wr_clk or negedge wr_rst_n) begin
                if (!wr_rst_n) begin
                    rd_ptr_gray_sync1 <= '0;
                    rd_ptr_gray_sync2 <= '0;
                end else begin
                    rd_ptr_gray_sync1 <= rd_ptr_gray;
                    rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;
                end
            end
        end else begin : gen_sync
            always_comb begin
                wr_ptr_gray_sync1 = wr_ptr_gray;
                wr_ptr_gray_sync2 = wr_ptr_gray;
                rd_ptr_gray_sync1 = rd_ptr_gray;
                rd_ptr_gray_sync2 = rd_ptr_gray;
            end
        end
    endgenerate
    
    // Status flags
    logic [ADDR_WIDTH:0] wr_ptr_sync_bin;
    logic [ADDR_WIDTH:0] rd_ptr_sync_bin;
    
    // Gray to binary conversion for synchronized pointers
    function automatic logic [ADDR_WIDTH:0] gray2bin(input logic [ADDR_WIDTH:0] gray);
        logic [ADDR_WIDTH:0] bin;
        bin[ADDR_WIDTH] = gray[ADDR_WIDTH];
        for (int i = ADDR_WIDTH-1; i >= 0; i--) begin
            bin[i] = bin[i+1] ^ gray[i];
        end
        return bin;
    endfunction
    
    always_comb begin
        wr_ptr_sync_bin = gray2bin(wr_ptr_gray_sync2);
        rd_ptr_sync_bin = gray2bin(rd_ptr_gray_sync2);
    end
    
    assign wr_full_int        = (wr_ptr_gray == {~rd_ptr_gray_sync2[ADDR_WIDTH:ADDR_WIDTH-1], rd_ptr_gray_sync2[ADDR_WIDTH-2:0]});
    assign rd_empty_int       = (rd_ptr_gray == wr_ptr_gray_sync2);
    assign wr_almost_full     = (wr_ptr_sync_bin - rd_ptr_sync_bin) >= ALMOST_FULL_THRESH;
    assign rd_almost_empty    = (wr_ptr_sync_bin - rd_ptr_sync_bin) <= ALMOST_EMPTY_THRESH;
    assign wr_count           = wr_ptr_sync_bin - rd_ptr_sync_bin;
    assign rd_count           = wr_ptr_sync_bin - rd_ptr_sync_bin;
    
    assign wr_full            = wr_full_int;
    assign rd_empty           = rd_empty_int;

endmodule


// Synchronous FIFO variant (simpler, single clock)
module generic_fifo_sync #(
    parameter int DEPTH = 512,
    parameter int WIDTH = 64,
    parameter int ALMOST_FULL_THRESH  = DEPTH - 4,
    parameter int ALMOST_EMPTY_THRESH = 4
)(
    input  logic                   clk,
    input  logic                   rst_n,
    input  logic                   wr_en,
    input  logic [WIDTH-1:0]       wr_data,
    output logic                   wr_full,
    output logic                   wr_almost_full,
    output logic [$clog2(DEPTH):0] wr_count,
    
    input  logic                   rd_en,
    output logic [WIDTH-1:0]       rd_data,
    output logic                   rd_empty,
    output logic                   rd_almost_empty,
    output logic [$clog2(DEPTH):0] rd_count
);

    localparam int ADDR_WIDTH = $clog2(DEPTH);
    
    logic [WIDTH-1:0] mem [0:DEPTH-1];
    
    logic [ADDR_WIDTH:0] wr_ptr;
    logic [ADDR_WIDTH:0] rd_ptr;
    
    // Write pointer with synchronous reset
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            wr_ptr <= '0;
        end else if (wr_en && !wr_full) begin
            wr_ptr <= wr_ptr + 1'b1;
        end
    end
    
    // Write data
    always_ff @(posedge clk) begin
        if (wr_en && !wr_full) begin
            mem[wr_ptr[ADDR_WIDTH-1:0]] <= wr_data;
        end
    end
    
    // Read pointer
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            rd_ptr <= '0;
        end else if (rd_en && !rd_empty) begin
            rd_ptr <= rd_ptr + 1'b1;
        end
    end
    
    // Read data
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            rd_data <= '0;
        end else if (rd_en && !rd_empty) begin
            rd_data <= mem[rd_ptr[ADDR_WIDTH-1:0]];
        end
    end
    
    // Status
    assign wr_full         = (wr_ptr[ADDR_WIDTH] != rd_ptr[ADDR_WIDTH]) && 
                             (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]);
    assign rd_empty        = (wr_ptr == rd_ptr);
    assign wr_count        = wr_ptr - rd_ptr;
    assign rd_count        = wr_ptr - rd_ptr;
    assign wr_almost_full  = wr_count >= ALMOST_FULL_THRESH;
    assign rd_almost_empty = rd_count <= ALMOST_EMPTY_THRESH;

endmodule