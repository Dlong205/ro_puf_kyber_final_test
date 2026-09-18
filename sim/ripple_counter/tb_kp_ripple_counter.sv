`timescale 1ns / 1ps

module FDCE #(
    parameter INIT = 1'b0
)(
    input  wire C,
    input  wire CE,
    input  wire CLR,
    input  wire D,
    output reg  Q
);
    initial Q = INIT;
    always @(posedge C or posedge CLR) begin
        if (CLR)
            Q <= 1'b0;
        else if (CE)
            Q <= D;
    end
endmodule

module tb_kp_ripple_counter;
    localparam integer WIDTH = 4;
    localparam integer MODULO = (1 << WIDTH);

    reg clk = 1'b0;
    reg clear = 1'b1;
    wire [WIDTH-1:0] q;
    wire presc_q;

    kp_ripple_counter #(.WIDTH(WIDTH)) dut (
        .clk(clk), .clear(clear), .q(q), .presc_q(presc_q)
    );

    integer failures = 0;
    integer edges = 0;
    integer seed = 1;

    function integer expected_q(input integer n);
        begin
            expected_q = (n / 2) % MODULO;
        end
    endfunction

    task automatic pulse;
        begin
            clk = 1'b0; #5;
            clk = 1'b1; #5;
            clk = 1'b0; #5;
            edges = edges + 1;
            if (q !== expected_q(edges)) begin
                failures = failures + 1;
                $display("FAIL seq edges=%0d got=%0d exp=%0d", edges, q, expected_q(edges));
            end
        end
    endtask

    task automatic do_clear;
        begin
            clear = 1'b1; #5;
            clear = 1'b0; #5;
            edges = 0;
            if (q !== 0) begin
                failures = failures + 1;
                $display("FAIL clear: q=%0d expected 0", q);
            end
        end
    endtask

    task automatic check_q(input [WIDTH-1:0] want, input string label);
        begin
            if (q !== want) begin
                failures = failures + 1;
                $display("FAIL %0s got=%0d exp=%0d", label, q, want);
            end else begin
                $display("PASS %0s q=%0d", label, q);
            end
        end
    endtask

    integer i, count;

    initial begin
        clear = 1'b1;
        #20;
        check_q(0, "reset_while_ro_off");

        // Independent truth table (no implementation formula): N -> q
        do_clear();
        check_q(0, "tt_N0_eq_0");
        pulse(); check_q(0, "tt_N1_eq_0");
        pulse(); check_q(1, "tt_N2_eq_1");
        pulse(); check_q(1, "tt_N3_eq_1");
        pulse(); check_q(2, "tt_N4_eq_2");

        do_clear();
        for (i = 0; i < 20; i = i + 1)
            pulse();
        check_q(expected_q(20), "seq_20_edges");

        do_clear();
        repeat (7) pulse();
        check_q(expected_q(7), "seven_edges");
        do_clear();
        check_q(0, "clear_mid_state");

        do_clear();
        repeat (MODULO * 2) pulse();
        check_q(expected_q(MODULO * 2), "wrap_exact_2x_2^W");
        do_clear();
        repeat (MODULO * 2 + 1) pulse();
        check_q(expected_q(MODULO * 2 + 1), "wrap_plus_one");
        do_clear();
        repeat (MODULO - 1) pulse();
        check_q(expected_q(MODULO - 1), "pre_wrap_max");

        for (i = 0; i < 30; i = i + 1) begin
            count = $urandom(seed) % 13;
            do_clear();
            repeat (count) pulse();
            check_q(expected_q(count), "random_burst");
        end

        do_clear();
        repeat (5) pulse();
        clear = 1'b1; #3;
        check_q(0, "async_clear_during_count");
        clear = 1'b0; #3;
        edges = 0;
        repeat (3) pulse();
        check_q(expected_q(3), "restart_after_clear");

        clear = 1'b1; #10;
        check_q(0, "clear_with_no_edges");
        clear = 1'b0;

        if (failures) begin
            $fatal(1, "%0d ripple counter checks failed", failures);
        end
        $display("ALL RIPPLE COUNTER TESTS PASSED (q = floor(N_edges/2) mod 2^%0d)", WIDTH);
        $finish;
    end
endmodule
