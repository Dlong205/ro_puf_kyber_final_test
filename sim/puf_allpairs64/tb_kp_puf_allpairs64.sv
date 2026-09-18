`timescale 1ns/1ps

module tb_kp_puf_allpairs64;
    localparam integer NUM_RO = 64;
    localparam integer PAIR_COUNT = NUM_RO * (NUM_RO - 1) / 2;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic zeroize = 1'b0;
    logic start = 1'b0;
    logic busy, done;
    logic [PAIR_COUNT-1:0] response;
    logic telemetry_valid;
    logic [10:0] telemetry_index;
    logic [5:0] telemetry_pair_a, telemetry_pair_b;
    logic [31:0] telemetry_count0, telemetry_count1;
    logic telemetry_winner;

    integer failures = 0;
    integer records;
    integer expected_a, expected_b;
    integer timeout_cycles;
    bit seen [0:63][0:63];
    bit ro_oscillated [0:63];

    always #5 clk = ~clk;

    kp_puf_allpairs_top #(
        .NUM_RO(NUM_RO), .PAIR_COUNT(PAIR_COUNT),
        .REF_CYCLES(128), .RESET_CYCLES(8), .SETTLE_CYCLES(2)
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
            for (a = 0; a < NUM_RO; a++)
                for (b = 0; b < NUM_RO; b++)
                    seen[a][b] = 1'b0;
            for (a = 0; a < NUM_RO; a++)
                ro_oscillated[a] = 1'b0;
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
            check_quiet("measured ROs actually oscillated",
                        (telemetry_count0 != 0) || (telemetry_count1 != 0));
            if (telemetry_count0 != 0)
                ro_oscillated[telemetry_pair_a] = 1'b1;
            if (telemetry_count1 != 0)
                ro_oscillated[telemetry_pair_b] = 1'b1;
            records++;
            if (expected_b == NUM_RO - 1) begin
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
            while (!done && timeout_cycles < 1000000) begin
                @(posedge clk); #1;
                if (telemetry_valid) begin
                    check_record();
                end
                timeout_cycles++;
            end
            check("all-pairs campaign completed", done);
            check("exactly 2016 records emitted", records == 2016);
            check("schedule ended after pair (62,63)",
                  expected_a == 63 && expected_b == 64);
            begin
                integer r;
                bit all_ro_ran;
                all_ro_ran = 1'b1;
                for (r = 0; r < NUM_RO; r++)
                    if (!ro_oscillated[r]) begin
                        all_ro_ran = 1'b0;
                        $display("RO %0d never oscillated", r);
                    end
                check("every one of the 64 ROs oscillated at least once",
                      all_ro_ran);
            end
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
        check("scheduler restarts after zeroize", records == 2016);

        if (failures)
            $fatal(1, "%0d all-pairs64 checks failed", failures);
        $display("ALL 2016-PAIR SCHEDULER TESTS PASSED");
        $finish;
    end
endmodule