`timescale 1ns / 1ps

module ntt_multiplier_tb;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic en = 1'b0;
    logic [11:0] a = '0;
    logic [11:0] b = '0;
    wire [23:0] p;
    wire [23:0] ntt_p;
    integer failures = 0;
    integer i;
    logic [23:0] held;

    always #5 clk = ~clk;

    generic_mult #(
        .WIDTH_A(12),
        .WIDTH_B(12)
    ) dut (
        .clk   (clk),
        .rst_n (rst_n),
        .en    (en),
        .a     (a),
        .b     (b),
        .p     (p)
    );

    ntt_mult_12x12 ntt_dut (
        .CLK (clk),
        .A   (a),
        .B   (b),
        .P   (ntt_p)
    );

    task automatic apply_and_check(input logic [11:0] ta,
                                   input logic [11:0] tb);
        logic [23:0] expected;
        begin
            @(negedge clk);
            a = ta;
            b = tb;
            en = 1'b1;
            expected = ta * tb;
            @(posedge clk);
            #1;
            if (p !== expected) begin
                $error("multiply mismatch: %0d * %0d = %0d, got %0d",
                       ta, tb, expected, p);
                failures = failures + 1;
            end
            if (ntt_p !== expected) begin
                $error("NTT wrapper mismatch: %0d * %0d = %0d, got %0d",
                       ta, tb, expected, ntt_p);
                failures = failures + 1;
            end
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        rst_n = 1'b1;

        apply_and_check(12'd0,    12'd0);
        apply_and_check(12'd1,    12'd4095);
        apply_and_check(12'd4095, 12'd4095);
        apply_and_check(12'd3329, 12'd2285);

        for (i = 0; i < 10000; i = i + 1)
            apply_and_check($urandom, $urandom);

        held = p;
        @(negedge clk);
        en = 1'b0;
        a = 12'hfff;
        b = 12'hfff;
        repeat (3) @(posedge clk);
        #1;
        if (p !== held) begin
            $error("enable hold failed: expected %0d, got %0d", held, p);
            failures = failures + 1;
        end

        @(negedge clk);
        rst_n = 1'b0;
        #1;
        if (p !== 24'd0) begin
            $error("asynchronous reset failed: got %0d", p);
            failures = failures + 1;
        end

        if (failures == 0)
            $display("PASS: NTT wrapper 10004 vectors; generic enable hold/reset");
        else
            $fatal(1, "FAIL: %0d multiplier checks failed", failures);
        $finish;
    end
endmodule
