`timescale 1ns / 1ps

module tb_kp_puf_simple (
    input wire clk
);

    localparam int BIT_COUNT = 16;
    localparam int TIMEOUT_CYCLES = 2000;

    logic rst_n;
    logic start;
    logic [7:0] seed;
    logic busy;
    logic done;
    logic [BIT_COUNT-1:0] response;
    logic [BIT_COUNT-1:0] response_a;
    logic [BIT_COUNT-1:0] response_b;
    integer failures;

    kp_puf_top #(
        .BIT_COUNT(BIT_COUNT),
        .REF_CYCLES(8),
        .RESET_CYCLES(8),
        .SETTLE_CYCLES(2)
    ) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (start),
        .seed     (seed),
        .busy     (busy),
        .done     (done),
        .response (response)
    );

    task automatic check(input string name, input logic condition);
        begin
            if (condition)
                $display("PASS: %s", name);
            else begin
                failures = failures + 1;
                $display("FAIL: %s", name);
            end
        end
    endtask

    task automatic run_puf(input logic [7:0] run_seed,
                           output logic [BIT_COUNT-1:0] run_response);
        integer cycles;
        logic saw_busy;
        begin
            seed = run_seed;
            @(posedge clk);
            start = 1'b1;
            @(posedge clk);
            start = 1'b0;

            cycles = 0;
            saw_busy = 1'b0;
            while (!done && cycles < TIMEOUT_CYCLES) begin
                @(posedge clk);
                if (busy) saw_busy = 1'b1;
                cycles = cycles + 1;
            end
            check("PUF asserts busy", saw_busy);
            check("PUF completes before timeout", done);
            run_response = response;
            @(posedge clk);
            check("done is a one-cycle pulse", !done);
        end
    endtask

    initial begin
        failures = 0;
        rst_n = 1'b0;
        start = 1'b0;
        seed = 8'h00;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        run_puf(8'hA5, response_a);
        run_puf(8'hA5, response_b);
        check("same seed is deterministic in the digital RO model",
              response_a == response_b);

        seed = 8'h3C;
        @(posedge clk);
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;
        repeat (6) @(posedge clk);
        rst_n = 1'b0;
        repeat (2) @(posedge clk);
        check("mid-operation reset clears busy", !busy);
        check("mid-operation reset clears done", !done);
        check("mid-operation reset clears response", response == '0);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);
        run_puf(8'hA5, response_b);
        check("PUF restarts cleanly after reset", response_b == response_a);

        if (failures != 0)
            $fatal(1, "%0d PUF TESTS FAILED", failures);

        $display("ALL PUF TESTS PASSED");
        $finish;
    end

endmodule
