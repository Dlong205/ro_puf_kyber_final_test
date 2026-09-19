`timescale 1ns / 1ps
`default_nettype none

// I3A end-to-end: physical boundary test model + real BCH FE + real KCV gate
// + real scheduler.  The physical model emits the canonical 0..2015 sweep
// with counts derived from a TB-provided 264-bit response; no RO ring is
// simulated.  Enrollment, trusted-anchor provisioning, reconstruction, noise,
// parser/anchor fail-early, scheduler faults and reset are exercised.
module tb_edge_puf64_operational_core;
    `include "puf64_mapping_data.vh"
    localparam integer PAIR_COUNT = 2016;

    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0;
    reg zeroize = 1'b0;
    reg start = 1'b0;
    reg enroll = 1'b0;
    reg command_ok = 1'b1;
    reg [263:0] helper_in = 264'd0;
    reg mmcm_locked = 1'b1;
    reg trusted_valid = 1'b0;
    reg [223:0] trusted_ref = 224'd0;
    reg helper_kcv_valid = 1'b0;
    reg [223:0] helper_kcv_ref = 224'd0;
    reg [55:0] kcv_ctx = 56'h010101010101;
    reg [55:0] enroll_ctx = 56'h010101010101;
    reg downstream_done = 1'b0;

    wire [263:0] helper_out;
    wire fe_success, kcv_pass, kcv_fail;
    wire [223:0] fe_kcv;
    wire [7:0] bch_corr_bits;
    wire mapped_error, early_reject, busy, done;
    wire [8:0] selected_count;
    wire downstream_start;
    wire [191:0] downstream_key_internal;

    // Test-model controls (read by kp_puf64_physical below).
    reg [263:0] src_r = 264'd0;
    integer fault_index = -1;
    integer fault_kind = 0;

    edge_puf64_operational_core #(
        .ALLOW_ENROLL(1'b1)
    ) dut (
        .clk(clk), .rst_n(rst_n), .zeroize(zeroize), .start(start),
        .enroll(enroll), .command_ok(command_ok), .helper_in(helper_in),
        .helper_out(helper_out), .fe_success(fe_success),
        .mmcm_locked(mmcm_locked), .trusted_kcv_valid(trusted_valid),
        .trusted_kcv_ref(trusted_ref), .helper_kcv_ref(helper_kcv_ref),
        .helper_kcv_valid(helper_kcv_valid), .kcv_ctx(kcv_ctx),
        .enroll_ctx(enroll_ctx), .kcv_pass(kcv_pass), .fe_kcv(fe_kcv),
        .kcv_fail(kcv_fail), .bch_corr_bits(bch_corr_bits),
        .downstream_key_internal(downstream_key_internal),
        .downstream_start(downstream_start), .downstream_done(downstream_done),
        .mapped_error(mapped_error), .early_reject(early_reject),
        .busy(busy), .done(done), .selected_count(selected_count)
    );

    integer downstream_seen = 0;
    integer downstream_pulses = 0;
    integer physical_starts = 0;
    integer downstream_delay = 1;
    integer downstream_countdown = 0;
    reg downstream_start_d = 1'b0;
    always @(posedge clk) begin
        downstream_start_d <= downstream_start;
        if (downstream_start) begin
            downstream_seen = 1;
            downstream_pulses = downstream_pulses + 1;
            downstream_countdown = downstream_delay;
        end
        if (downstream_start && downstream_start_d)
            $fatal(1, "downstream_start lasted more than one cycle");
        if (dut.puf_start_r)
            physical_starts = physical_starts + 1;
    end

    always @(posedge clk) begin
        downstream_done <= 1'b0;
        if (downstream_countdown > 0) begin
            downstream_countdown = downstream_countdown - 1;
            if (downstream_countdown == 0)
                downstream_done <= 1'b1;
        end
    end

    integer cycles;
    task automatic pulse_start(input bit en);
        begin
            while (busy || done) @(posedge clk);
            @(negedge clk);
            enroll = en; downstream_seen = 0; downstream_pulses = 0;
            physical_starts = 0;
            if (fault_kind == 6) mmcm_locked = 1'b0;
            start = 1'b1;
            @(negedge clk); start = 1'b0;
            cycles = 0;
            while (!done && cycles < 200000) begin
                @(posedge clk);
                cycles = cycles + 1;
            end
            if (!done) begin
                $display("TIMEOUT t=%0t state=%0d enroll=%0b cmd=%0b anch=%0b sched=%0d mvalid=%0b merr=%0b",
                         $time, dut.state, enroll, command_ok, trusted_valid,
                         dut.u_puf64_scheduler.state, dut.mapped_valid, dut.mapped_error);
                $fatal(1, "operational transaction timed out");
            end
            #1;
            if (dut.mapped_latched !== 264'd0 ||
                downstream_key_internal !== 192'd0)
                $fatal(1, "done was exposed before mapped/key erase");
            mmcm_locked = 1'b1;
        end
    endtask

    task automatic reset_in_state(input [3:0] target_state,
                                  input [127:0] label);
        integer guard;
        begin
            while (busy || done) @(posedge clk);
            @(negedge clk); enroll = 1'b0; start = 1'b1;
            @(negedge clk); start = 1'b0;
            guard = 0;
            while (dut.state != target_state && guard < 200000) begin
                @(posedge clk);
                guard = guard + 1;
            end
            if (dut.state != target_state)
                $fatal(1, "%0s: target state not reached", label);
            @(negedge clk); rst_n = 1'b0; downstream_countdown = 0;
            repeat (3) @(posedge clk);
            #1;
            if (busy || downstream_start || dut.mapped_latched !== 264'd0 ||
                downstream_key_internal !== 192'd0 ||
                dut.u_puf64_scheduler.response_r !== 264'd0 ||
                dut.mapped_response !== 264'd0)
                $fatal(1, "%0s: reset did not erase secret state", label);
            @(negedge clk); rst_n = 1'b1;
            repeat (3) @(posedge clk);
        end
    endtask

    reg [263:0] R0 = {33{8'hA5}};
    reg [263:0] R1 = {33{8'h5A}};
    reg [263:0] mask;
    reg [263:0] helper0, helper1;
    reg [223:0] kcv0, kcv1;
    integer n, i;
    integer starts_before_busy_retry;

    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);

        // Enrollment 0/1: mapped response -> FE helper + public KCV.
        src_r = R0; fault_index = -1; fault_kind = 0;
        pulse_start(1'b1);
        if (!fe_success) $fatal(1, "enroll0 FE failed");
        helper0 = helper_out; kcv0 = fe_kcv;
        src_r = R1;
        pulse_start(1'b1);
        if (!fe_success) $fatal(1, "enroll1 FE failed");
        helper1 = helper_out; kcv1 = fe_kcv;
        if (kcv0 === kcv1) $fatal(1, "distinct roots produced identical KCV");

        trusted_valid = 1'b1; trusted_ref = kcv0;
        helper_kcv_valid = 1'b1; helper_kcv_ref = kcv0;
        helper_in = helper0;

        // Clean reconstruct with the trusted anchor.
        src_r = R0;
        pulse_start(1'b0);
        if (!fe_success || !kcv_pass || mapped_error)
            $fatal(1, "clean reconstruct did not pass");
        if (downstream_seen != 1)
            $fatal(1, "clean reconstruct did not start downstream");
        if (downstream_pulses != 1)
            $fatal(1, "clean reconstruct downstream pulse count=%0d",
                   downstream_pulses);
        $display("I3A_CLEAN_RECONSTRUCT_OK");

        // Noise 0..8 must reconstruct and reach downstream.
        for (n = 0; n <= 8; n = n + 1) begin
            mask = 264'd0;
            if (n > 0) mask = (264'h1 << n) - 264'h1;
            src_r = R0 ^ mask;
            pulse_start(1'b0);
            if (!fe_success || !kcv_pass || downstream_seen != 1)
                $fatal(1, "noise %0d did not pass", n);
        end
        $display("I3A_NOISE_0_8_OK");

        // Noise 9 must never start downstream.
        mask = (264'h1 << 9) - 264'h1;
        src_r = R0 ^ mask;
        pulse_start(1'b0);
        if (downstream_seen != 0)
            $fatal(1, "noise 9 started downstream");
        $display("I3A_NOISE_9_REJECTED");

        // Parser fail: no RO sweep at all.
        src_r = R0; command_ok = 1'b0;
        pulse_start(1'b0);
        if (!early_reject || physical_starts != 0 || downstream_seen != 0)
            $fatal(1, "parser fail did not fail early");
        command_ok = 1'b1;
        $display("I3A_PARSER_FAIL_NO_RO");

        // Anchor invalid: no RO sweep.
        trusted_valid = 1'b0;
        pulse_start(1'b0);
        if (!early_reject || physical_starts != 0)
            $fatal(1, "missing anchor did not fail early");
        trusted_valid = 1'b1;
        $display("I3A_ANCHOR_INVALID_NO_RO");

        // Selected tie: scheduler error, no FE/downstream.
        src_r = R0;
        fault_index = puf64_map_sorted_full(0); fault_kind = 1;
        pulse_start(1'b0);
        if (!mapped_error || downstream_seen != 0)
            $fatal(1, "selected tie was not rejected");
        fault_index = -1; fault_kind = 0;
        $display("I3A_SELECTED_TIE_REJECTED");

        // Timeout on any pair: sticky sweep error.
        fault_index = 100; fault_kind = 2;
        pulse_start(1'b0);
        if (!mapped_error || downstream_seen != 0)
            $fatal(1, "timeout was not rejected");
        fault_index = -1; fault_kind = 0;
        $display("I3A_TIMEOUT_REJECTED");

        // Overflow.
        fault_index = 100; fault_kind = 3;
        pulse_start(1'b0);
        if (!mapped_error || downstream_seen != 0)
            $fatal(1, "overflow was not rejected");
        fault_index = -1;
        $display("I3A_OVERFLOW_REJECTED");

        // Count zero.
        fault_index = 100; fault_kind = 5;
        pulse_start(1'b0);
        if (!mapped_error || downstream_seen != 0)
            $fatal(1, "count zero was not rejected");
        fault_index = -1;
        $display("I3A_ZERO_REJECTED");

        // MMCM unlock.
        fault_index = 100; fault_kind = 6;
        pulse_start(1'b0);
        if (!mapped_error || downstream_seen != 0)
            $fatal(1, "MMCM unlock was not rejected");
        fault_index = -1; fault_kind = 0;
        $display("I3A_MMCM_REJECTED");

        // Helper KCV inconsistent with the anchor.
        src_r = R0; helper_kcv_ref = kcv1;
        pulse_start(1'b0);
        if (downstream_seen != 0 || kcv_pass === 1'b1)
            $fatal(1, "helper KCV mismatch was not rejected");
        helper_kcv_ref = kcv0;
        $display("I3A_HELPER_KCV_MISMATCH_REJECTED");

        // Wrong trusted anchor.
        trusted_ref = kcv1;
        pulse_start(1'b0);
        if (downstream_seen != 0 || kcv_pass === 1'b1)
            $fatal(1, "wrong anchor was not rejected");
        trusted_ref = kcv0;
        $display("I3A_WRONG_ANCHOR_REJECTED");

        // Active substitution: helper0 + attacker KCV (kcv1), CRC handled by
        // the parser layer; anchor stays kcv0.
        src_r = R0; helper_kcv_ref = kcv1;
        pulse_start(1'b0);
        if (downstream_seen != 0)
            $fatal(1, "active substitution was not rejected");
        helper_kcv_ref = kcv0;
        $display("I3A_ACTIVE_SUBSTITUTION_REJECTED");

        // Reset mid-sweep: no downstream, and a clean transaction afterwards.
        src_r = R0;
        @(negedge clk); enroll = 1'b0; start = 1'b1;
        @(negedge clk); start = 1'b0;
        repeat (50) @(posedge clk);
        rst_n = 1'b0;
        repeat (3) @(posedge clk);
        if (downstream_seen != 0 || busy)
            $fatal(1, "reset mid-sweep left the core active");
        rst_n = 1'b1;
        repeat (2) @(posedge clk);
        pulse_start(1'b0);
        if (!fe_success || !kcv_pass || downstream_seen != 1)
            $fatal(1, "post-reset clean transaction failed");
        $display("I3A_RESET_MID_SWEEP_OK");

        reset_in_state(4'd4, "reset_fe");
        $display("I3_7_RESET_MID_FE_OK");
        reset_in_state(4'd6, "reset_kcv");
        $display("I3_7_RESET_MID_KCV_OK");
        downstream_delay = 50;
        reset_in_state(4'd10, "reset_downstream");
        downstream_delay = 1;
        pulse_start(1'b0);
        if (!fe_success || !kcv_pass || downstream_pulses != 1)
            $fatal(1, "clean transaction after staged resets failed");
        $display("I3_7_RESET_DOWNSTREAM_AND_RECOVERY_OK");

        // Hold completion off, then try to start a second request while the
        // first transaction is waiting downstream. It must remain one sweep
        // and one downstream pulse. A following clean transaction must work.
        downstream_delay = 20;
        @(negedge clk); enroll = 1'b0; downstream_seen = 0;
        downstream_pulses = 0; physical_starts = 0; start = 1'b1;
        @(negedge clk); start = 1'b0;
        wait (dut.state == 4'd10);
        starts_before_busy_retry = physical_starts;
        @(negedge clk); start = 1'b1;
        @(negedge clk); start = 1'b0;
        wait (done);
        #1;
        if (physical_starts != starts_before_busy_retry ||
            downstream_pulses != 1 ||
            dut.mapped_latched !== 264'd0 || downstream_key_internal !== 192'd0)
            $fatal(1, "busy start/pulse/erase invariant failed");
        downstream_delay = 1;
        pulse_start(1'b0);
        if (!fe_success || !kcv_pass || downstream_pulses != 1)
            $fatal(1, "second consecutive clean transaction failed");
        $display("I3_7_BUSY_START_TWO_TRANSACTIONS_ZEROIZE_OK");

        $display("I3A_OPERATIONAL_CORE_PASS");
        $finish;
    end

    initial begin
        repeat (20000000) @(posedge clk);
        $fatal(1, "operational core tb timeout");
    end
endmodule

// Test model at the physical boundary.  Real synthesis uses
// rtl/puf/kp_puf64_physical.sv (this module is never in the synthesis list).
module kp_puf64_physical #(
    parameter integer NUM_RO = 64,
    parameter integer WIDTH = 16,
    parameter integer REF_CYCLES = 1023,
    parameter integer CLEAR_CYCLES = 8,
    parameter integer SETTLE_CYCLES = 8,
    parameter integer CAPTURE_TIMEOUT = 1024
)(
    input  logic         clk,
    input  logic         rst_n,
    input  logic         zeroize,
    input  logic         start,
    output logic         busy,
    output logic         done,
    output logic         telemetry_valid,
    output logic [10:0]  telemetry_index,
    output logic [5:0]   telemetry_pair_a,
    output logic [5:0]   telemetry_pair_b,
    output logic [31:0]  telemetry_count0,
    output logic [31:0]  telemetry_count1,
    output logic         telemetry_stable,
    output logic         telemetry_timeout,
    output logic         telemetry_overflow_a,
    output logic         telemetry_overflow_b,
    output logic         telemetry_winner
);
    `include "puf64_mapping_data.vh"

    logic         running;
    logic [10:0]  idx;
    integer       j;
    logic         is_sel;
    logic [8:0]   dest;
    logic [5:0]   pair_a_c, pair_b_c;
    logic [31:0]  c0_c, c1_c;
    logic         win_c;
    logic         ovf_a_c, ovf_b_c;

    function automatic [5:0] canon_a(input integer index);
        integer ii, aa;
        begin
            ii = index; aa = 0;
            while (ii >= 64 - 1 - aa) begin
                ii = ii - (64 - 1 - aa);
                aa = aa + 1;
            end
            canon_a = aa & 6'h3F;
        end
    endfunction

    function automatic [5:0] canon_b(input integer index);
        integer ii, aa;
        begin
            ii = index; aa = 0;
            while (ii >= 64 - 1 - aa) begin
                ii = ii - (64 - 1 - aa);
                aa = aa + 1;
            end
            canon_b = (aa + 1 + ii) & 6'h3F;
        end
    endfunction

    always_comb begin
        is_sel = 1'b0;
        dest = 9'd0;
        for (j = 0; j < 264; j = j + 1) begin
            if (puf64_map_sorted_full(j) == idx) begin
                is_sel = 1'b1;
                dest = puf64_map_sorted_dest(j);
            end
        end
        pair_a_c = canon_a(idx);
        pair_b_c = canon_b(idx);
        if (is_sel && tb_edge_puf64_operational_core.src_r[dest]) begin
            c0_c = 32'd1000; c1_c = 32'd1100;
        end else if (is_sel) begin
            c0_c = 32'd1100; c1_c = 32'd1000;
        end else begin
            c0_c = 32'd1000; c1_c = 32'd1100;
        end
        ovf_a_c = 1'b0;
        ovf_b_c = 1'b0;
        if (idx == tb_edge_puf64_operational_core.fault_index) begin
            case (tb_edge_puf64_operational_core.fault_kind)
                1: begin c0_c = 32'd1000; c1_c = 32'd1000; end
                3: ovf_a_c = 1'b1;
                4: ovf_b_c = 1'b1;
                5: c1_c = 32'd0;
                default: ;
            endcase
        end
        win_c = (c0_c > c1_c) ? 1'b0 : 1'b1;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || zeroize) begin
            running <= 1'b0; idx <= 11'd0;
            busy <= 1'b0; done <= 1'b0;
            telemetry_valid <= 1'b0; telemetry_index <= 11'd0;
            telemetry_pair_a <= 6'd0; telemetry_pair_b <= 6'd0;
            telemetry_count0 <= 32'd0; telemetry_count1 <= 32'd0;
            telemetry_stable <= 1'b1; telemetry_timeout <= 1'b0;
            telemetry_overflow_a <= 1'b0; telemetry_overflow_b <= 1'b0;
            telemetry_winner <= 1'b1;
        end else begin
            done <= 1'b0;
            telemetry_valid <= 1'b0;
            telemetry_overflow_a <= 1'b0;
            telemetry_overflow_b <= 1'b0;
            if (!running) begin
                if (start) begin
                    running <= 1'b1; idx <= 11'd0; busy <= 1'b1;
                end
            end else begin
                telemetry_index <= idx;
                telemetry_pair_a <= pair_a_c;
                telemetry_pair_b <= pair_b_c;
                telemetry_count0 <= c0_c;
                telemetry_count1 <= c1_c;
                telemetry_winner <= win_c;
                telemetry_overflow_a <= ovf_a_c;
                telemetry_overflow_b <= ovf_b_c;
                telemetry_stable <= 1'b1;
                telemetry_timeout <= 1'b0;
                if (idx == tb_edge_puf64_operational_core.fault_index &&
                    tb_edge_puf64_operational_core.fault_kind == 2) begin
                    telemetry_stable <= 1'b0;
                    telemetry_timeout <= 1'b1;
                end
                telemetry_valid <= 1'b1;
                if (idx == 11'd2015) begin
                    running <= 1'b0; busy <= 1'b0; done <= 1'b1;
                end else begin
                    idx <= idx + 11'd1;
                end
            end
        end
    end
endmodule

`default_nettype wire
