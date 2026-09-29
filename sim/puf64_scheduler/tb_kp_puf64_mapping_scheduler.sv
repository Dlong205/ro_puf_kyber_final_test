`timescale 1ns / 1ps
`default_nettype none

// I3 scheduler tests with a synthetic count provider at the measurement
// boundary (no RO ring simulation).  Golden vector: for canonical pair (a,b)
// counts are c0 = 1000 + 7a + b, c1 = c0 + (+1 if (a+b) even else -1), so the
// expected response bit for destination j is ((a_j + b_j) % 2 == 0).
module tb_kp_puf64_mapping_scheduler;
    `include "puf64_mapping_data.vh"

    // Synthetic-count golden for the ACTIVE mapping generation. The include
    // dir selects the generation (frozen V2 default); the golden hex must
    // match it. Overridable via +define+PUF64_GOLDEN_HEX=<64 hex digits>.
    //   legacy d501 (rtl/top): f845ac8a...1599 (stale, never use for E2E)
    //   frozen V2 gen1 81b5:  572f0e71187ce4ab968955d4ea4e97cb15b1b9b89b2619b48de1864b6b076056d8
    //   mapping G2 0x005d:    5d7cb7b01df33622c70229f326ea0e6cc50f601a4ea4d19ed194afe5a32f6056d8
`ifndef PUF64_GOLDEN_HEX
    localparam [263:0] GOLDEN_PACKED = 264'h572f0e71187ce4ab968955d4ea4e97cb15b1b9b89b2619b48de1864b6b076056d8;
`else
    localparam [263:0] GOLDEN_PACKED = 264'h`PUF64_GOLDEN_HEX;
