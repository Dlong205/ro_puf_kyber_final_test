`timescale 1ns / 1ps

module tb_reset_sync;
    reg clk;
    reg arst_n;
    wire srst_n;

    always #5 clk = ~clk;

    reset_sync_n dut (
        .clk_i(clk),
        .arst_ni(arst_n),
        .srst_no(srst_n)
    );

    initial begin
        clk = 1'b0;
        arst_n = 1'b0;

        repeat (2) @(posedge clk);
        #1;
        if (srst_n !== 1'b0)
            $fatal(1, "reset output was not asserted");

        @(negedge clk);
        arst_n = 1'b1;
        @(posedge clk);
        #1;
        if (srst_n !== 1'b0)
            $fatal(1, "reset released before two synchronizer edges");
        @(posedge clk);
        #1;
        if (srst_n !== 1'b1)
            $fatal(1, "reset did not release on the second edge");

        // Assert between clock edges and require immediate propagation.
        #2;
        arst_n = 1'b0;
        #1;
        if (srst_n !== 1'b0)
            $fatal(1, "asynchronous reset assertion was delayed");

        @(negedge clk);
        arst_n = 1'b1;
        repeat (2) @(posedge clk);
        #1;
        if (srst_n !== 1'b1)
            $fatal(1, "second reset release failed");

        $display("*** ASIC RESET SYNCHRONIZER PASS ***");
        $finish;
    end
endmodule
