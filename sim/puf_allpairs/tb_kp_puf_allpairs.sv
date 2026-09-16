`timescale 1ns/1ps

module tb_kp_puf_allpairs;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic zeroize = 1'b0;
    logic start = 1'b0;
    logic busy, done;
    logic [495:0] response;
    logic telemetry_valid;
    logic [8:0] telemetry_index;
    logic [4:0] telemetry_pair_a, telemetry_pair_b;
    logic [31:0] telemetry_count0, telemetry_count1;
    logic telemetry_winner;

    integer failures = 0;
    integer records;
    integer expected_a, expected_b;
    integer timeout_cycles;
    bit seen [0:31][0:31];

    always #5 clk = ~clk;

    kp_puf_allpairs_top #(
        .REF_CYCLES(8), .RESET_CYCLES(8), .SETTLE_CYCLES(2)
    ) dut (
        .clk(clk), .rst_n(rst_n), .zeroize(zeroize), .start(start),
        .busy(busy), .done(done), .response(response),
        .telemetry_valid(telemetry_valid),
        .telemetry_index(telemetry_index),
        .telemetry_pair_a(telemetry_pair_a),
        .telemetry_pair_b(telemetry_pair_b),
        .telemetry_count0(telemetry_count0),
        .telemetry_count1(telemetry_count1),
        .telemetry_winner(telemetry_winner)
    );

    task automatic check(input string label, input bit condition);
        if (condition)
            $display("PASS: %s", label);
        else begin
            failures++;
            $display("FAIL: %s", label);
        end
    endtask

    task automatic check_quiet(input string label, input bit condition);
        if (!condition) begin
            failures++;
            $display("FAIL: %s at record %0d", label, records);
        end
    endtask

    task automatic clear_scoreboard;
        integer a, b;
        begin
            records = 0;
            expected_a = 0;
            expected_b = 1;
            for (a = 0; a < 32; a++)
                for (b = 0; b < 32; b++)
                    seen[a][b] = 1'b0;
        end
    endtask

    task automatic check_record;
        begin
            check_quiet("telemetry index is sequential", telemetry_index == records);
            check_quiet("pair_a follows lexicographic schedule", telemetry_pair_a == expected_a);
            check_quiet("pair_b follows lexicographic schedule", telemetry_pair_b == expected_b);
            check_quiet("pair is canonical", telemetry_pair_a < telemetry_pair_b);
            check_quiet("pair was not emitted twice", !seen[telemetry_pair_a][telemetry_pair_b]);
            seen[telemetry_pair_a][telemetry_pair_b] = 1'b1;
            records++;
            if (expected_b == 31) begin
                expected_a++;
                expected_b = expected_a + 1;
            end else begin
                expected_b++;
            end
        end
    endtask

    task automatic run_campaign;
        begin
            clear_scoreboard();
            @(posedge clk); start <= 1'b1;
            @(posedge clk); start <= 1'b0;
            timeout_cycles = 0;
            while (!done && timeout_cycles < 30000) begin
                @(posedge clk); #1;
                if (telemetry_valid)
                    check_record();
                timeout_cycles++;
            end
            check("all-pairs campaign completed", done);
            check("exactly 496 records emitted", records == 496);
            check("schedule ended after pair (30,31)",
                  expected_a == 31 && expected_b == 32);
            @(posedge clk); #1;
            check("done is a one-cycle pulse", !done);
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        rst_n <= 1'b1;
        repeat (3) @(posedge clk);
        run_campaign();

        @(negedge clk); zeroize <= 1'b1;
        @(negedge clk); #1;
        check("zeroize clears busy", !busy);
        check("zeroize clears done", !done);
        check("zeroize clears response", response == '0);
        zeroize <= 1'b0;
        repeat (3) @(posedge clk);
        run_campaign();
        check("scheduler restarts after zeroize", records == 496);

        if (failures)
            $fatal(1, "%0d all-pairs checks failed", failures);
        $display("ALL 496-PAIR SCHEDULER TESTS PASSED");
        $finish;
    end
endmodule
