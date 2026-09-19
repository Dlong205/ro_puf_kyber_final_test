`timescale 1ns / 1ps

// Injected-status regression for the production puf64_ro_bench FSM.  The leaf
// RO/counter cells are replaced by status_stubs.sv (selected at compile time
// with -DTB_SCENARIO_*) so every terminal-record status bit can be exercised:
//   stable, forced-timeout-with-plausible-count, count-zero, overflow.
// The FSM, pair schedule and capture pipeline are the unmodified production RTL.
module tb_puf64_ro_bench_status;
    localparam integer NUM_RO = 4;
    localparam integer PAIR_COUNT = NUM_RO * (NUM_RO - 1) / 2;
    localparam integer RO_BITS = 2;
    localparam integer IDX_W = 3;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst_n = 1'b0;
    reg start = 1'b0;

    wire busy, done;
    wire [PAIR_COUNT-1:0] response;
    wire tel_valid, tel_stable, tel_timeout;
    wire tel_ovf_a, tel_ovf_b;
    wire [IDX_W-1:0] tel_index;
    wire [RO_BITS-1:0] tel_a, tel_b;
    wire [31:0] tel_c0, tel_c1;
    wire tel_winner;

    puf64_ro_bench #(
        .NUM_RO(NUM_RO), .WIDTH(16), .REF_CYCLES(16),
        .CLEAR_CYCLES(4), .SETTLE_CYCLES(4), .CAPTURE_TIMEOUT(64)
    ) dut (
        .clk(clk), .rst_n(rst_n), .zeroize(1'b0), .start(start),
        .busy(busy), .done(done), .response(response),
        .telemetry_valid(tel_valid),
        .telemetry_stable(tel_stable),
        .telemetry_timeout(tel_timeout),
        .telemetry_overflow_a(tel_ovf_a),
        .telemetry_overflow_b(tel_ovf_b),
        .telemetry_index(tel_index),
        .telemetry_pair_a(tel_a), .telemetry_pair_b(tel_b),
        .telemetry_count0(tel_c0), .telemetry_count1(tel_c1),
        .telemetry_winner(tel_winner)
    );

    integer failures = 0;
    integer records = 0;
    integer events_per_index [0:PAIR_COUNT-1];
    integer i;
    integer exp_a = 0, exp_b = 1;
    integer timeout_cycles;

    task automatic fail(input string message);
        begin
            failures = failures + 1;
            $display("FAIL %0s", message);
        end
    endtask

    // Checks every terminal record against the scenario-specific status truth.
    task automatic check_record;
        begin
            if (tel_index >= PAIR_COUNT || events_per_index[tel_index] != 0)
                fail($sformatf("duplicate/out-of-range terminal event index=%0d",
                               tel_index));
            else
                events_per_index[tel_index] = events_per_index[tel_index] + 1;

            if (tel_index != records)
                fail($sformatf("index exp=%0d got=%0d", records, tel_index));
            if (tel_a != exp_a || tel_b != exp_b)
                fail($sformatf("pair exp=(%0d,%0d) got=(%0d,%0d)",
                               exp_a, exp_b, tel_a, tel_b));
            if (tel_a >= tel_b)
                fail($sformatf("non-canonical pair (%0d,%0d)", tel_a, tel_b));

`ifdef TB_SCENARIO_TIMEOUT
            if (tel_stable || !tel_timeout)
                fail($sformatf("timeout status stable=%0b timeout=%0b",
                               tel_stable, tel_timeout));
            if (tel_c0 == 0 || tel_c1 == 0)
                fail("timeout record lost its plausible nonzero count");
            if (tel_ovf_a || tel_ovf_b)
                fail("timeout record raised overflow");
