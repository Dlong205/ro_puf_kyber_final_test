`timescale 1ns / 1ps
`default_nettype none

// KAT and negative tests for edge_root_binding.
// Golden KCV computed with host hashlib.shake_256 (see
// sim/edge_wrapper/edge_root_binding_kat.vh header).
module tb_edge_root_binding;
    // key vector words {w5,w4,w3,w2,w1,w0}; w0 = key_latch[31:0] = LE bytes
    // 00 01 02 03 -> 32'h03020100.
    localparam [191:0] KEY_A = {32'h17161514, 32'h13121110, 32'h0f0e0d0c,
                                32'h0b0a0908, 32'h07060504, 32'h03020100};
    // ctx7 vector: {gen[55:48], tag_hi[47:40], tag_lo[39:32], fe[31:24],
    //               profile[23:16], proto[15:8], rec[7:0]}
    // stream order after domain byte: rec, proto, profile, gen, fe, tag_lo, tag_hi
    localparam [55:0] CTX_A = {8'h01, 8'h00, 8'h00, 8'h01,
                               8'h01, 8'h01, 8'h01};

    `include "edge_root_binding_kat.vh"

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg zeroize = 1'b0;
    reg start = 1'b0;
    reg [191:0] key = KEY_A;
    reg [55:0]  kcv_ctx = CTX_A;
    reg [223:0] kcv_exp  = KAT_KCV_A;
    wire busy, done, kcv_pass;
    integer cycles, pass_cycles;

    always #5 clk = ~clk;

    edge_root_binding dut (
        .clk(clk), .rst_n(rst_n), .zeroize(zeroize), .start(start),
        .root_key(key), .kcv_ctx(kcv_ctx), .kcv_ref(kcv_exp),
        .busy(busy), .done(done), .kcv_pass(kcv_pass)
    );

    task automatic run_check(input [223:0] reference,
                             input [95:0]  name,
                             input integer expect_pass);
        begin
            kcv_exp = reference;
            @(negedge clk); start = 1'b1;
            @(negedge clk); start = 1'b0;
            cycles = 0;
            while (!done && cycles < 400) begin
                @(posedge clk); cycles = cycles + 1;
            end
            if (cycles >= 400) $fatal(1, "KCV %0s timed out", name);
            if (kcv_pass !== expect_pass[0])
                $fatal(1, "KCV %0s: pass=%b expected=%0d",
                       name, kcv_pass, expect_pass);
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        // 1. Correct key + correct reference must pass.
        run_check(KAT_KCV_A, "A", 1);
        pass_cycles = cycles;
        @(negedge clk);

        // 2. Wrong root key must fail (simulates a different enrollment).
        key = {32'hdeadbeef, 32'hcafebabe, 32'h0badf00d,
               32'h12345678, 32'h9abcdef0, 32'h55aa55aa};
        run_check(KAT_KCV_A, "wrongroot", 0);

        // 3. Right key but wrong context (version/mapping mismatch) fails.
        key = KEY_A; kcv_ctx = {8'h01, 8'h00, 8'h00, 8'h01,
                            8'h01, 8'h01, 8'h02};
        run_check(KAT_KCV_A, "wrongctx", 0);

        // 4. Single-byte KCV reference corruption at first/middle/last byte.
        kcv_ctx = CTX_A;
        run_check(KAT_KCV_A ^ 224'h000000000000000000000000000000000000000000000000000000ff, "kcv0", 0);
        run_check(KAT_KCV_A ^ 224'h00000000000000000000000000000000000000000000000000ff0000, "kcv-mid", 0);
        run_check(KAT_KCV_A ^ 224'hff000000000000000000000000000000000000000000000000000000, "kcv-last", 0);

        // 5. Failure latency must equal pass latency (constant time).
        if (cycles != pass_cycles)
            $fatal(1, "fail latency %0d != pass latency %0d",
                   cycles, pass_cycles);

        // 6. Zeroize mid-computation must scrub and re-arm.
        @(negedge clk); start = 1'b1; kcv_exp = KAT_KCV_A;
        @(negedge clk); start = 1'b0;
        repeat (20) @(posedge clk);
        zeroize = 1'b1;
        @(negedge clk); zeroize = 1'b0;
        repeat (3) @(posedge clk);
        if (dut.kcv_acc !== 224'd0 || dut.key_latch !== 192'd0)
            $fatal(1, "zeroize left KCV state behind");
        run_check(KAT_KCV_A, "postzeroize", 1);

        $display("EDGE_ROOT_BINDING_KAT_PASS cycles=%0d", pass_cycles);
        $finish;
    end

    initial begin
        repeat (20000) @(posedge clk);
        $fatal(1, "timeout");
    end
endmodule

`default_nettype wire
