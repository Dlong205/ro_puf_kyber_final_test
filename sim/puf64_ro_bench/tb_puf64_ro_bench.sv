`timescale 1ns / 1ps

module tb_puf64_ro_bench;
    parameter integer NUM_RO = 8;
    parameter integer PAIR_COUNT = NUM_RO * (NUM_RO - 1) / 2;
    parameter integer RO_BITS = (NUM_RO <= 1) ? 1 : $clog2(NUM_RO);
    parameter integer IDX_W = (PAIR_COUNT <= 1) ? 1 : $clog2(PAIR_COUNT);

    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0;
    reg start = 1'b0;

    wire busy, done;
    wire [PAIR_COUNT-1:0] response;
    wire tel_valid, tel_stable, tel_timeout;
    wire [IDX_W-1:0] tel_index;
    wire [RO_BITS-1:0] tel_a, tel_b;
    wire [31:0] tel_c0, tel_c1;
    wire tel_winner;

    puf64_ro_bench #(
        .NUM_RO(NUM_RO), .WIDTH(16), .REF_CYCLES(64),
        .CLEAR_CYCLES(8), .SETTLE_CYCLES(8)
    ) dut (
        .clk(clk), .rst_n(rst_n), .zeroize(1'b0), .start(start),
        .busy(busy), .done(done), .response(response),
        .telemetry_valid(tel_valid), .telemetry_stable(tel_stable),
        .telemetry_timeout(tel_timeout), .telemetry_index(tel_index),
        .telemetry_pair_a(tel_a), .telemetry_pair_b(tel_b),
        .telemetry_count0(tel_c0), .telemetry_count1(tel_c1),
        .telemetry_winner(tel_winner)
    );

    integer failures = 0;
    integer records = 0;
    integer exp_a = 0, exp_b = 1;
    bit seen [0:NUM_RO-1][0:NUM_RO-1];
    integer i, j;
    integer en_weight;
    integer timeout_cycles;

    // ro_en enable-weight monitor (0 in idle, 2 during a measurement).
    always @(posedge clk) begin
        en_weight = 0;
        for (i = 0; i < NUM_RO; i = i + 1)
            en_weight = en_weight + dut.ro_en_i[i];
        if (rst_n && en_weight != 0 && en_weight != 2) begin
            failures = failures + 1;
            $display("FAIL ro_en weight=%0d at %0t", en_weight, $time);
        end
    end

    task automatic check_record;
        begin
            if (tel_index != records) begin
                failures = failures + 1;
                $display("FAIL index exp=%0d got=%0d", records, tel_index);
            end
            if (tel_a != exp_a || tel_b != exp_b) begin
                failures = failures + 1;
                $display("FAIL pair exp=(%0d,%0d) got=(%0d,%0d)",
                         exp_a, exp_b, tel_a, tel_b);
            end
            if (tel_a >= tel_b) begin
                failures = failures + 1;
                $display("FAIL non-canonical pair (%0d,%0d)", tel_a, tel_b);
            end
            if (seen[tel_a][tel_b]) begin
                failures = failures + 1;
                $display("FAIL duplicate pair (%0d,%0d)", tel_a, tel_b);
            end
            seen[tel_a][tel_b] = 1'b1;
            if (tel_c0 == 0 || tel_c1 == 0) begin
                failures = failures + 1;
                $display("FAIL zero count pair (%0d,%0d) c0=%0d c1=%0d",
                         tel_a, tel_b, tel_c0, tel_c1);
            end
            if (!tel_stable) begin
                failures = failures + 1;
                $display("FAIL unstable pair (%0d,%0d)", tel_a, tel_b);
            end
            records = records + 1;
            if (exp_b == NUM_RO - 1) begin
                exp_a = exp_a + 1;
                exp_b = exp_a + 1;
            end else begin
                exp_b = exp_b + 1;
            end
        end
    endtask

    initial begin
        for (i = 0; i < NUM_RO; i = i + 1)
            for (j = 0; j < NUM_RO; j = j + 1)
                seen[i][j] = 1'b0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);

        // reset mid-idle must hold counters clear
        @(posedge clk); start = 1'b1;
        @(posedge clk); start = 1'b0;

        timeout_cycles = 0;
        while (!done && timeout_cycles < 20 * PAIR_COUNT * 200) begin
            @(posedge clk); #1;
            if (tel_valid)
                check_record();
            timeout_cycles = timeout_cycles + 1;
        end
        if (done !== 1'b1) begin
            failures = failures + 1;
            $display("FAIL campaign did not finish");
        end
        if (records != PAIR_COUNT) begin
            failures = failures + 1;
            $display("FAIL records exp=%0d got=%0d", PAIR_COUNT, records);
        end

        // reset while measuring: enable must return to 0 and no false records
        @(posedge clk); start = 1'b1; @(posedge clk); start = 1'b0;
        repeat (20) @(posedge clk);
        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        if (en_weight != 0) begin
            failures = failures + 1;
            $display("FAIL reset did not disable ROs en_weight=%0d", en_weight);
        end
        rst_n = 1'b1;
        repeat (3) @(posedge clk);

        if (failures) begin
            $fatal(1, "%0d bench checks failed (NUM_RO=%0d)", failures, NUM_RO);
        end
        $display("ALL PUF64 RO BENCH TESTS PASSED (NUM_RO=%0d pairs=%0d)",
                 NUM_RO, PAIR_COUNT);
        $finish;
    end

    initial begin
        #50000000;
        $fatal(1, "bench TB timeout");
    end
endmodule