`endif

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

    // I4.2a: back-to-back telemetry (1-cycle spacing, no idle gap) over a
    // closed index window.  Exercises the commit bubble and the 2-deep event
    // FIFO, including a selected commit immediately followed by new arrivals.
    task automatic emit_burst(input integer lo, input integer hi);
        integer k, aa, bb;
        reg [31:0] v0, v1;
        begin
            for (k = lo; k <= hi; k = k + 1) begin
                aa = canon_a(k); bb = canon_b(k);
                v0 = 1000 + 7 * aa + bb;
                v1 = v0 + ((((aa + bb) % 2) == 0) ? 1 : -1);
                @(negedge clk);
                tel_valid = 1'b1; tel_index = k[10:0];
                tel_a = aa[5:0]; tel_b = bb[5:0];
                tel_c0 = v0; tel_c1 = v1;
                tel_stable = 1'b1; tel_timeout = 1'b0;
                tel_ovf_a = 1'b0; tel_ovf_b = 1'b0; mmcm_locked = 1'b1;
            end
            @(negedge clk); tel_valid = 1'b0;
        end
    endtask

    // Full clean sweep with a back-to-back burst window [burst_lo, burst_hi].
    task automatic run_sweep_burst(input integer burst_lo, input integer burst_hi);
        integer k, aa, bb;
        reg [31:0] v0, v1;
        begin
            k = 0;
            while (k < 2016) begin
                if (k == burst_lo) begin
                    emit_burst(burst_lo, burst_hi);
                    k = burst_hi + 1;
                end else begin
                    aa = canon_a(k); bb = canon_b(k);
                    v0 = 1000 + 7 * aa + bb;
                    v1 = v0 + ((((aa + bb) % 2) == 0) ? 1 : -1);
                    emit_pair(k, v0, v1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1);
                    k = k + 1;
                end
            end
            @(negedge clk); sweep_done = 1'b1;
            @(negedge clk); sweep_done = 1'b0;
        end
    endtask

    function automatic bit is_selected(input integer idx);
        integer j;
        begin
            is_selected = 1'b0;
            for (j = 0; j < 264; j = j + 1)
                if (puf64_map_sorted_full(j) == idx[10:0])
                    is_selected = 1'b1;
        end
    endfunction

    // I4.2a: consume handshake with negedge-only driving.  ready is held
    // across exactly one sampling posedge and cleared at the next negedge,
    // so the DUT never races the testbench in the sampling slot.
    task automatic consume_response;
        begin
            @(negedge clk); ready = 1'b1;
            @(negedge clk); ready = 1'b0;
            wait_idle(10);
            if (mapped_valid || busy)
                $fatal(1, "consume handshake did not return to idle");
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
        // Reset while valid is stalled by ready=0 must erase both the public
        // output and the internal partial-response bitmap.
        @(negedge clk); rst_n = 1'b0;
        repeat (2) @(posedge clk);
        if (mapped_valid || mapped_response !== 264'd0 ||
            dut.response_r !== 264'd0 || busy)
            $fatal(1, "reset while valid/!ready did not erase scheduler state");
        @(negedge clk); rst_n = 1'b1;
        repeat (2) @(posedge clk);
        do_start();
        run_sweep(-1, 0, -1);
        wait_valid(4000);
        if (!mapped_valid || mapped_response !== GOLDEN_PACKED)
            $fatal(1, "clean rerun after valid/ready reset failed");
        consume_response();
        if (mapped_response !== 264'd0)
            $fatal(1, "response buffer not zeroized after consume");
        $display("SCHED_CLEAN_GOLDEN_OK");
        $display("SCHED_RESET_VALID_BACKPRESSURE_OK");

        // 2. Single selected tie -> correctable (BCH t=8): valid response,
        // tied destination forced to 0, sweep completes.
        begin
            integer tie_canon, tie_dest;
            reg tie_golden;
            tie_canon = puf64_map_sorted_full(3);
            tie_dest = puf64_map_sorted_dest(3);
            tie_golden = (((puf64_map_pair_a(tie_dest) + puf64_map_pair_b(tie_dest)) % 2) == 0);
            do_start();
            run_sweep(tie_canon, 1, -1);
            wait_valid(4000);
            if (!mapped_valid || mapped_error)
                $fatal(1, "single selected tie was not absorbed as correctable");
            if (selected_count != 9'd264)
                $fatal(1, "single-tie selected_count=%0d", selected_count);
            if (mapped_response[tie_dest] !== 1'b0)
                $fatal(1, "tied dest bit not forced 0");
            if (tie_golden) begin
                if (mapped_response === GOLDEN_PACKED)
                    $fatal(1, "tied-1 response unexpectedly golden");
            end
            consume_response();
        end
        $display("SCHED_SELECTED_TIE_CORRECTABLE");

        // 2b. Two selected ties -> still correctable.
        begin
            integer t0, t1;
            t0 = puf64_map_sorted_full(3);
            t1 = puf64_map_sorted_full(7);
            do_start();
            for (i = 0; i < 2016; i = i + 1) begin
                a = canon_a(i); b = canon_b(i);
                c0 = 1000 + 7 * a + b;
                c1 = c0 + ((((a + b) % 2) == 0) ? 1 : -1);
                if (i == t0 || i == t1) c1 = c0;
                emit_pair(i, c0, c1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1);
            end
            @(negedge clk); sweep_done = 1'b1;
            @(negedge clk); sweep_done = 1'b0;
            wait_valid(4000);
            if (!mapped_valid || mapped_error)
                $fatal(1, "double selected tie was not absorbed");
            if (selected_count != 9'd264)
                $fatal(1, "double-tie selected_count=%0d", selected_count);
            consume_response();
        end
        $display("SCHED_DOUBLE_TIE_CORRECTABLE");

        // 2c. Three selected ties -> fail-closed (cap=2).
        begin
            integer t0, t1, t2;
            t0 = puf64_map_sorted_full(3);
            t1 = puf64_map_sorted_full(7);
            t2 = puf64_map_sorted_full(11);
            do_start();
            for (i = 0; i < 2016; i = i + 1) begin
                a = canon_a(i); b = canon_b(i);
                c0 = 1000 + 7 * a + b;
                c1 = c0 + ((((a + b) % 2) == 0) ? 1 : -1);
                if (i == t0 || i == t1 || i == t2) c1 = c0;
                emit_pair(i, c0, c1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1);
            end
            @(negedge clk); sweep_done = 1'b1;
            @(negedge clk); sweep_done = 1'b0;
            wait_valid(4000);
            if (mapped_valid || !mapped_error)
                $fatal(1, "triple selected tie was not rejected at cap");
            do_start();
            @(negedge clk);
        end
        $display("SCHED_TRIPLE_TIE_REJECTED");

        // 3. Unselected tie -> ignored, response still golden.
        do_start();
        run_sweep(0, 1, -1);
        wait_valid(4000);
        if (!mapped_valid || mapped_error || mapped_response !== GOLDEN_PACKED)
            $fatal(1, "unselected tie corrupted the mapped response");
        consume_response();
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
        consume_response();
        if (mapped_response !== 264'd0)
            $fatal(1, "response buffer not zeroized after consume");
        $display("SCHED_RESET_MID_SWEEP_OK");

        // 10. I4.2a: mapped_valid must not assert mid-sweep (pipeline must
        // not present a partial response); the sweep still completes golden.
        do_start();
        for (i = 0; i < 2016; i = i + 1) begin
            a = canon_a(i); b = canon_b(i);
            c0 = 1000 + 7 * a + b;
            c1 = c0 + ((((a + b) % 2) == 0) ? 1 : -1);
            emit_pair(i, c0, c1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1);
            if (i == 500) begin
                @(posedge clk); #1;
                if (mapped_valid || mapped_error)
                    $fatal(1, "response valid/error asserted mid-sweep valid=%b err=%b state=%d sel=%d ev_idx=%d look=%d ev_ok=%b bubble=%b ev2v=%b done_seen=%b",
                        mapped_valid, mapped_error, dut.state, dut.sel_ptr,
                        dut.ev_index, dut.lookup_full_r, dut.ev_ok,
                        dut.bubble_r, dut.ev2_valid, dut.sweep_done_seen);
                if (!busy)
                    $fatal(1, "busy dropped mid-sweep");
            end
        end
        @(negedge clk); sweep_done = 1'b1;
        @(negedge clk); sweep_done = 1'b0;
        wait_valid(4000);
        if (!mapped_valid || mapped_error || mapped_response !== GOLDEN_PACKED)
            $fatal(1, "mid-sweep-checked sweep did not complete golden");
        consume_response();
        $display("SCHED_NO_EARLY_VALID_OK");

        // 11. I4.2a: back-to-back burst across the first selected entry.
        begin
            integer f0, blo, bhi;
            f0 = puf64_map_sorted_full(0);
            blo = (f0 >= 2) ? f0 - 2 : 0;
            bhi = f0 + 2;
            do_start();
            run_sweep_burst(blo, bhi);
            wait_valid(4000);
            if (!mapped_valid || mapped_error || mapped_response !== GOLDEN_PACKED)
                $fatal(1, "back-to-back burst corrupted the mapped response");
            if (selected_count != 9'd264)
                $fatal(1, "burst sweep selected_count=%0d", selected_count);
            consume_response();
            if (mapped_response !== 264'd0)
                $fatal(1, "burst sweep response not zeroized after consume");
        end
        $display("SCHED_BACK2BACK_BURST_OK");

        // 12. I4.2a: sweep_done coincident with the last telemetry event.
        do_start();
        for (i = 0; i < 2015; i = i + 1) begin
            a = canon_a(i); b = canon_b(i);
            c0 = 1000 + 7 * a + b;
            c1 = c0 + ((((a + b) % 2) == 0) ? 1 : -1);
            emit_pair(i, c0, c1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1);
        end
        a = canon_a(2015); b = canon_b(2015);
        c0 = 1000 + 7 * a + b;
        c1 = c0 + ((((a + b) % 2) == 0) ? 1 : -1);
        @(negedge clk);
        tel_valid = 1'b1; tel_index = 11'd2015;
        tel_a = a[5:0]; tel_b = b[5:0];
        tel_c0 = c0; tel_c1 = c1;
        tel_stable = 1'b1; tel_timeout = 1'b0;
        tel_ovf_a = 1'b0; tel_ovf_b = 1'b0; mmcm_locked = 1'b1;
        sweep_done = 1'b1;
        @(posedge clk); #1;
        @(negedge clk); tel_valid = 1'b0; sweep_done = 1'b0;
        wait_valid(4000);
        if (!mapped_valid || mapped_error || mapped_response !== GOLDEN_PACKED)
            $fatal(1, "coincident last-event/sweep_done dropped the final bit");
        if (selected_count != 9'd264)
            $fatal(1, "coincident done selected_count=%0d", selected_count);
        consume_response();
        $display("SCHED_COINCIDENT_DONE_OK");

        // 13. I4.2a: reset while pipeline events are in flight.
        do_start();
        emit_burst(10, 12);
        @(negedge clk); rst_n = 1'b0;
        repeat (2) @(posedge clk);
        if (mapped_valid || mapped_error || busy ||
            mapped_response !== 264'd0 || dut.response_r !== 264'd0 ||
            dut.sel_ptr !== 9'd0 || dut.selected_count !== 9'd0)
            $fatal(1, "reset with pending pipeline did not erase state");
        @(negedge clk); rst_n = 1'b1;
        repeat (2) @(posedge clk);
        do_start();
        run_sweep(-1, 0, -1);
        wait_valid(4000);
        if (!mapped_valid || mapped_error || mapped_response !== GOLDEN_PACKED)
            $fatal(1, "post-pending-reset clean sweep failed");
        consume_response();
        $display("SCHED_RESET_WHILE_PENDING_OK");

        // 14. I4.2a: zeroize while pipeline events are in flight.
        do_start();
        emit_burst(20, 22);
        @(negedge clk); zeroize = 1'b1;
        repeat (2) @(posedge clk);
        @(negedge clk); zeroize = 1'b0;
        if (mapped_valid || mapped_error || busy ||
            mapped_response !== 264'd0 || dut.response_r !== 264'd0)
            $fatal(1, "zeroize with pending pipeline did not erase state");
        repeat (2) @(posedge clk);
        do_start();
        run_sweep(-1, 0, -1);
        wait_valid(4000);
        if (!mapped_valid || mapped_error || mapped_response !== GOLDEN_PACKED)
            $fatal(1, "post-pending-zeroize clean sweep failed");
        consume_response();
        $display("SCHED_ZEROIZE_WHILE_PENDING_OK");

        // 15. I4.2a: hardware fault on the very last canonical pair.
        do_start();
        run_sweep(2015, 2, -1);
        wait_valid(4000);
        if (mapped_valid || !mapped_error)
            $fatal(1, "last-pair timeout was not rejected at drain");
        do_start();
        @(negedge clk);
        $display("SCHED_LAST_PAIR_FAULT_REJECTED");

        // 16. Selected tie on the last selected entry (drain edge) ->
        // correctable: last bit forced 0, sweep still completes.
        begin
            integer last_canon, last_dest;
            last_canon = puf64_map_sorted_full(263);
            last_dest = puf64_map_sorted_dest(263);
            do_start();
            run_sweep(last_canon, 1, -1);
            wait_valid(4000);
            if (!mapped_valid || mapped_error)
                $fatal(1, "last-entry tie was not absorbed");
            if (selected_count != 9'd264)
                $fatal(1, "last-tie selected_count=%0d", selected_count);
            if (mapped_response[last_dest] !== 1'b0)
                $fatal(1, "last tied dest bit not forced 0");
            consume_response();
        end
        $display("SCHED_SELECTED_TIE_LAST_CORRECTABLE");

        // 17. I4.2a: tie on the last unselected pair is ignored (golden).
        begin
            integer tail_unsel;
            tail_unsel = -1;
            for (i = 2015; i >= 0 && tail_unsel == -1; i = i - 1)
                if (!is_selected(i))
                    tail_unsel = i;
            if (tail_unsel == -1)
                $fatal(1, "no unselected pair found");
            do_start();
            run_sweep(tail_unsel, 1, -1);
            wait_valid(4000);
            if (!mapped_valid || mapped_error || mapped_response !== GOLDEN_PACKED)
                $fatal(1, "trailing unselected tie corrupted the response");
            consume_response();
        end
        $display("SCHED_TRAILING_UNSELECTED_TIE_OK");

        $display("PUF64_MAPPING_SCHEDULER_PASS");
        $finish;
    end

    initial begin
        repeat (4000000) @(posedge clk);
        $fatal(1, "scheduler tb timeout");
    end
endmodule

`default_nettype wire
