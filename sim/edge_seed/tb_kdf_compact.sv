`timescale 1ns / 1ps
`default_nettype none

module tb_kdf_compact;
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst_n = 0, zeroize = 0, start = 0;
    logic [191:0] key_in;
    wire done;
    wire [511:0] seed_out;
    int cycles = 0;

    localparam [511:0] EXPECTED = {
        32'h3aff5570, 32'h9429424d, 32'h45de8b1c, 32'h34f7aad8,
        32'hfdf69b34, 32'hb48b340e, 32'habcf673d, 32'hfd02abad,
        32'h1ae1dc88, 32'hafb02040, 32'h370b6470, 32'heea10462,
        32'h0b3c4345, 32'h06d34af4, 32'h180ff71f, 32'h23514971
    };

    kdf_keccak_compact dut (.*);

    always @(posedge clk)
        if (rst_n && !done) begin
            cycles <= cycles + 1;
            if (cycles > 1000) $fatal(1, "compact KDF timeout");
        end

    initial begin
        key_in = {
            32'h17161514, 32'h13121110, 32'h0f0e0d0c,
            32'h0b0a0908, 32'h07060504, 32'h03020100
        };
        repeat (5) @(negedge clk);
        rst_n = 1;
        @(negedge clk); start = 1;
        @(negedge clk); start = 0;
        while (!done) @(negedge clk);
        if (seed_out !== EXPECTED)
            $fatal(1, "compact SHAKE256 KAT mismatch got=%h", seed_out);
        $display("COMPACT_KDF_KAT_PASS cycles=%0d", cycles);

        zeroize = 1;
        #1;
        if (seed_out != 0 || dut.lane_a[0] != 0 || dut.lane_a[24] != 0 ||
            dut.lane_b[0] != 0 || dut.lane_b[24] != 0 ||
            dut.column[0] != 0 || dut.column[4] != 0)
            $fatal(1, "compact KDF zeroize failed");
        zeroize = 0;
        $display("COMPACT_KDF_ZEROIZE_PASS");
        $finish;
    end
endmodule

`default_nettype wire
