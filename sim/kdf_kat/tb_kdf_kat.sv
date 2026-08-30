`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// tb_kdf_kat.sv — FIPS 202 SHAKE256 Known Answer Test for kdf_keccak
//
// Test: 192-bit key (0x00..0x17) → SHAKE256 → 512-bit output
// Reference: Python hashlib.shake_256(bytes(range(24))).digest(64)
//-----------------------------------------------------------------------------
module tb_kdf_kat(input wire clk);

    logic rst_n = 0;
    initial begin
        repeat (5) @(posedge clk);
        rst_n = 1;
    end

    int cyc = 0;
    always @(posedge clk) if (rst_n) cyc <= cyc + 1;

    // DUT
    logic        start = 0;
    logic [191:0] key_in;
    wire         done;
    wire [511:0] seed_out;

    kdf_keccak u_kdf (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (start),
        .key_in   (key_in),
        .done     (done),
        .seed_out (seed_out)
    );

    // Test key: 0x00, 0x01, 0x02, ..., 0x17 (24 bytes = 192 bits)
    // Little-endian word packing: word[0] = {0x03, 0x02, 0x01, 0x00}
    initial begin
        key_in = {
            32'h17161514, 32'h13121110,
            32'h0f0e0d0c, 32'h0b0a0908,
            32'h07060504, 32'h03020100
        };
    end

    // Expected output from Python hashlib.shake_256
    logic [511:0] expected;
    initial begin
        expected = {
            32'h3aff5570, 32'h9429424d, 32'h45de8b1c, 32'h34f7aad8,
            32'hfdf69b34, 32'hb48b340e, 32'habcf673d, 32'hfd02abad,
            32'h1ae1dc88, 32'hafb02040, 32'h370b6470, 32'heea10462,
            32'h0b3c4345, 32'h06d34af4, 32'h180ff71f, 32'h23514971
        };
    end

    // Control
    logic started = 0;
    always @(posedge clk) begin
        if (rst_n && !started && cyc == 2) begin
            start <= 1;
            started <= 1;
            $display("[KDF_KAT] Starting KDF with key = 0x000102...1617");
        end else begin
            start <= 0;
        end

        if (done) begin
            $display("[KDF_KAT] KDF done at cycle %0d", cyc);
            $display("[KDF_KAT] seed_out = %0h", seed_out);
            $display("[KDF_KAT] expected = %0h", expected);
            
            if (seed_out == expected) begin
                $display("[KDF_KAT] *** PASS: Output matches FIPS 202 SHAKE256 reference ***");
            end else begin
                $display("[KDF_KAT] *** FAIL: Output does NOT match ***");
                // Show word-by-word comparison
                for (int i = 0; i < 16; i++) begin
                    logic [31:0] got_w, exp_w;
                    got_w = seed_out[i*32 +: 32];
                    exp_w = expected[i*32 +: 32];
                    if (got_w != exp_w)
                        $display("[KDF_KAT]   word[%0d]: got=%08h expected=%08h  <-- MISMATCH", i, got_w, exp_w);
                    else
                        $display("[KDF_KAT]   word[%0d]: got=%08h OK", i, got_w);
                end
            end
            $finish;
        end

        if (cyc > 5000) begin
            $display("[KDF_KAT] *** TIMEOUT at cycle %0d ***", cyc);
            $finish;
        end
    end

endmodule
