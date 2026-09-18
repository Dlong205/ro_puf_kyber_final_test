`timescale 1ns / 1ps
`default_nettype none

// Phase-1 behaviour through the separate ASIC boundary top.  The scenario
// stubs below reuse the exact encoding channel of tb_edge_phase1 so the
// ASIC-top tests exercise the SAME core FSM/KCV gate, but every stimulus and
// observation crosses Edge_Puf_Mlkem_Asic_Top's ports:
//   - reset through reset_sync_n (async assert on rst_ni),
//   - kcv_pass_o / status_o / helper_out_o / kcv_out_o / result_tag_o wiring,
//   - fail-closed negative cases stay fail-closed at the boundary.
module tb_edge_asic_top;
    localparam [191:0] TEST_KEY =
        192'h0123456789abcdef_fedcba9876543210_a55a5aa5_deadbeef;
    localparam [223:0] TEST_KCV =
        224'hadaf31dbbf9f894024a99ee438675ce991f4c98f2a2c523b15335b7c;
    // XOR-fold of shared_secret for the good root (see TEST_KEY above);
    // independent of the RTL expression so a fold typo cannot self-verify.
    localparam [31:0] TEST_TAG = 32'h7bf7e44a;

    reg clk = 1'b0;
    reg rst_ni = 1'b0;
    reg zeroize_i = 1'b0;
    reg enroll_i = 1'b0;
    reg start_i = 1'b0;
    reg [7:0] puf_seed_i = 8'h10;
    reg [223:0] kcv_ref_i = TEST_KCV;
    wire [263:0] helper_out_o;
    wire kcv_pass_o;
    wire kcv_fail_o;
    wire [223:0] kcv_out_o;
    wire fe_success_o;
    wire [7:0] bch_corr_bits_o;
    wire busy_o;
    wire done_o;
    wire scrub_done_o;
    wire protocol_start_o;
    wire secret_valid_o;
    wire [31:0] result_tag_o;
    wire [1:0] status_o;
    integer cycles;
    always #5 clk = ~clk;

    integer edge_start_count;
    integer protocol_start_count;
    integer secret_valid_count;
    integer scrub_count;
    integer captured_corr;
    reg [263:0] captured_helper;

    Edge_Puf_Mlkem_Asic_Top dut_as (
        .clk_i(clk), .rst_ni(rst_ni),
        .zeroize_i(zeroize_i), .enroll_i(enroll_i), .start_i(start_i),
        .puf_seed_i(puf_seed_i),
        .helper_in_i(264'h1), .helper_out_o(helper_out_o),
        .kcv_enable_i(1'b1), .kcv_ref_i(kcv_ref_i), .kcv_ctx_i(56'h01010101_010101),
        .enroll_ctx_i(56'h01010101_010101),
        .kcv_pass_o(kcv_pass_o), .kcv_fail_o(kcv_fail_o), .kcv_out_o(kcv_out_o),
        .fe_success_o(fe_success_o), .bch_corr_bits_o(bch_corr_bits_o),
        .peer_req_pk_i(1'b0), .peer_ready_c_i(1'b0),
        .stream_in_valid_i(1'b0), .stream_in_data_i(32'd0),
        .ready_pk_o(), .req_c_o(), .stream_out_valid_o(), .stream_out_data_o(),
        .busy_o(busy_o), .done_o(done_o), .scrub_done_o(scrub_done_o),
        .protocol_start_o(protocol_start_o), .secret_valid_o(secret_valid_o),
        .result_tag_o(result_tag_o), .status_o(status_o)
    );

    always @(posedge clk) begin
        if (rst_ni && dut_as.u_core.edge_start)
            edge_start_count = edge_start_count + 1;
        if (rst_ni && protocol_start_o)
            protocol_start_count = protocol_start_count + 1;
        if (rst_ni && secret_valid_o)
            secret_valid_count = secret_valid_count + 1;
        if (rst_ni && scrub_done_o)
            scrub_count = scrub_count + 1;
        if (rst_ni && dut_as.u_core.state == 4'd4 && dut_as.u_core.fe_done) begin
            captured_corr = bch_corr_bits_o;
            captured_helper = helper_out_o;
        end
    end

    task automatic run_case(input [7:0] seed, input [223:0] reference,
                            input integer want_edge, input integer want_kcv);
        begin
            puf_seed_i = seed;
            kcv_ref_i = reference;
            edge_start_count = 0;
            protocol_start_count = 0;
            secret_valid_count = 0;
            scrub_count = 0;
            @(negedge clk); start_i = 1'b1;
            @(negedge clk); start_i = 1'b0;
            cycles = 0;
            while (!done_o && cycles < 400) begin
                @(posedge clk);
                cycles = cycles + 1;
            end
            if (!done_o) $fatal(1, "case timed out");
            if (edge_start_count != want_edge)
                $fatal(1, "seed=%02x edge_start=%0d expected=%0d",
                       seed, edge_start_count, want_edge);
            if (kcv_pass_o !== want_kcv[0])
                $fatal(1, "seed=%02x kcv_pass_o=%b expected=%0d",
                       seed, kcv_pass_o, want_kcv);
            if (status_o[0] !== kcv_pass_o)
                $fatal(1, "status_o[0] disagrees with kcv_pass_o=%b", kcv_pass_o);
            if (status_o[1] !== done_o)
                $fatal(1, "status_o[1] disagrees with done_o=%b", done_o);
            if (want_kcv != 0 &&
                (protocol_start_count == 0 || secret_valid_count == 0 ||
                 scrub_count == 0))
                $fatal(1, "seed=%02x missing protocol/secret/scrub handoff", seed);
        end
    endtask

    initial begin
        repeat (3) @(posedge clk);
        rst_ni = 1'b1;
        @(negedge clk);

        // 0. Enroll through the boundary: helper_out_o is captured at
        //    ST_FE_WAIT and kcv_out_o publishes the SHAKE256 KCV digest
        //    (ST_KCV_GEN) that a host verifier must reproduce.  Enrollment
        //    must not launch the KEM.
        captured_helper = 264'h0; captured_corr = 0;
        edge_start_count = 0; protocol_start_count = 0;
        secret_valid_count = 0; scrub_count = 0;
        enroll_i = 1'b1; kcv_ref_i = TEST_KCV; puf_seed_i = 8'h10;
        @(negedge clk); start_i = 1'b1;
        @(negedge clk); start_i = 1'b0;
        cycles = 0;
        while (!done_o && cycles < 400) begin @(posedge clk); cycles = cycles + 1; end
        enroll_i = 1'b0;
        if (!done_o) $fatal(1, "enroll timed out");
        if (edge_start_count != 0)
            $fatal(1, "enroll launched the KEM");
        if (captured_helper !== 264'h11)
            $fatal(1, "enroll helper_out_o=%x expected 0x11", captured_helper);
        if (kcv_out_o !== TEST_KCV)
            $fatal(1, "enroll kcv_out_o=%h != published KCV %h", kcv_out_o, TEST_KCV);
        if (fe_success_o !== 1'b1)
            $fatal(1, "fe_success_o not asserted on enroll");
        if (kcv_fail_o !== 1'b0) $fatal(1, "enroll asserted kcv_fail_o");
        if (status_o[1] !== done_o) $fatal(1, "status_o[1] disagrees on enroll");
        $display("ASIC_TOP_ENROLL_OK kcv=%h", kcv_out_o);

        // 1. Good root: gate open, full handoff, verified boundary folds.
        run_case(8'h10, TEST_KCV, 1, 1);
        if (captured_corr != 0)
            $fatal(1, "good case reported %0d corrected bits", captured_corr);
        if (captured_helper !== 264'h11)
            $fatal(1, "decode helper_out_o=%x expected 0x11", captured_helper);
        if (fe_success_o !== 1'b1)
            $fatal(1, "fe_success_o not asserted on good root");
        if (kcv_fail_o !== 1'b0)
            $fatal(1, "kcv_fail_o asserted on good root");
        if (result_tag_o !== TEST_TAG)
            $fatal(1, "result_tag_o=%h != %h", result_tag_o, TEST_TAG);
        $display("ASIC_TOP_GOOD_OK tag=%08x", result_tag_o);

        // 2. FE failure / random helper must not launch the KEM.
        run_case(8'hf0, TEST_KCV, 0, 0);
        if (kcv_fail_o !== 1'b0)
            $fatal(1, "kcv_fail_o on FE failure is ambiguous");
        $display("ASIC_TOP_RANDOM_HELPER_OK");

        // 3/4. FE success but wrong root: KCV must reject at the boundary.
        run_case(8'h21, TEST_KCV, 0, 0);
        if (kcv_fail_o !== 1'b1)
            $fatal(1, "kcv_fail_o not asserted on wrong root");
        if (protocol_start_count != 0)
            $fatal(1, "wrong root launched the KEM");
        run_case(8'h22, TEST_KCV, 0, 0);
        $display("ASIC_TOP_WRONG_ROOT_OK");

        // 5. PUF noise 0..8 recomposes within radius; boundary telemetry
        //    matches the injected count.
        for (integer n = 0; n <= 8; n = n + 1) begin
            run_case(8'h30 | n[7:0], TEST_KCV, 1, 1);
            if (captured_corr != n)
                $fatal(1, "noise %0d reported %0d corrected bits", n, captured_corr);
        end
        $display("ASIC_TOP_NOISE_0_8_OK");

        // 6. Noise beyond the BCH radius must fail closed.
        for (integer n = 9; n <= 15; n = n + 1)
            run_case(8'h30 | n[7:0], TEST_KCV, 0, 0);
        $display("ASIC_TOP_NOISE_GT8_OK");

        // 7. One flipped KCV reference bit rejects with the same fail latency
        //    as the other positions (gate is present, no KEM launch).
        kcv_ref_i = TEST_KCV ^ 224'h1; puf_seed_i = 8'h10;
        edge_start_count = 0; protocol_start_count = 0; secret_valid_count = 0;
        scrub_count = 0;
        @(negedge clk); start_i = 1'b1; @(negedge clk); start_i = 1'b0;
        cycles = 0;
        while (!done_o && cycles < 400) begin @(posedge clk); cycles = cycles + 1; end
        if (edge_start_count != 0) $fatal(1, "flipped KCV launched the KEM");
        if (kcv_fail_o !== 1'b1) $fatal(1, "flipped KCV did not assert kcv_fail_o");
        $display("ASIC_TOP_KCV_FLIP_OK");

        // 8. Zeroize mid-reconstruct must scrub and not launch.
        edge_start_count = 0; start_i = 1'b1; kcv_ref_i = TEST_KCV; puf_seed_i = 8'h10;
        @(negedge clk); start_i = 1'b0;
        repeat (12) @(posedge clk);
        zeroize_i = 1'b1;
        @(negedge clk); zeroize_i = 1'b0;
        repeat (3) @(posedge clk);
        if (edge_start_count != 0)
            $fatal(1, "zeroize mid-KCV launched the KEM");
        if (dut_as.u_core.u_fe.key_out !== 192'd0)
            $fatal(1, "zeroize mid-KCV left the FE key");
        run_case(8'h10, TEST_KCV, 1, 1);
        $display("ASIC_TOP_ZEROIZE_MID_OK");

        // 9. Reset through rst_ni mid-BCH must abort and leave no pulse.
        edge_start_count = 0; start_i = 1'b1;
        @(negedge clk); start_i = 1'b0;
        repeat (3) @(posedge clk);
        rst_ni = 1'b0;
        repeat (4) @(posedge clk);
        rst_ni = 1'b1;
        repeat (4) @(posedge clk);
        if (edge_start_count != 0)
            $fatal(1, "reset mid-BCH launched the KEM");
        run_case(8'h10, TEST_KCV, 1, 1);
        $display("ASIC_TOP_RESET_MID_OK");

        $display("EDGE_ASIC_TOP_PASS");
        $finish;
    end

    initial begin
        repeat (20000) @(posedge clk);
        $fatal(1, "timeout");
    end
endmodule

// Scenario-driven stubs; identical to the tb_edge_phase1 set: the stub PUF
// encodes the FE/KEM scenario in puf_seed and both are consumed by the real
// edge_puf_mlkem_core FSM inside the ASIC boundary top.
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
            busy <= start;
            if (start) begin
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