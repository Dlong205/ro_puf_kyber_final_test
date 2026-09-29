`timescale 1ns / 1ps
`default_nettype none

// R1 counter equivalence: v1 (bare `~` assigns) vs v2 (explicit LUT1).
// WIDTH=5 -> overflow at 2^6=64 clk edges; stimulus covers toggle, mid-count
// clear, overflow wrap, post-wrap counting and a second clear.  q/overflow/
// presc_q must agree on every edge.
module tb_ripple_v1v2;
    reg clk = 1'b0;
    always #1 clk = ~clk;
    reg clear = 1'b1;

    wire [4:0] q1, q2;
    wire ovf1, ovf2, pq1, pq2;

    kp_ripple_counter #(.WIDTH(5)) v1 (
        .clk(clk), .clear(clear), .q(q1), .overflow(ovf1), .presc_q(pq1)
    );
    kp_ripple_counter_v2 #(.WIDTH(5)) v2 (
        .clk(clk), .clear(clear), .q(q2), .overflow(ovf2), .presc_q(pq2)
    );

    integer edges = 0;
    integer failures = 0;
    reg saw_ovf = 1'b0;

    task automatic check;
        begin
            if (ovf1) saw_ovf = 1'b1;
            if (q1 !== q2 || ovf1 !== ovf2 || pq1 !== pq2) begin
                $display("MISMATCH edge=%0d q=%h/%h ovf=%b/%b pq=%b/%b",
                         edges, q1, q2, ovf1, ovf2, pq1, pq2);
                failures = failures + 1;
            end
        end
    endtask

    initial begin
        repeat (4) @(posedge clk);
        clear = 1'b0;
        // Run 200 edges: covers prescaler, counting, overflow at edge 64
        // (count = floor(edges/2) mod 32, overflow iff floor(edges/2) >= 32).
        repeat (200) begin
            @(posedge clk); #0; edges = edges + 1;
            if (edges == 10) clear = 1'b1;
            if (edges == 12) clear = 1'b0;
            check();
        end
        if (!saw_ovf)
            $fatal(1, "overflow never asserted (edges=%0d)", edges);
        // Second clear mid-count, then 100 more edges incl. second wrap.
        @(negedge clk); clear = 1'b1;
        repeat (2) @(posedge clk);
        @(negedge clk); clear = 1'b0;
        if (q1 !== 5'd0 || q2 !== 5'd0 || ovf1 !== 1'b0 || ovf2 !== 1'b0)
            $fatal(1, "clear did not reset both counters");
        repeat (150) begin
            @(posedge clk); #0; edges = edges + 1;
            check();
        end
        if (failures != 0)
            $fatal(1, "%0d edge mismatches", failures);
        $display("RIPPLE_V1V2_EQUIVALENT edges=%0d", edges);
        $display("R1_RIPPLE_EQUIVALENCE_PASS");
        $finish;
    end

    initial begin
        repeat (100000) @(posedge clk);
        $fatal(1, "ripple tb timeout");
    end
endmodule

`default_nettype wire
