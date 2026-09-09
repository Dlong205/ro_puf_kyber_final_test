`timescale 1ns / 1ps
`default_nettype none

module tb_edge_kem_scrub_controller;
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst_n = 0, zeroize = 0, launch_req = 0, core_done = 0;
    wire ready, busy, done, scrub_done, core_reset, core_start, scrub_en;
    wire [10:0] scrub_addr;
    int scrub_cycles = 0, starts = 0;

    edge_kem_scrub_controller #(.SCRUB_LAST_ADDR(7)) dut (
        .clk(clk), .rst_n(rst_n), .zeroize(zeroize),
        .launch_req(launch_req), .core_done(core_done), .ready(ready),
        .busy(busy), .done(done), .scrub_done(scrub_done),
        .core_reset(core_reset), .core_start(core_start),
        .scrub_en(scrub_en), .scrub_addr(scrub_addr)
    );

    always @(posedge clk) begin
        if (scrub_en) begin
            if (scrub_addr !== scrub_cycles[10:0])
                $fatal(1, "scrub address got=%0d expected=%0d", scrub_addr, scrub_cycles);
            scrub_cycles <= scrub_cycles + 1;
        end
        if (core_start) starts <= starts + 1;
    end

    task automatic check(input string name, input logic condition);
        if (!condition) $fatal(1, "FAIL: %s", name);
        $display("PASS: %s", name);
    endtask

    initial begin
        repeat (4) @(negedge clk);
        rst_n = 1;
        #1;
        check("idle after reset", ready && !busy && !core_reset);

        launch_req = 1;
        @(negedge clk); launch_req = 0;
        check("launch enters reset", busy && core_reset && !core_start);
        while (!core_start) begin
            @(negedge clk);
            check("core held reset during scrub", !scrub_en || core_reset);
        end
        check("all scrub addresses written before start", scrub_cycles == 8);
        @(negedge clk);
        check("core_start is one cycle", !core_start && starts == 1);
        core_done = 1;
        @(negedge clk); core_done = 0;
        check("transaction done pulse", done);
        @(negedge clk);
        check("returns idle", ready && !done);

        // Abort a live KEM. Address counter restarts and no core start/done
        // may escape the zeroize path.
        scrub_cycles = 0;
        launch_req = 1;
        @(negedge clk); launch_req = 0;
        while (!core_start) @(negedge clk);
        @(negedge clk);
        zeroize = 1;
        launch_req = 1; // held request must be consumed/ignored by abort
        @(negedge clk); zeroize = 0;
        scrub_cycles = 0;
        while (!scrub_done) begin
            @(negedge clk);
            check("zeroize never launches KEM", !core_start);
        end
        check("zeroize covers entire address space", scrub_cycles == 8);
        check("abort has no transaction done", !done && starts == 2);
        @(negedge clk);
        repeat (3) @(negedge clk);
        check("held launch cannot restart after scrub", ready && starts == 2);
        launch_req = 0;
        @(negedge clk);

        $display("EDGE_KEM_SCRUB_CONTROLLER_PASS");
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "timeout");
    end
endmodule

`default_nettype wire