`elsif TB_SCENARIO_ZERO
            if (!tel_stable || tel_timeout)
                fail($sformatf("zero status stable=%0b timeout=%0b",
                               tel_stable, tel_timeout));
            if (tel_c0 != 0 || tel_c1 != 0)
                fail("count-zero scenario produced nonzero counts");
`elsif TB_SCENARIO_OVERFLOW
            if (!tel_stable || tel_timeout)
                fail("overflow scenario is not a stable capture");
            if (!tel_ovf_a || !tel_ovf_b)
                fail($sformatf("overflow not captured a=%0b b=%0b",
                               tel_ovf_a, tel_ovf_b));
`else
            if (!tel_stable || tel_timeout)
                fail($sformatf("stable status stable=%0b timeout=%0b",
                               tel_stable, tel_timeout));
            if (tel_c0 == 0 || tel_c1 == 0)
                fail("stable scenario produced a zero count");
            if (tel_ovf_a || tel_ovf_b)
                fail("stable scenario raised overflow");
`endif

            records = records + 1;
            if (exp_b == NUM_RO - 1) begin
                exp_a = exp_a + 1;
                exp_b = exp_a + 1;
            end else begin
                exp_b = exp_b + 1;
            end
        end
    endtask

    task automatic run_campaign(input string label);
        begin
            records = 0;
            exp_a = 0;
            exp_b = 1;
            for (i = 0; i < PAIR_COUNT; i = i + 1)
                events_per_index[i] = 0;
            @(posedge clk); start = 1'b1;
            @(posedge clk); start = 1'b0;
            timeout_cycles = 0;
            while (!done && timeout_cycles < 40 * PAIR_COUNT * 200) begin
                @(posedge clk); #1;
                if (tel_valid)
                    check_record();
                timeout_cycles = timeout_cycles + 1;
            end
            if (done !== 1'b1)
                fail($sformatf("%0s campaign did not finish", label));
            if (records != PAIR_COUNT)
                fail($sformatf("%0s records exp=%0d got=%0d",
                               label, PAIR_COUNT, records));
            for (i = 0; i < PAIR_COUNT; i = i + 1)
                if (events_per_index[i] != 1)
                    fail($sformatf("%0s index %0d terminal events=%0d",
                                   label, i, events_per_index[i]));
            repeat (4) @(posedge clk);
        end
    endtask

    initial begin
        for (i = 0; i < PAIR_COUNT; i = i + 1)
            events_per_index[i] = 0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);

        // Campaign 1: full pair sweep, exactly one terminal record per pair.
        run_campaign("first");

        // RUN must clear the previous buffer/status and re-emit 2016-equivalent
        // records from index 0 (here PAIR_COUNT records).
        run_campaign("second");

        // Reset in the middle of a measurement must not emit a terminal record
        // and must release every RO enable.
        @(posedge clk); start = 1'b1;
        @(posedge clk); start = 1'b0;
        repeat (3) @(posedge clk);
        if (tel_valid)
            fail("terminal record asserted during active measurement");
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        if (dut.ro_en_i != '0)
            fail("reset did not release RO enables mid-measure");
        if (tel_valid)
            fail("terminal record asserted while reset");

        // Clean restart after reset.
        rst_n = 1'b1;
        repeat (2) @(posedge clk);
        run_campaign("post-reset");

        if (failures) begin
            $fatal(1, "%0d injected-status bench checks failed", failures);
        end
`ifdef TB_SCENARIO_TIMEOUT
        $display("PASS INJECTED STATUS timeout w/ plausible count (NUM_RO=%0d)", NUM_RO);
`elsif TB_SCENARIO_ZERO
        $display("PASS INJECTED STATUS count_zero_a/b (NUM_RO=%0d)", NUM_RO);
`elsif TB_SCENARIO_OVERFLOW
        $display("PASS INJECTED STATUS overflow_a/b (NUM_RO=%0d)", NUM_RO);
`else
        $display("PASS INJECTED STATUS stable + terminal-event uniqueness (NUM_RO=%0d)",
                 NUM_RO);
`endif
        $finish;
    end

    initial begin
        #200000000;
        $fatal(1, "injected-status TB timeout");
    end
endmodule
