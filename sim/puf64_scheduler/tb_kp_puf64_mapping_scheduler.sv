`timescale 1ns / 1ps
`default_nettype none

// I3 scheduler tests with a synthetic count provider at the measurement
// boundary (no RO ring simulation).  Golden vector: for canonical pair (a,b)
// counts are c0 = 1000 + 7a + b, c1 = c0 + (+1 if (a+b) even else -1), so the
// expected response bit for destination j is ((a_j + b_j) % 2 == 0).
module tb_kp_puf64_mapping_scheduler;
    `include "puf64_mapping_data.vh"

    localparam [263:0] GOLDEN_PACKED = 264'hf845ac8a3c394faa22a6056910575142570bff1c60bdfde0cc4402e56a78011599;

    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0;
    reg zeroize = 1'b0;
    reg start = 1'b0;

    reg         tel_valid = 1'b0;
    reg  [10:0] tel_index = 11'd0;
    reg  [5:0]  tel_a = 6'd0;
    reg  [5:0]  tel_b = 6'd0;
    reg  [31:0] tel_c0 = 32'd0;
    reg  [31:0] tel_c1 = 32'd0;
    reg         tel_stable = 1'b1;
    reg         tel_timeout = 1'b0;
    reg         tel_ovf_a = 1'b0;
    reg         tel_ovf_b = 1'b0;
    reg         mmcm_locked = 1'b1;
    reg         sweep_done = 1'b0;

    wire [263:0] mapped_response;
    wire         mapped_valid;
    wire         mapped_error;
    wire         busy;
    wire [8:0]   selected_count;
    reg          ready = 1'b0;

    kp_puf64_mapping_scheduler dut (
        .clk(clk), .rst_n(rst_n), .zeroize(zeroize), .start(start),
        .tel_valid(tel_valid), .tel_index(tel_index),
        .tel_pair_a(tel_a), .tel_pair_b(tel_b),
        .tel_count0(tel_c0), .tel_count1(tel_c1),
        .tel_stable(tel_stable), .tel_timeout(tel_timeout),
        .tel_ovf_a(tel_ovf_a), .tel_ovf_b(tel_ovf_b),
        .mmcm_locked(mmcm_locked), .sweep_done(sweep_done),
        .mapped_response(mapped_response),
        .mapped_response_valid(mapped_valid),
        .mapped_response_ready(ready),
        .mapped_response_error(mapped_error),
        .busy(busy), .selected_count(selected_count)
    );

    reg [263:0] expected_bits;
    integer failures = 0;
    integer i, a, b;
    integer guard;
    reg [31:0] c0, c1;

    function automatic [5:0] canon_a(input integer idx);
        integer ii, aa;
        begin
            ii = idx; aa = 0;
            while (ii >= 64 - 1 - aa) begin
                ii = ii - (64 - 1 - aa);
                aa = aa + 1;
            end
            canon_a = aa & 6'h3F;
        end
    endfunction

    function automatic [5:0] canon_b(input integer idx);
        integer ii, aa;
        begin
            ii = idx; aa = 0;
            while (ii >= 64 - 1 - aa) begin
                ii = ii - (64 - 1 - aa);
                aa = aa + 1;
            end
            canon_b = (aa + 1 + ii) & 6'h3F;
        end
    endfunction

    task automatic do_start;
        begin
            @(negedge clk); start = 1'b1;
            @(negedge clk); start = 1'b0;
        end
    endtask

    task automatic emit_pair(input integer idx, input [31:0] v0, input [31:0] v1,
                             input bit stable, input bit timeout,
                             input bit ovf_a, input bit ovf_b, input bit locked);
        begin
            @(negedge clk);
            tel_valid = 1'b1; tel_index = idx[10:0];
            tel_a = canon_a(idx); tel_b = canon_b(idx);
            tel_c0 = v0; tel_c1 = v1;
            tel_stable = stable; tel_timeout = timeout;
            tel_ovf_a = ovf_a; tel_ovf_b = ovf_b; mmcm_locked = locked;
            @(posedge clk); #1;
            @(negedge clk); tel_valid = 1'b0;
            tel_stable = 1'b1; tel_timeout = 1'b0;
            tel_ovf_a = 1'b0; tel_ovf_b = 1'b0; mmcm_locked = 1'b1;
        end
    endtask

    // fault_kind: 0 none, 1 tie, 2 timeout, 3 ovf_a, 4 ovf_b, 5 zero, 6 mmcm
    task automatic run_sweep(input integer fault_idx, input integer fault_kind,
                             input integer skip_idx);
        begin
            for (i = 0; i < 2016; i = i + 1) begin
                a = canon_a(i); b = canon_b(i);
                c0 = 1000 + 7 * a + b;
                c1 = c0 + ((((a + b) % 2) == 0) ? 1 : -1);
                if (i == fault_idx) begin
                    case (fault_kind)
                        1: c1 = c0;
                        2: begin
                            @(negedge clk);
                            tel_valid = 1'b1; tel_index = i[10:0];
                            tel_a = a[5:0]; tel_b = b[5:0];
                            tel_c0 = c0; tel_c1 = c1;
                            tel_stable = 1'b0; tel_timeout = 1'b1;
                            @(posedge clk); #1;
                            @(negedge clk);
                            tel_valid = 1'b0; tel_timeout = 1'b0;
                            continue;
                        end
                        3: begin
                            @(negedge clk);
                            tel_valid = 1'b1; tel_index = i[10:0];
                            tel_a = a[5:0]; tel_b = b[5:0];
                            tel_c0 = c0; tel_c1 = c1;
                            tel_ovf_a = 1'b1;
                            @(posedge clk); #1;
                            @(negedge clk);
                            tel_valid = 1'b0; tel_ovf_a = 1'b0;
                            continue;
                        end
                        4: begin
                            @(negedge clk);
                            tel_valid = 1'b1; tel_index = i[10:0];
                            tel_a = a[5:0]; tel_b = b[5:0];
                            tel_c0 = c0; tel_c1 = c1;
                            tel_ovf_b = 1'b1;
                            @(posedge clk); #1;
                            @(negedge clk);
                            tel_valid = 1'b0; tel_ovf_b = 1'b0;
                            continue;
                        end
                        5: c1 = 32'd0;
                        6: begin
                            @(negedge clk);
                            tel_valid = 1'b1; tel_index = i[10:0];
                            tel_a = a[5:0]; tel_b = b[5:0];
                            tel_c0 = c0; tel_c1 = c1;
                            mmcm_locked = 1'b0;
                            @(posedge clk); #1;
                            @(negedge clk);
                            tel_valid = 1'b0; mmcm_locked = 1'b1;
                            continue;
                        end
                        default: ;
                    endcase
                end
                if (i != skip_idx)
                    emit_pair(i, c0, c1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1);
            end
            @(negedge clk); sweep_done = 1'b1;
            @(negedge clk); sweep_done = 1'b0;
        end
    endtask

    task automatic wait_valid(input integer limit);
        begin
            guard = 0;
            while (!mapped_valid && guard < limit) begin
                @(posedge clk);
                guard = guard + 1;
            end
        end
    endtask

    task automatic wait_idle(input integer limit);
        begin
            guard = 0;
            while (busy && guard < limit) begin
                @(posedge clk);
                guard = guard + 1;
            end
        end
    endtask

    task automatic expect_fail(input integer fault_idx, input integer kind,
                               input [127:0] label);
        begin
            do_start();
            run_sweep(fault_idx, kind, -1);
            wait_valid(4000);
            if (mapped_valid || !mapped_error)
                $fatal(1, "%0s: expected sticky error without valid response", label);
            if (selected_count == 9'd264)
                $fatal(1, "%0s: selected_count reached 264 on fault", label);
            failures = failures; // keep lint quiet
            do_start();
            @(negedge clk);
        end
    endtask

    initial begin
        for (i = 0; i < 264; i = i + 1)
            expected_bits[i] = (((puf64_map_pair_a(i) + puf64_map_pair_b(i)) % 2) == 0);

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // 1. Clean sweep + golden packed vector + backpressure.
        do_start();
        run_sweep(-1, 0, -1);
        wait_valid(4000);
        if (!mapped_valid || mapped_error)
            $fatal(1, "clean sweep did not produce a valid response");
        if (selected_count != 9'd264)
            $fatal(1, "selected_count=%0d", selected_count);
        if (mapped_response !== expected_bits)
            $fatal(1, "mapped response does not match the generated pairs");
        if (mapped_response !== GOLDEN_PACKED)
            $fatal(1, "packed 33-byte golden vector mismatch");
        for (i = 0; i < 20; i = i + 1) begin
            @(posedge clk);
            if (!mapped_valid || mapped_response !== GOLDEN_PACKED)
                $fatal(1, "response not held stable under backpressure");
        end
        ready = 1'b1;
        @(posedge clk); ready = 1'b0;
        wait_idle(10);
        if (mapped_response !== 264'd0)
            $fatal(1, "response buffer not zeroized after consume");
        $display("SCHED_CLEAN_GOLDEN_OK");

        // 2. Selected tie -> fail-closed.
        expect_fail(puf64_map_sorted_full(0), 1, "selected tie");
        $display("SCHED_SELECTED_TIE_REJECTED");

        // 3. Unselected tie -> ignored, response still golden.
        do_start();
        run_sweep(0, 1, -1);
        wait_valid(4000);
        if (!mapped_valid || mapped_error || mapped_response !== GOLDEN_PACKED)
            $fatal(1, "unselected tie corrupted the mapped response");
        ready = 1'b1; @(posedge clk); ready = 1'b0; wait_idle(10);
        $display("SCHED_UNSELECTED_TIE_OK");

        // 4-7. Hardware faults on any pair -> fail-closed.
        expect_fail(100, 2, "timeout");
        $display("SCHED_TIMEOUT_REJECTED");
        expect_fail(100, 3, "overflow_a");
        $display("SCHED_OVF_A_REJECTED");
        expect_fail(100, 4, "overflow_b");
        $display("SCHED_OVF_B_REJECTED");
        expect_fail(100, 5, "count_zero");
        $display("SCHED_ZERO_REJECTED");
        expect_fail(100, 6, "mmcm");
        $display("SCHED_MMCM_REJECTED");

        // 8. Missing selected entry -> error at sweep end.
        do_start();
        run_sweep(-1, 0, puf64_map_sorted_full(0));
        wait_valid(4000);
        if (mapped_valid || !mapped_error)
            $fatal(1, "missing selected entry was not rejected");
        do_start();
        @(negedge clk);
        $display("SCHED_MISSING_ENTRY_REJECTED");

        // 9. Reset mid-sweep: no valid, no error latch, clean re-run works.
        do_start();
        for (i = 0; i < 50; i = i + 1)
            emit_pair(i, 1000 + i, 1001 + i, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1);
        @(negedge clk); rst_n = 1'b0;
        repeat (3) @(posedge clk);
        if (mapped_valid || mapped_error || busy)
            $fatal(1, "reset mid-sweep did not clear the scheduler");
        rst_n = 1'b1;
        repeat (2) @(posedge clk);
        do_start();
        run_sweep(-1, 0, -1);
        wait_valid(4000);
        if (!mapped_valid || mapped_error || mapped_response !== GOLDEN_PACKED)
            $fatal(1, "post-reset clean sweep failed");
        @(negedge clk); ready = 1'b1; @(posedge clk); ready = 1'b0;
        $display("SCHED_RESET_MID_SWEEP_OK");

        $display("PUF64_MAPPING_SCHEDULER_PASS");
        $finish;
    end

    initial begin
        repeat (4000000) @(posedge clk);
        $fatal(1, "scheduler tb timeout");
    end
endmodule

`default_nettype wire
