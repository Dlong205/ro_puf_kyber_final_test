module soc_bram #(
    parameter MEM_WORDS = 4096, // 16KB
    parameter INIT_FILE = "firmware.hex"
) (
    input clk,
    input rstn,
    
    // PicoRV32 memory interface
    input         mem_valid,
    output reg    mem_ready,
    input  [31:0] mem_addr,
    input  [31:0] mem_wdata,
    input  [ 3:0] mem_wstrb,
    output reg [31:0] mem_rdata
);

    // RAM declaration
    reg [31:0] memory [0:MEM_WORDS-1];
    
    // Initialize RAM with firmware.hex
    initial begin
        $readmemh(INIT_FILE, memory);
    end

    wire [31:0] word_addr = mem_addr[31:2];
    wire valid_addr = (word_addr < MEM_WORDS);

    always @(posedge clk) begin
        if (!rstn) begin
            mem_ready <= 0;
            mem_rdata <= 0;
        end else begin
            mem_ready <= 0;
            if (mem_valid && !mem_ready) begin
                if (valid_addr) begin
                    // Write
                    if (mem_wstrb[0]) memory[word_addr][ 7: 0] <= mem_wdata[ 7: 0];
                    if (mem_wstrb[1]) memory[word_addr][15: 8] <= mem_wdata[15: 8];
                    if (mem_wstrb[2]) memory[word_addr][23:16] <= mem_wdata[23:16];
                    if (mem_wstrb[3]) memory[word_addr][31:24] <= mem_wdata[31:24];
                    // Read
                    mem_rdata <= memory[word_addr];
                end else begin
                    mem_rdata <= 32'h0;
                end
                mem_ready <= 1;
            end
        end
    end

endmodule
