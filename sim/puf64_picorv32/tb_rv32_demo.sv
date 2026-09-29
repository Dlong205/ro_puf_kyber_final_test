`timescale 1ns/1ps

module tb_rv32_demo;
    reg clk = 0;
    reg rst_n = 0;
    reg transport_start = 0;
    reg transport_zeroize = 0;
    reg command_ok = 0;
    reg trusted_kcv_valid = 0;
    reg mmcm_locked = 0;
    reg core_busy = 0;
    wire authorized_start;
    wire cpu_ready;
    wire cpu_trap;
    wire request_pending;

    always #5 clk = ~clk;

    puf64_picorv32_supervisor #(
        .FIRMWARE_HEX("../../firmware/rv32_demo.hex")
    ) dut (
        .clk(clk), .rst_n(rst_n), .transport_start(transport_start),
        .transport_zeroize(transport_zeroize), .command_ok(command_ok),
        .trusted_kcv_valid(trusted_kcv_valid), .mmcm_locked(mmcm_locked),
        .core_busy(core_busy), .authorized_start(authorized_start),
        .cpu_ready(cpu_ready), .cpu_trap(cpu_trap),
        .request_pending(request_pending)
    );

    task automatic pulse_request;
        begin
            @(negedge clk);
            transport_start = 1;
            @(negedge clk);
            transport_start = 0;
        end
    endtask

    integer cycles;
    integer launches;
    always @(posedge clk)
        if (authorized_start)
            launches <= launches + 1;

    initial begin
        launches = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;

        cycles = 0;
        while (!cpu_ready && cycles < 50000) begin
            @(posedge clk);
            cycles = cycles + 1;
        end
        if (!cpu_ready || cpu_trap)
            $fatal(1, "PicoRV32 firmware did not reach ready state");

        // A parsed request remains pending but cannot launch without all
        // hardware trust predicates.
        command_ok = 1;
        mmcm_locked = 1;
        pulse_request();
        repeat (100) @(posedge clk);
        if (!request_pending || launches != 0)
            $fatal(1, "request did not fail closed with invalid anchor");

        trusted_kcv_valid = 1;
        cycles = 0;
        while (launches != 1 && cycles < 50000) begin
            @(posedge clk);
            cycles = cycles + 1;
        end
        if (launches != 1 || request_pending || cpu_trap)
            $fatal(1, "trusted request was not authorized exactly once");

        // Busy core blocks the next request until it is idle.
        core_busy = 1;
        pulse_request();
        repeat (100) @(posedge clk);
        if (!request_pending || launches != 1)
            $fatal(1, "busy-core request was not held");
        core_busy = 0;
        cycles = 0;
        while (launches != 2 && cycles < 50000) begin
            @(posedge clk);
            cycles = cycles + 1;
        end
        if (launches != 2)
            $fatal(1, "held request was not authorized after idle");

        // Transport zeroize must remove any unconsumed authorization.
        trusted_kcv_valid = 0;
        pulse_request();
        repeat (20) @(posedge clk);
        transport_zeroize = 1;
        @(posedge clk);
        transport_zeroize = 0;
        repeat (20) @(posedge clk);
        if (request_pending || launches != 2)
            $fatal(1, "zeroize did not clear pending request");

        $display("RV32_DEMO_PASS launches=%0d", launches);
        $finish;
    end
endmodule
