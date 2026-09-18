`timescale 1ns / 1ps
`default_nettype none

// End-to-end same-root test through the REAL BCH fuzzy extractor and the REAL
// KCV SHAKE256 gate inside edge_puf_mlkem_core.  Only the PUF and the KEM are
// stubbed.  Proves the review finding: a helper that makes BCH succeed while
// changing the root (codeword delta, other enrollment) must be rejected by the
// KCV gate before any KEM start, and noise beyond the correction radius must
// never start the KEM either.
module tb_edge_phase1_e2e;
    localparam [55:0] CTX = 56'h01000001010101;

    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0;
    reg zeroize = 1'b0;
    reg start = 1'b0;
    reg enroll = 1'b0;
    reg [263:0] helper_in = 264'd0;
    reg [223:0] kcv_ref = 224'd0;
    wire done, kcv_pass, kcv_fail;
    wire [7:0] bch_corr_bits;
    wire [263:0] helper_out;
    wire [223:0] fe_kcv;
    integer cycles;
    integer edge_start_count = 0;
    integer captured_corr = 0;

    // Controlled by this testbench, read by the stub PUF below.
    reg [263:0] puf_resp = 264'd0;

    edge_puf_mlkem_core dut (
        .clk(clk), .rst_n(rst_n), .zeroize(zeroize), .start(start),
        .enroll(enroll), .puf_seed(8'h5a), .helper_in(helper_in),
        .helper_out(helper_out), .fe_success(),
        .kcv_enable(1'b1), .kcv_ref(kcv_ref), .kcv_ctx(CTX),
        .enroll_ctx(CTX), .fe_kcv(fe_kcv),
        .kcv_pass(kcv_pass), .bch_corr_bits(bch_corr_bits),
        .kcv_fail(kcv_fail),
        .stream_in_valid(1'b0), .peer_ready_c(1'b0),
        .peer_req_pk(1'b0), .stream_in_data(32'd0),
        .ready_pk(), .req_c(), .stream_out_valid(), .stream_out_data(),
        .busy(), .done(done), .scrub_done(), .protocol_start(),
        .secret_valid(), .shared_secret()
    );

    always @(posedge clk) begin
        if (rst_n && dut.edge_start)
            edge_start_count = edge_start_count + 1;
        if (rst_n && dut.fe_done)
            captured_corr = bch_corr_bits;
    end

    // Run one enroll/reconstruct and capture the public outputs.
    task automatic run_core(input r_enroll, input [263:0] resp,
                            output [263:0] helper_cap,
                            output [223:0] kcv_cap,
                            output fe_success_cap);
        begin
            puf_resp = resp;
            edge_start_count = 0;
            captured_corr = 0;
            @(negedge clk); start = 1'b1;
            @(negedge clk); start = 1'b0;
            cycles = 0;
            while (!done && cycles < 400) begin
                @(posedge clk);
                cycles = cycles + 1;
            end
            if (!done) $fatal(1, "core transaction timed out");
            helper_cap = helper_out;
            kcv_cap = fe_kcv;
            fe_success_cap = dut.fe_success;
        end
    endtask

    reg [263:0] R0 = {33{8'hA5}};
    reg [263:0] R1 = {33{8'h5A}};
    reg [263:0] helper0, helper1, mask, response;
    reg [223:0] kcv0, kcv1;
    reg fsuccess;
    integer n;

    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        // Enrollment 0 and 1 produce two distinct roots.
        enroll = 1'b1; helper_in = 264'd0; kcv_ref = 224'd0;
        run_core(1'b1, R0, helper0, kcv0, fsuccess);
        if (!fsuccess) $fatal(1, "enroll0 FE failed");
        run_core(1'b1, R1, helper1, kcv1, fsuccess);
        if (!fsuccess) $fatal(1, "enroll1 FE failed");
        if (kcv0 === 224'd0 || kcv1 === 224'd0)
            $fatal(1, "enrollment produced zero KCV");
        if (kcv0 === kcv1)
            $fatal(1, "distinct roots produced identical KCV");
        $display("E2E_ENROLL_OK kcv0=%056x kcv1=%056x", kcv0, kcv1);

        // Reconstruct mode.
        enroll = 1'b0;

        // 1. Noise 0..8 bits must reconstruct to root0 and pass the gate,
        //    with the correction popcount equal to the injected weight.
        for (n = 0; n <= 8; n = n + 1) begin
            mask = 264'd0;
            if (n > 0) mask = (264'h1 << n) - 264'h1;
            response = R0 ^ mask;
            helper_in = helper0; kcv_ref = kcv0;
            run_core(1'b0, response, helper_in, kcv_ref, fsuccess);
            if (!fsuccess) $fatal(1, "noise %0d: FE failed", n);
            if (edge_start_count != 1)
                $fatal(1, "noise %0d: expected one KEM start, got %0d",
                       n, edge_start_count);
            if (kcv_pass !== 1'b1)
                $fatal(1, "noise %0d: KCV gate rejected valid root", n);
            if (captured_corr != n)
                $fatal(1, "noise %0d: reported %0d corrected bits",
                       n, captured_corr);
        end
        $display("E2E_NOISE_0_8_OK");

        // 2. Noise beyond the correction radius must never start the KEM:
        //    either BCH fails or it miscorrects to a different root, and the
        //    KCV gate then blocks it.
        for (n = 9; n <= 16; n = n + 1) begin
            mask = (264'h1 << n) - 264'h1;
            helper_in = helper0; kcv_ref = kcv0;
            run_core(1'b0, R0 ^ mask, helper_in, kcv_ref, fsuccess);
            if (edge_start_count != 0)
                $fatal(1, "noise %0d: KEM started on wrong root", n);
        end
        $display("E2E_NOISE_GT8_OK");

        // 3. Codeword delta: reconstruct with helper0 and a response chosen so
        //    that BCH decodes the OTHER enrollment's codeword (success=1) but
        //    the root differs from root0.  The KCV gate must reject it.
        response = helper0 ^ helper1 ^ R1;
        helper_in = helper0; kcv_ref = kcv0;
        run_core(1'b0, response, helper_in, kcv_ref, fsuccess);
        if (!fsuccess)
            $fatal(1, "codeword-delta: FE did not report decode success");
        if (edge_start_count != 0)
            $fatal(1, "codeword-delta: KEM started on a different root");
        if (kcv_fail !== 1'b1)
            $fatal(1, "codeword-delta: kcv_fail telemetry not asserted");
        $display("E2E_CODEWORD_DELTA_REJECTED_OK");

        $display("EDGE_PHASE1_E2E_PASS");
        $finish;
    end

    initial begin
        repeat (400000) @(posedge clk);
        $fatal(1, "timeout");
    end
endmodule

// Stub PUF: full 264-bit response controlled by the testbench via a
// hierarchical reference (simulation only).
module kp_puf_top (
    input wire clk, input wire rst_n, input wire zeroize, input wire start,
    input wire [7:0] seed, output reg busy, output reg done,
    output reg [263:0] response,
    output reg telemetry_valid, output reg [8:0] telemetry_index,
    output reg [7:0] telemetry_challenge, output reg [31:0] telemetry_count0,
    output reg [31:0] telemetry_count1, output reg telemetry_winner
);
    always @(posedge clk or negedge rst_n or posedge zeroize) begin
        if (!rst_n || zeroize) begin
            busy <= 1'b0; done <= 1'b0; response <= 264'd0;
            telemetry_valid <= 1'b0; telemetry_index <= 9'd0;
            telemetry_challenge <= 8'd0; telemetry_count0 <= 32'd0;
            telemetry_count1 <= 32'd0; telemetry_winner <= 1'b0;
        end else begin
            done <= busy;
            busy <= start;
            if (start)
                response <= tb_edge_phase1_e2e.puf_resp;
        end
    end
endmodule

// Stub KEM: never actually runs; the KCV gate decides before edge_start.
module edge_mlkem_core (
    input wire clk, input wire rst_n, input wire zeroize, input wire start,
    input wire [191:0] fe_key, input wire stream_in_valid,
    input wire peer_ready_c, input wire peer_req_pk,
    input wire [31:0] stream_in_data, output wire ready_pk,
    output wire req_c, output wire stream_out_valid,
    output wire [31:0] stream_out_data, output reg busy, output reg done,
    output wire scrub_done, output wire protocol_start,
    output reg secret_valid, output reg [255:0] shared_secret
);
    assign ready_pk = 1'b0;
    assign req_c = 1'b0;
    assign stream_out_valid = 1'b0;
    assign stream_out_data = 32'd0;
    assign scrub_done = done;
    assign protocol_start = start;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || zeroize) begin
            busy <= 1'b0; done <= 1'b0; secret_valid <= 1'b0;
            shared_secret <= 256'd0;
        end else begin
            done <= busy;
            secret_valid <= busy;
            busy <= start;
        end
    end
endmodule

`default_nettype wire
