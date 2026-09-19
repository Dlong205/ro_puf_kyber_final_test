`timescale 1ns / 1ps
`default_nettype none

// I2.5 KCV trust-anchor audit test.  REAL BCH fuzzy extractor + REAL KCV
// SHAKE256 gate inside edge_puf_mlkem_core; only the PUF and the KEM are
// stubbed.  Demonstrates whether a helper-provided KCV reference can be
// substituted together with the helper.
//
// Cases:
//   1. enroll R0/R1 -> public helpers and KCVs.
//   2. codeword delta with the original KCV reference: rejected.
//   3. codeword delta with the MATCHING (attacker-supplied) KCV reference:
//      if the gate passes and the KEM starts, the current architecture is
//      vulnerable to active helper+KCV substitution.
module tb_edge_kcv_substitution;
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
    end

    task automatic run_core(input [263:0] resp,
                            output [263:0] helper_cap,
                            output [223:0] kcv_cap,
                            output fe_success_cap);
        begin
            puf_resp = resp;
            edge_start_count = 0;
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
    reg [263:0] helper0, helper1, response;
    reg [223:0] kcv0, kcv1;
    reg fsuccess;

    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        enroll = 1'b1; helper_in = 264'd0; kcv_ref = 224'd0;
        run_core(R0, helper0, kcv0, fsuccess);
        if (!fsuccess) $fatal(1, "enroll0 FE failed");
        run_core(R1, helper1, kcv1, fsuccess);
        if (!fsuccess) $fatal(1, "enroll1 FE failed");
        if (kcv0 === kcv1) $fatal(1, "distinct roots produced identical KCV");
        $display("KCVSUB_ENROLL_OK");

        enroll = 1'b0;
        // Case A: codeword delta, original KCV reference -> must be rejected.
        response = helper0 ^ helper1 ^ R1;
        helper_in = helper0; kcv_ref = kcv0;
        run_core(response, helper_in, kcv_ref, fsuccess);
        if (!fsuccess) $fatal(1, "case A: FE did not report success");
        if (edge_start_count != 0 || kcv_pass === 1'b1)
            $fatal(1, "case A: gate accepted a different root");
        $display("KCVSUB_DELTA_ORIGINAL_KCV_REJECTED");

        // Case B: the attacker also substitutes the KCV reference that
        // matches the reconstructed root.  The current architecture compares
        // helper-provided reference vs computed digest, so this must PASS if
        // the anchor is not separate.
        helper_in = helper0; kcv_ref = kcv1;
        run_core(response, helper_in, kcv_ref, fsuccess);
        if (!fsuccess) $fatal(1, "case B: FE did not report success");
        if (kcv_pass !== 1'b1 || edge_start_count != 1)
            $fatal(1, "case B: substitution unexpectedly blocked");
        $display("KCV_ACTIVE_SUBSTITUTION_CONFIRMED helper+kcv both replaced");

        // Case C: correct root with the wrong reference must still fail.
        helper_in = helper0; kcv_ref = kcv1;
        run_core(R0, helper_in, kcv_ref, fsuccess);
        if (edge_start_count != 0 || kcv_pass === 1'b1)
            $fatal(1, "case C: gate accepted correct root with wrong KCV");
        $display("KCVSUB_WRONG_REFERENCE_REJECTED");

        $display("EDGE_KCV_SUBSTITUTION_AUDIT_PASS");
        $finish;
    end

    initial begin
        repeat (400000) @(posedge clk);
        $fatal(1, "timeout");
    end
endmodule

// Stub PUF: response controlled by the testbench (simulation only).
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
                response <= tb_edge_kcv_substitution.puf_resp;
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
