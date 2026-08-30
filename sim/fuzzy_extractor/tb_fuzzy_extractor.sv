`timescale 1ns / 1ps

module tb_fuzzy_extractor;

    logic                    clk;
    logic                    rst_n;
    logic                    start;
    logic                    mode;
    logic [263:0]            response_in;
    logic [263:0]            helper_in;
    logic [263:0]            helper_out;
    logic [191:0]            key_out;
    logic                    busy;
    logic                    done;
    logic                    success;

    fuzzy_extractor #(
        .T(8),
        .DATA_BITS(192),
        .N(264),
        .BITS(8)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .start       (start),
        .mode        (mode),
        .response_in (response_in),
        .helper_in   (helper_in),
        .helper_out  (helper_out),
        .key_out     (key_out),
        .busy        (busy),
        .done        (done),
        .success     (success)
    );

    logic [263:0] R0;
    logic [263:0] H;
    logic [191:0] KEY0;
    int failures;
    int tests;

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    initial begin
        repeat (200000) @(posedge clk);
        $fatal(1, "Fuzzy-extractor simulation timeout");
    end

    logic [3:0] prev_state;
    always @(posedge clk) begin
        if (dut.state !== prev_state) begin
            $display("t=%0t state=%0d (prev=%0d)", $time, dut.state, prev_state);
            prev_state = dut.state;
        end
        if (($time % 200000) == 0)
            $display("t=%0t heartbeat", $time);
    end

    task wait_done;
        begin
            while (!done) @(posedge clk);
            @(posedge clk);
        end
    endtask

    task run_op(input logic m, input logic [263:0] resp, input logic [263:0] hlp);
        begin
            @(posedge clk);
            mode        = m;
            response_in = resp;
            helper_in   = hlp;
            start       = 1'b1;
            @(posedge clk);
            start       = 1'b0;
            wait_done();
        end
    endtask

    task check(input string name, input logic cond);
        begin
            tests = tests + 1;
            if (cond)
                $display("PASS: %s", name);
            else begin
                failures = failures + 1;
                $display("FAIL: %s", name);
            end
        end
    endtask

    function automatic [263:0] flipn(input [263:0] v, input int base, input int n);
        begin
            for (int i = 0; i < n; i = i + 1)
                v[base + i] = ~v[base + i];
            flipn = v;
        end
    endfunction

    initial begin
        failures = 0;
        tests    = 0;
        rst_n    = 0;
        start    = 0;
        mode     = 0;
        response_in = '0;
        helper_in   = '0;

        R0 = {8'hAB, 8'hCD, 8'hEF, 8'h01, 8'h23, 8'h45, 8'h67, 8'h89,
              8'h9A, 8'hBC, 8'hDE, 8'hF0, 8'h12, 8'h34, 8'h56, 8'h78,
              8'h9A, 8'hBC, 8'hDE, 8'hF0, 8'h13, 8'h57, 8'h9B, 8'hDF,
              8'h24, 8'h68, 8'hAC, 8'hE0, 8'h35, 8'h79, 8'hBD, 8'hF1,
              8'h46};

        repeat (3) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        $display("--- enroll ---");
        run_op(0, R0, '0);
        KEY0 = R0[263:72];
        H    = helper_out;
        check("enroll: key_out == response data part", key_out == KEY0);
        check("enroll: helper data part is zero (systematic)", H[263:72] == '0);
        check("enroll: helper ecc part non-trivial", H[71:0] != '0);
        check("enroll: success asserted", success == 1'b1);

        $display("--- reconstruct clean ---");
        run_op(1, R0, H);
        check("recon clean: key matches", key_out == KEY0);
        check("recon clean: success", success == 1'b1);

        $display("--- reconstruct 1 error ---");
        run_op(1, flipn(R0, 100, 1), H);
        check("recon 1err: key matches", key_out == KEY0);
        check("recon 1err: success", success == 1'b1);

        $display("--- reconstruct 8 errors (t) ---");
        run_op(1, flipn(R0, 4, 8), H);
        check("recon 8err: key matches", key_out == KEY0);
        check("recon 8err: success", success == 1'b1);

        $display("--- reconstruct 12 errors (> t) ---");
        run_op(1, flipn(R0, 8, 12), H);
        check("recon 12err: success == 0", success == 1'b0);

        $display("--- enroll determinism ---");
        run_op(0, R0, '0);
        check("enroll: helper deterministic", helper_out == H);

        if (failures == 0) begin
            $display("ALL %0d TESTS PASSED", tests);
            $finish;
        end else begin
            $display("%0d/%0d TESTS FAILED", failures, tests);
            $fatal(1, "Fuzzy-extractor regression failed");
        end
    end

endmodule
