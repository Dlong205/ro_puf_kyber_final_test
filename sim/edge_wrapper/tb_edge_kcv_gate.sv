`timescale 1ns / 1ps
`default_nettype none

// Stub PUF/FE/KEM models identical to tb_edge_puf_mlkem_handoff.  The FE
// stub returns success in reconstruct mode and a fixed TEST_KEY.
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
            if (start) response <= {256'h1234, seed};
        end
    end
endmodule

module fuzzy_extractor (
    input wire clk, input wire rst_n, input wire zeroize, input wire start,
    input wire mode, input wire [263:0] response_in,
    input wire [263:0] helper_in, output reg [263:0] helper_out,
    output reg [191:0] key_out, output reg busy, output reg done,
    output reg success, output wire [7:0] corr_bit_count
);
    localparam [191:0] TEST_KEY = 192'h0123456789abcdef_fedcba9876543210_a55a5aa5_deadbeef;
    assign corr_bit_count = 8'd0;
    always @(posedge clk or negedge rst_n or posedge zeroize) begin
        if (!rst_n || zeroize) begin
            helper_out <= 264'd0; key_out <= 192'd0; busy <= 1'b0;
            done <= 1'b0; success <= 1'b0;
        end else begin
            done <= busy;
            busy <= start;
            if (start) begin
                helper_out <= helper_in ^ response_in;
                key_out <= TEST_KEY;
                success <= mode;
            end
        end
    end
endmodule

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
    localparam [191:0] TEST_KEY = 192'h0123456789abcdef_fedcba9876543210_a55a5aa5_deadbeef;
    reg captured_good;
    assign ready_pk = 1'b0;
    assign req_c = 1'b0;
    assign stream_out_valid = 1'b0;
    assign stream_out_data = 32'd0;
    assign scrub_done = done;
    assign protocol_start = start;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || zeroize) begin
            busy <= 1'b0; done <= 1'b0; secret_valid <= 1'b0;
            shared_secret <= 256'd0; captured_good <= 1'b0;
        end else begin
            done <= busy;
            secret_valid <= busy;
            busy <= start;
            if (start) begin
                captured_good <= fe_key == TEST_KEY;
                shared_secret <= {64'd0, fe_key};
            end
        end
    end
endmodule

// Fail-closed same-root gate test: reconstruct path through the real
// edge_puf_mlkem_core with stub PUF/FE/KEM.  A wrong KCV reference must
// block edge_start and scrub the FE key; the correct reference must hand
// the key to the seed controller exactly once.
module tb_edge_kcv_gate;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg zeroize = 1'b0;
    reg start = 1'b0;
    wire done;
    integer cycles;
    always #5 clk = ~clk;

    // KAT reference for the stub TEST_KEY with kcv_ctx =
    // 56'h01010101_010101 (all bytes 0x01), host-computed SHAKE256.
    localparam [223:0] TEST_KCV = 224'hadaf31dbbf9f894024a99ee438675ce991f4c98f2a2c523b15335b7c;

    reg [223:0] kcv_ref = TEST_KCV;
    wire kcv_pass;
    integer edge_start_count;
    integer fail_count;

    edge_puf_mlkem_core dut (
        .clk(clk), .rst_n(rst_n), .zeroize(zeroize), .start(start),
        .enroll(1'b0), .puf_seed(8'h5a), .helper_in(264'h1),
        .helper_out(), .fe_success(),
        .enroll_allowed(1'b1), .trusted_kcv_valid(1'b1),
        .trusted_kcv_ref(kcv_ref), .helper_kcv_ref(kcv_ref),
        .helper_kcv_valid(1'b1), .kcv_ctx(56'h01010101_010101),
        .enroll_ctx(56'h01010101_010101), .fe_kcv(),
        .kcv_pass(),
        .stream_in_valid(1'b0),
        .peer_ready_c(1'b0), .peer_req_pk(1'b0), .stream_in_data(32'd0),
        .ready_pk(), .req_c(), .stream_out_valid(), .stream_out_data(),
        .busy(), .done(done), .scrub_done(), .protocol_start(),
        .secret_valid(), .shared_secret()
    );

    always @(posedge clk)
        if (rst_n && dut.edge_start)
            edge_start_count = edge_start_count + 1;

    task automatic run_recon;
        begin
            edge_start_count = 0;
            @(posedge clk); start <= 1'b1;
            @(posedge clk); start <= 1'b0;
            cycles = 0;
            while (!done && cycles < 300) begin
                @(posedge clk);
                cycles = cycles + 1;
            end
            if (!done) $fatal(1, "transaction timed out");
        end
    endtask

    initial begin
        fail_count = 0;
        repeat (3) @(posedge clk);
        rst_n <= 1'b1;
        @(negedge clk);

        // 1. Correct reference: gate must allow exactly one edge_start.
        run_recon();
        if (edge_start_count != 1)
            $fatal(1, "pass path: edge_start_count=%0d expected 1",
                   edge_start_count);
        if (!dut.u_edge.captured_good)
            $fatal(1, "pass path: Edge captured wrong key");
        if (dut.u_fe.key_out !== 192'd0)
            $fatal(1, "pass path: FE key not erased after handoff");
        if (dut.kcv_pass !== 1'b1)
            $fatal(1, "pass path: kcv_pass not asserted");
        $display("KCV_GATE_PASS_PATH_OK cycles=%0d", cycles);

        @(negedge clk);

        // 2. Corrupted reference (first byte): gate must block.
        kcv_ref = TEST_KCV ^ 224'hff;
        run_recon();
        if (edge_start_count != 0)
            $fatal(1, "fail path: edge_start fired on KCV mismatch");
        if (dut.kcv_pass !== 1'b0)
            $fatal(1, "fail path: kcv_pass asserted");
        if (dut.u_fe.key_out !== 192'd0)
            $fatal(1, "fail path: FE key not scrubbed after KCV failure");
        if (dut.u_edge.fe_key !== 192'd0)
            $fatal(1, "fail path: Edge seed input not scrubbed");
        $display("KCV_GATE_FAIL_PATH_OK cycles=%0d", cycles);

        @(negedge clk);

        // 3. Recovery: correct reference must pass again after a failure.
        kcv_ref = TEST_KCV;
        run_recon();
        if (edge_start_count != 1)
            $fatal(1, "recovery path: edge_start_count=%0d expected 1",
                   edge_start_count);
        $display("KCV_GATE_RECOVERY_OK cycles=%0d", cycles);

        @(negedge clk);

        // 4. Zeroize during the KCV computation must abort to a clean idle
        //    and report done with fe_success=0 (fail-closed).
        edge_start_count = 0;
        kcv_ref = TEST_KCV ^ 224'hff;
        @(posedge clk); start <= 1'b1;
        @(posedge clk); start <= 1'b0;
        repeat (10) @(posedge clk);
        zeroize <= 1'b1;
        @(posedge clk); zeroize <= 1'b0;
        cycles = 0;
        while (!done && cycles < 300) begin
            @(posedge clk); cycles = cycles + 1;
        end
        if (edge_start_count != 0)
            $fatal(1, "abort path: edge_start fired after zeroize");
        $display("KCV_GATE_ABORT_OK");

        $display("EDGE_KCV_GATE_PASS");
        $finish;
    end

    initial begin
        repeat (5000) @(posedge clk);
        $fatal(1, "timeout");
    end
endmodule

`default_nettype wire
