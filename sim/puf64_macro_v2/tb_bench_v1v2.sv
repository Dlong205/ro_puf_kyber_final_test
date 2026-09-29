`timescale 1ns / 1ps
`default_nettype none

// R1 sweep equivalence: puf64_ro_bench (v1) vs puf64_ro_bench_v2, 64 ROs,
// behavioral RO models, identical stimulus.  Every telemetry field, busy,
// done timing and the final 2016-bit response must agree cycle-by-cycle.
module tb_bench_v1v2;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0;
    reg zeroize = 1'b0;
    reg start = 1'b0;

    wire busy1, done1, busy2, done2;
    wire [2015:0] resp1, resp2;
    wire tv1, ts1, tt1, toa1, tob1, tw1;
    wire tv2, ts2, tt2, toa2, tob2, tw2;
    wire [10:0] ti1, ti2;
    wire [5:0] ta1, tb1, ta2, tb2;
    wire [31:0] tc01, tc11, tc02, tc12;

    puf64_ro_bench #(.NUM_RO(64)) v1 (
        .clk(clk), .rst_n(rst_n), .zeroize(zeroize), .start(start),
        .busy(busy1), .done(done1), .response(resp1),
        .telemetry_valid(tv1), .telemetry_stable(ts1),
        .telemetry_timeout(tt1), .telemetry_overflow_a(toa1),
        .telemetry_overflow_b(tob1), .telemetry_index(ti1),
        .telemetry_pair_a(ta1), .telemetry_pair_b(tb1),
        .telemetry_count0(tc01), .telemetry_count1(tc11),
        .telemetry_winner(tw1)
    );
    puf64_ro_bench_v2 #(.NUM_RO(64)) v2 (
        .clk(clk), .rst_n(rst_n), .zeroize(zeroize), .start(start),
        .busy(busy2), .done(done2), .response(resp2),
        .telemetry_valid(tv2), .telemetry_stable(ts2),
        .telemetry_timeout(tt2), .telemetry_overflow_a(toa2),
        .telemetry_overflow_b(tob2), .telemetry_index(ti2),
        .telemetry_pair_a(ta2), .telemetry_pair_b(tb2),
        .telemetry_count0(tc02), .telemetry_count1(tc12),
        .telemetry_winner(tw2)
    );

    integer failures = 0;
    integer cycles = 0;

    always @(posedge clk) begin
        cycles = cycles + 1;
        if (rst_n) begin
            if (busy1 !== busy2 || done1 !== done2 ||
                tv1 !== tv2 || ts1 !== ts2 || tt1 !== tt2 ||
                toa1 !== toa2 || tob1 !== tob2 || tw1 !== tw2 ||
                ti1 !== ti2 || ta1 !== ta2 || tb1 !== tb2 ||
                tc01 !== tc02 || tc11 !== tc12 || resp1 !== resp2) begin
                $display("MISMATCH cycle=%0d", cycles);
                failures = failures + 1;
                if (failures > 10) $fatal(1, "too many mismatches");
            end
        end
    end

    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);
        @(negedge clk); start = 1'b1;
        @(negedge clk); start = 1'b0;
        wait (done1 && done2);
        if (resp1 !== resp2)
            $fatal(1, "final response mismatch");
        repeat (4) @(posedge clk);
        if (failures != 0)
            $fatal(1, "%0d cycle mismatches", failures);
        $display("BENCH_V1V2_EQUIVALENT cycles=%0d", cycles);
        $display("R1_BENCH_EQUIVALENCE_PASS");
        $finish;
    end

    initial begin
        repeat (6000000) @(posedge clk);
        $fatal(1, "bench tb timeout");
    end
endmodule

`default_nettype wire
