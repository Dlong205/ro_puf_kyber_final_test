`timescale 1ns / 1ps
`default_nettype none

// Phase-1 negative tests at the edge_puf_mlkem_core level.  The stub PUF
// encodes a scenario in puf_seed and the stub FE derives success/key from it,
// so the testbench can exercise wrong-root, over-noise, reset/zeroize and
// KCV-timing cases through the real core FSM and KCV gate.
//
// Scenario encoding (low byte of puf_seed):
//   0x1X  FE success, key == TEST_KEY              (good)
//   0x2X  FE success, key != TEST_KEY              (codeword delta / other enrollment)
//   0x3N  N-bit noise: success iff N <= 8, key == TEST_KEY
//   0xF0  FE failure (random helper / over-noise)
module tb_edge_phase1;
    localparam [191:0] TEST_KEY =
        192'h0123456789abcdef_fedcba9876543210_a55a5aa5_deadbeef;
    // KCV for TEST_KEY with ctx all-0x01 (host SHAKE256, see
    // scripts/helper_record_spec.py).
    localparam [223:0] TEST_KCV =
        224'hadaf31dbbf9f894024a99ee438675ce991f4c98f2a2c523b15335b7c;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg zeroize = 1'b0;
    reg start = 1'b0;
    reg [7:0] puf_seed = 8'h10;
    reg [223:0] kcv_ref = TEST_KCV;
    wire done;
    wire kcv_pass;
    wire kcv_fail;
    wire [7:0] bch_corr_bits;
    wire [263:0] helper_out;
    wire protocol_start;
    wire secret_valid;
    integer cycles;
    always #5 clk = ~clk;

    integer edge_start_count;
    integer protocol_start_count;
    integer secret_valid_count;
    integer captured_corr;

    edge_puf_mlkem_core dut (
        .clk(clk), .rst_n(rst_n), .zeroize(zeroize), .start(start),
        .enroll(1'b0), .puf_seed(puf_seed), .helper_in(264'h1),
        .helper_out(helper_out), .fe_success(),
        .kcv_enable(1'b1), .kcv_ref(kcv_ref), .kcv_ctx(56'h01010101_010101),
        .enroll_ctx(56'h01010101_010101), .fe_kcv(),
        .kcv_pass(kcv_pass), .bch_corr_bits(bch_corr_bits), .kcv_fail(kcv_fail),
        .stream_in_valid(1'b0),
        .peer_ready_c(1'b0), .peer_req_pk(1'b0), .stream_in_data(32'd0),
        .ready_pk(), .req_c(), .stream_out_valid(), .stream_out_data(),
        .busy(), .done(done), .scrub_done(), .protocol_start(protocol_start),
        .secret_valid(secret_valid), .shared_secret()
    );

    always @(posedge clk) begin
        if (rst_n && dut.edge_start)
            edge_start_count = edge_start_count + 1;
        if (rst_n && protocol_start)
            protocol_start_count = protocol_start_count + 1;
        if (rst_n && secret_valid)
            secret_valid_count = secret_valid_count + 1;
        if (rst_n && dut.state == 4'd4 && dut.fe_done)
            captured_corr = bch_corr_bits;
    end

    // The core instantiates its own scenario-driven PUF/FE/KEM stubs below.
    task automatic run_case(input [7:0] seed, input [223:0] reference,
                            input integer want_edge, input integer want_kcv);
        begin
            puf_seed = seed;
            kcv_ref = reference;
            edge_start_count = 0;
            protocol_start_count = 0;
            secret_valid_count = 0;
            @(negedge clk); start = 1'b1;
            @(negedge clk); start = 1'b0;
            cycles = 0;
            while (!done && cycles < 400) begin
                @(posedge clk);
                cycles = cycles + 1;
            end
            if (!done) $fatal(1, "case timed out");
            if (edge_start_count != want_edge)
                $fatal(1, "seed=%02x edge_start=%0d expected=%0d",
                       seed, edge_start_count, want_edge);
            if (kcv_pass !== want_kcv[0])
                $fatal(1, "seed=%02x kcv_pass=%b expected=%0d",
                       seed, kcv_pass, want_kcv);
            if (edge_start_count != 0 &&
                (protocol_start_count == 0 || secret_valid_count == 0))
                $fatal(1, "seed=%02x missing protocol/secret handoff", seed);
        end
    endtask

    integer t_first, t_mid, t_last;
    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(negedge clk);

        // 1. Good root, correct KCV.
        run_case(8'h10, TEST_KCV, 1, 1);
        if (captured_corr != 0)
            $fatal(1, "good case reported %0d corrected bits", captured_corr);
        $display("PHASE1_GOOD_OK");

        // 2. FE failure / random helper must not launch the KEM.
        run_case(8'hf0, TEST_KCV, 0, 0);
        $display("PHASE1_RANDOM_HELPER_OK");

        // 3/4. FE success but wrong root (codeword delta / other enrollment):
        //      KCV must reject and no start pulse may reach KDF/ML-KEM.
        run_case(8'h21, TEST_KCV, 0, 0);
        run_case(8'h22, TEST_KCV, 0, 0);
        $display("PHASE1_WRONG_ROOT_OK");

        // 5. PUF noise 0..8 bits with the correct record still reconstructs;
        //    the applied correction popcount must equal the injected count.
        for (integer n = 0; n <= 8; n = n + 1) begin
            run_case(8'h30 | n[7:0], TEST_KCV, 1, 1);
            if (captured_corr != n)
                $fatal(1, "noise %0d reported %0d corrected bits",
                       n, captured_corr);
        end
        $display("PHASE1_NOISE_0_8_OK");

        // 6. Noise beyond the BCH correction radius must fail closed.
        for (integer n = 9; n <= 15; n = n + 1) begin
            run_case(8'h30 | n[7:0], TEST_KCV, 0, 0);
        end
        $display("PHASE1_NOISE_GT8_OK");

        // 7. KCV wrong at byte in word 0/3/5/6 all reject with equal latency.
        //    Word 5 is explicit: the pre-review folded compare skipped it.
        puf_seed = 8'h10; kcv_ref = TEST_KCV ^ 224'h1;
        @(negedge clk); start = 1'b1; @(negedge clk); start = 1'b0;
        cycles = 0;
        while (!done && cycles < 400) begin @(posedge clk); cycles = cycles + 1; end
        t_first = cycles;
        if (edge_start_count != 0) $fatal(1, "kcv-first launched KEM");
        @(negedge clk);
        kcv_ref = TEST_KCV ^ (224'h1 << 112);
        @(negedge clk); start = 1'b1; @(negedge clk); start = 1'b0;
        cycles = 0;
        while (!done && cycles < 400) begin @(posedge clk); cycles = cycles + 1; end
        t_mid = cycles;
        if (edge_start_count != 0) $fatal(1, "kcv-mid launched KEM");
        @(negedge clk);
        kcv_ref = TEST_KCV ^ (224'h1 << 168);
        @(negedge clk); start = 1'b1; @(negedge clk); start = 1'b0;
        cycles = 0;
        while (!done && cycles < 400) begin @(posedge clk); cycles = cycles + 1; end
        if (edge_start_count != 0) $fatal(1, "kcv-word5 launched KEM");
        if (cycles != t_mid) $fatal(1, "word5 latency %0d != %0d", cycles, t_mid);
        @(negedge clk);
        kcv_ref = TEST_KCV ^ (224'h1 << 216);
        @(negedge clk); start = 1'b1; @(negedge clk); start = 1'b0;
        cycles = 0;
        while (!done && cycles < 400) begin @(posedge clk); cycles = cycles + 1; end
        t_last = cycles;
        if (edge_start_count != 0) $fatal(1, "kcv-last launched KEM");
        if (t_first != t_mid || t_first != t_last)
            $fatal(1, "KCV fail latency varies: %0d/%0d/%0d",
                   t_first, t_mid, t_last);
        $display("PHASE1_KCV_POSITION_TIMING_OK cycles=%0d word5=covered", t_first);

        // 8. Zeroize mid-reconstruct (during KCV) must scrub and not launch.
        @(negedge clk); edge_start_count = 0; start = 1'b1; kcv_ref = TEST_KCV;
        @(negedge clk); start = 1'b0;
        repeat (12) @(posedge clk);
        zeroize = 1'b1;
        @(negedge clk); zeroize = 1'b0;
        repeat (3) @(posedge clk);
        if (edge_start_count != 0)
            $fatal(1, "zeroize mid-KCV launched the KEM");
        if (dut.u_fe.key_out !== 192'd0)
            $fatal(1, "zeroize mid-KCV left the FE key");
        @(negedge clk);
        // core must re-arm after the abort
        run_case(8'h10, TEST_KCV, 1, 1);
        $display("PHASE1_ZEROIZE_MID_OK");

        // 9. Reset mid-BCH must abort and leave no start pulse.
        @(negedge clk); edge_start_count = 0; start = 1'b1;
        @(negedge clk); start = 1'b0;
        repeat (3) @(posedge clk);
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (4) @(posedge clk);
        if (edge_start_count != 0)
            $fatal(1, "reset mid-BCH launched the KEM");
        @(negedge clk);
        run_case(8'h10, TEST_KCV, 1, 1);
        $display("PHASE1_RESET_MID_OK");

        $display("EDGE_PHASE1_NEGATIVE_PASS");
        $finish;
    end

    initial begin
        repeat (20000) @(posedge clk);
        $fatal(1, "timeout");
    end
endmodule

// Scenario-driven stubs.  kp_puf_top is a stub already declared in the gate
// testbench but Verilator compiles each top separately, so redeclare here.
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
                response <= {256'h0, seed};
        end
    end
endmodule

module fuzzy_extractor (
    input wire clk, input wire rst_n, input wire zeroize, input wire start,
    input wire mode, input wire [263:0] response_in,
    input wire [263:0] helper_in, output reg [263:0] helper_out,
    output reg [191:0] key_out, output reg busy, output reg done,
    output reg success, output reg [7:0] corr_bit_count
);
    localparam [191:0] TEST_KEY =
        192'h0123456789abcdef_fedcba9876543210_a55a5aa5_deadbeef;
    wire [7:0] scenario = response_in[7:0];
    wire [7:0] noise = scenario[3:0];
    wire fe_ok = (scenario != 8'hf0) &&
                 !((scenario[7:4] == 4'h3) && (noise > 8));
    wire [191:0] fe_key = (scenario[7:4] == 4'h2)
                          ? (TEST_KEY ^ 192'hdeadbeef)
                          : TEST_KEY;
    always @(posedge clk or negedge rst_n or posedge zeroize) begin
        if (!rst_n || zeroize) begin
            helper_out <= 264'd0; key_out <= 192'd0; busy <= 1'b0;
            done <= 1'b0; success <= 1'b0; corr_bit_count <= 8'd0;
        end else begin
            done <= busy;
            busy <= (mode ? start : 1'b0);
            if (mode && start) begin
                helper_out <= helper_in ^ response_in;
                key_out <= fe_key;
                success <= fe_ok;
                corr_bit_count <= response_in[3:0];
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
    localparam [191:0] TEST_KEY =
        192'h0123456789abcdef_fedcba9876543210_a55a5aa5_deadbeef;
    assign ready_pk = busy;
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
            if (start)
                shared_secret <= {64'd0, fe_key ^
                    ((fe_key == TEST_KEY) ? 192'd0 : TEST_KEY)};
        end
    end
endmodule

`default_nettype wire
