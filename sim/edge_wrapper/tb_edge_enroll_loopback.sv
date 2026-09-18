`timescale 1ns / 1ps
`default_nettype none

// End-to-end enrollment loopback for the same-root context binding.
//
// ENROLL emits a record whose KCV is computed by the real SHAKE256 core from
// the transport-provided enroll context.  Feeding that exact record back
// through SESSION must pass the KCV gate and start the KEM exactly once;
// a CRC-valid record with a corrupted KCV or a different context must be
// rejected with no KEM start pulse.  This is the regression test for the
// review finding that the board tops wired enroll_ctx to a context that is
// only latched during SESSION (i.e. zero at enrollment time).
module tb_edge_enroll_loopback;
    localparam integer CLKS = 4;
    `include "helper_record_spec.vh"

    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0;
    reg uart_rx = 1'b1;
    wire uart_tx;

    wire core_start, core_zeroize, core_enroll;
    wire [263:0] helper_in, helper_out;
    wire [223:0] core_fe_kcv;
    wire core_kcv_enable;
    wire [223:0] core_kcv_ref;
    wire [55:0]  core_kcv_ctx;
    wire [55:0]  core_enroll_ctx;
    wire fe_success;
    wire core_done, core_busy;
    wire ready_pk, req_c, stream_out_valid;
    wire [31:0] stream_out_data;
    wire peer_req_pk, peer_ready_c, stream_in_valid;
    wire [31:0] stream_in_data;
    wire secret_valid;
    wire [255:0] shared_secret;
    wire kcv_pass, kcv_fail;
    wire [7:0] bch_corr_bits;
    wire scrub_done, protocol_start;

    integer edge_start_count = 0;
    integer protocol_start_count = 0;
    integer index;
    reg [8*HREC_BYTES-1:0] record;
    reg [8*HREC_BYTES-1:0] bad;
    reg [7:0] drained;
    reg [31:0] expected_tag;

    edge_uart_transport #(
        .CLKS_PER_BIT(CLKS), .PK_WORDS(2), .CT_WORDS(2),
        .ALLOW_ENROLL(1'b1)
    ) u_transport (
        .clk(clk), .rst_n(rst_n), .uart_rx_i(uart_rx),
        .uart_tx_o(uart_tx), .tx_active(),
        .core_start(core_start), .core_zeroize(core_zeroize),
        .core_enroll(core_enroll), .helper_in(helper_in),
        .helper_out(helper_out), .core_fe_kcv(core_fe_kcv),
        .core_kcv_enable(core_kcv_enable), .core_kcv_ref(core_kcv_ref),
        .core_kcv_ctx(core_kcv_ctx), .core_enroll_ctx(core_enroll_ctx),
        .record_status(), .record_fail(), .zeroize_done(),
        .fe_success(fe_success), .core_done(core_done),
        .core_busy(core_busy), .ready_pk(ready_pk), .req_c(req_c),
        .stream_out_valid(stream_out_valid),
        .stream_out_data(stream_out_data), .peer_req_pk(peer_req_pk),
        .peer_ready_c(peer_ready_c), .stream_in_valid(stream_in_valid),
        .stream_in_data(stream_in_data), .secret_valid(secret_valid),
        .shared_secret(shared_secret)
    );

    edge_puf_mlkem_core u_core (
        .clk(clk), .rst_n(rst_n), .zeroize(core_zeroize),
        .start(core_start), .enroll(core_enroll), .puf_seed(8'h5a),
        .helper_in(helper_in), .helper_out(helper_out),
        .fe_success(fe_success),
        .kcv_enable(core_kcv_enable), .kcv_ref(core_kcv_ref),
        .kcv_ctx(core_kcv_ctx), .enroll_ctx(core_enroll_ctx),
        .fe_kcv(core_fe_kcv), .kcv_pass(kcv_pass), .kcv_fail(kcv_fail),
        .bch_corr_bits(bch_corr_bits),
        .stream_in_valid(stream_in_valid),
        .peer_ready_c(peer_ready_c), .peer_req_pk(peer_req_pk),
        .stream_in_data(stream_in_data), .ready_pk(ready_pk), .req_c(req_c),
        .stream_out_valid(stream_out_valid), .stream_out_data(stream_out_data),
        .busy(core_busy), .done(core_done), .scrub_done(scrub_done),
        .protocol_start(protocol_start), .secret_valid(secret_valid),
        .shared_secret(shared_secret)
    );

    always @(posedge clk) begin
        if (rst_n && u_core.edge_start)
            edge_start_count = edge_start_count + 1;
        if (rst_n && protocol_start)
            protocol_start_count = protocol_start_count + 1;
    end

    task automatic send_uart(input [7:0] value);
        integer bit_index;
        begin
            uart_rx = 1'b0;
            repeat (CLKS) @(posedge clk);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                uart_rx = value[bit_index];
                repeat (CLKS) @(posedge clk);
            end
            uart_rx = 1'b1;
            repeat (CLKS) @(posedge clk);
        end
    endtask

    task automatic recv_uart(output [7:0] value);
        integer bit_index;
        begin
            @(negedge uart_tx);
            repeat (CLKS + CLKS/2) @(posedge clk);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                value[bit_index] = uart_tx;
                repeat (CLKS) @(posedge clk);
            end
            repeat (CLKS/2) @(posedge clk);
        end
    endtask

    task automatic expect_uart(input [7:0] expected);
        reg [7:0] received;
        begin
            recv_uart(received);
            if (received !== expected)
                $fatal(1, "UART expected %02x received %02x", expected, received);
        end
    endtask

    task automatic send_record(input [8*HREC_BYTES-1:0] rec);
        begin
            for (index = 0; index < HREC_BYTES; index = index + 1)
                send_uart(rec[8*index +: 8]);
            send_uart(8'h78); send_uart(8'h56);
            send_uart(8'h34); send_uart(8'h12);
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        rst_n = 1'b1;

        // A. ENROLL must publish a CRC-valid record with a nonzero KCV.
        send_uart(8'h01);
        expect_uart(8'haa);
        for (index = 0; index < HREC_BYTES; index = index + 1)
            recv_uart(record[8*index +: 8]);
        if (record[8*0 +: 32] !== HREC_MAGIC)
            $fatal(1, "enroll record magic wrong");
        if (record[8*HREC_OFF_PROFILE +: 8] !== 8'h01 ||
            record[8*HREC_OFF_FE_PARAM +: 8] !== 8'h01 ||
            record[8*HREC_OFF_GENERATION +: 8] !== 8'h01)
            $fatal(1, "enroll record header wrong");
        if (record[8*HREC_OFF_KCV +: 224] === 224'd0)
            $fatal(1, "enroll record KCV is zero");
        if (record[8*HREC_OFF_CRC +: 16] !== hrec_crc16(record))
            $fatal(1, "enroll record CRC wrong");
        if (edge_start_count != 0)
            $fatal(1, "enrollment started the KEM");
        $display("LOOPBACK_ENROLL_RECORD_OK kcv=%056x",
                 record[8*HREC_OFF_KCV +: 224]);

        // B. SESSION with the exact enrolled record must pass the KCV gate
        //    and start the KEM exactly once.
        send_uart(8'h02);
        expect_uart(8'h48);
        send_record(record);
        expect_uart(8'h50);
        // Sample before the post-transaction zeroize scrubs the registered
        // gate decision: edge_start only fires when the KCV matched.
        if (kcv_pass !== 1'b1)
            $fatal(1, "KCV gate did not pass for the enrolled record");
        for (index = 0; index < 8; index = index + 1)
            expect_uart(index[7:0]);
        expect_uart(8'h43);
        for (index = 0; index < 4; index = index + 1)
            send_uart(8'ha0 + index[7:0]);
        for (index = 4; index < 8; index = index + 1)
            send_uart(8'ha0 + index[7:0]);
        // The stub KEM latches shared_secret only after the last ciphertext
        // word is delivered; sample it once the transport reaches the result
        // stage (S_RESULT_SEND = 5'd15) instead of racing the delivery.
        while (u_transport.state !== 5'd15) @(posedge clk);
        expected_tag = 32'h12345678 ^ shared_secret[31:0] ^
            shared_secret[63:32] ^ shared_secret[95:64] ^
            shared_secret[127:96] ^ shared_secret[159:128] ^
            shared_secret[191:160] ^ shared_secret[223:192] ^
            shared_secret[255:224];
        expect_uart(8'haa);
        expect_uart(expected_tag[7:0]);
        expect_uart(expected_tag[15:8]);
        expect_uart(expected_tag[23:16]);
        expect_uart(expected_tag[31:24]);
        repeat (5) @(posedge clk);
        if (edge_start_count != 1)
            $fatal(1, "expected one KEM start, got %0d", edge_start_count);
        if (protocol_start_count != 1)
            $fatal(1, "expected one protocol_start");
        $display("LOOPBACK_RECONSTRUCT_OK edge_start=%0d", edge_start_count);

        // C. CRC-valid record with one corrupted KCV byte: gate must reject,
        //    no KEM start, kcv_fail telemetry set.
        edge_start_count = 0;
        protocol_start_count = 0;
        bad = record;
        bad[8*HREC_OFF_KCV +: 8] = bad[8*HREC_OFF_KCV +: 8] ^ 8'h01;
        bad[8*HREC_OFF_CRC +: 16] = hrec_crc16(bad);
        send_uart(8'h02);
        expect_uart(8'h48);
        send_record(bad);
        expect_uart(8'hff);
        expect_uart(8'h03);
        if (edge_start_count != 0)
            $fatal(1, "corrupted KCV launched the KEM");
        if (protocol_start_count != 0)
            $fatal(1, "corrupted KCV reached protocol_start");
        if (kcv_fail !== 1'b1)
            $fatal(1, "kcv_fail telemetry not asserted");
        $display("LOOPBACK_CORRUPT_KCV_REJECTED_OK");

        // D. CRC-valid record with a different generation (context binding):
        //    the KCV no longer matches the context, gate must reject.
        edge_start_count = 0;
        protocol_start_count = 0;
        bad = record;
        bad[8*HREC_OFF_GENERATION +: 8] = 8'h02;
        bad[8*HREC_OFF_CRC +: 16] = hrec_crc16(bad);
        send_uart(8'h02);
        expect_uart(8'h48);
        send_record(bad);
        expect_uart(8'hff);
        expect_uart(8'h03);
        if (edge_start_count != 0)
            $fatal(1, "wrong context launched the KEM");
        $display("LOOPBACK_WRONG_CONTEXT_REJECTED_OK");

        $display("EDGE_ENROLL_LOOPBACK_PASS");
        $finish;
    end

    initial begin
        repeat (4000000) @(posedge clk);
        $fatal(1, "timeout");
    end
endmodule

// Scenario stubs: the PUF/FE/KEM bodies are stubs, but the KCV SHAKE256 core
// inside edge_puf_mlkem_core is the real RTL under test.
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
                response <= {8{32'h5a3c6e97}};
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
    always @(posedge clk or negedge rst_n or posedge zeroize) begin
        if (!rst_n || zeroize) begin
            helper_out <= 264'd0; key_out <= 192'd0; busy <= 1'b0;
            done <= 1'b0; success <= 1'b0; corr_bit_count <= 8'd0;
        end else begin
            done <= busy;
            busy <= start;
            if (start) begin
                helper_out <= helper_in ^ response_in;
                key_out <= TEST_KEY;
                success <= 1'b1;
                corr_bit_count <= 8'd0;
            end
        end
    end
endmodule

module edge_mlkem_core (
    input wire clk, input wire rst_n, input wire zeroize, input wire start,
    input wire [191:0] fe_key, input wire stream_in_valid,
    input wire peer_ready_c, input wire peer_req_pk,
    input wire [31:0] stream_in_data, output reg ready_pk,
    output reg req_c, output reg stream_out_valid,
    output reg [31:0] stream_out_data, output reg busy, output reg done,
    output wire scrub_done, output wire protocol_start,
    output reg secret_valid, output reg [255:0] shared_secret
);
    localparam [191:0] TEST_KEY =
        192'h0123456789abcdef_fedcba9876543210_a55a5aa5_deadbeef;
    integer pk_index = 0;
    integer ct_index = 0;
    integer delay_count = 0;
    assign scrub_done = done;
    assign protocol_start = start;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || zeroize) begin
            busy <= 1'b0; done <= 1'b0; ready_pk <= 1'b0; req_c <= 1'b0;
            stream_out_valid <= 1'b0; stream_out_data <= 32'd0;
            secret_valid <= 1'b0; shared_secret <= 256'd0;
            pk_index <= 0; ct_index <= 0; delay_count <= 0;
        end else begin
            done <= 1'b0;
            stream_out_valid <= 1'b0;
            secret_valid <= 1'b0;
            if (start) begin
                busy <= 1'b1;
                ready_pk <= 1'b0;
                pk_index <= 0;
                ct_index <= 0;
                delay_count <= 2;
            end else if (delay_count != 0) begin
                delay_count <= delay_count - 1;
                if (delay_count == 1)
                    ready_pk <= 1'b1;
            end else if (peer_req_pk) begin
                stream_out_data <= pk_index == 0 ? 32'h03020100
                                                 : 32'h07060504;
                stream_out_valid <= 1'b1;
                pk_index <= pk_index + 1;
                if (pk_index == 1)
                    ready_pk <= 1'b0;
            end else if (!req_c && peer_ready_c) begin
                req_c <= 1'b1;
            end else if (stream_in_valid) begin
                ct_index <= ct_index + 1;
                if (ct_index == 1) begin
                    req_c <= 1'b0;
                    secret_valid <= 1'b1;
                    done <= 1'b1;
                    busy <= 1'b0;
                    shared_secret <= {64'd0, fe_key} ^ {64'd0, TEST_KEY};
                end
            end
        end
    end
endmodule

`default_nettype wire
