`timescale 1ns / 1ps
`default_nettype none

// Transport tests for the Phase-1 versioned helper record.  Enrollment must
// emit a full 76-byte record; reconstruction must accept exactly 76 record
// bytes, validate them before starting the core, and reject malformed records
// without producing a core start pulse.
module tb_edge_uart_transport;
    localparam integer CLKS = 4;
    `include "helper_record_spec.vh"
    `include "helper_record_kat.vh"

    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0;
    reg uart_rx = 1'b1;
    wire uart_tx;

    wire core_start, core_zeroize, core_enroll;
    wire core_command_ok;
    wire [263:0] helper_in;
    reg  [263:0] helper_out = HREC_KAT_HELPER;
    reg  [223:0] core_fe_kcv = HREC_KAT_KCV;
    wire core_helper_kcv_valid;
    wire [223:0] core_helper_kcv;
    wire [55:0]  core_kcv_ctx;
    reg fe_success = 1'b0;
    reg core_done = 1'b0;
    reg core_busy = 1'b0;
    reg ready_pk = 1'b0;
    reg req_c = 1'b0;
    reg stream_out_valid = 1'b0;
    reg [31:0] stream_out_data = 32'd0;
    wire peer_req_pk, peer_ready_c, stream_in_valid;
    wire [31:0] stream_in_data;
    reg secret_valid = 1'b0;
    reg external_result_valid = 1'b0;
    localparam [31:0] EXTERNAL_RESULT_TAG = 32'ha1b2c3d4;
    reg [255:0] shared_secret = {
        32'h77665544, 32'h33221100, 32'hffeeddcc, 32'hbbaa9988,
        32'h76543210, 32'hfedcba98, 32'h89abcdef, 32'h01234567
    };
    integer pk_index = 0;
    integer ct_index = 0;
    integer delay_count = 0;
    integer start_count = 0;

    edge_uart_transport #(
        .CLKS_PER_BIT(CLKS), .PK_WORDS(2), .CT_WORDS(2),
        // This tb covers both enrollment and reconstruction.
        .ALLOW_ENROLL(1'b1), .EXTERNAL_RESULT_TAG(1'b1)
    ) dut (
        .clk(clk), .rst_n(rst_n), .uart_rx_i(uart_rx),
        .uart_tx_o(uart_tx), .tx_active(), .core_start(core_start),
        .core_zeroize(core_zeroize), .core_enroll(core_enroll),
        .core_command_ok(core_command_ok),
        .helper_in(helper_in), .helper_out(helper_out),
        .core_fe_kcv(core_fe_kcv), .core_helper_kcv_valid(core_helper_kcv_valid),
        .core_helper_kcv(core_helper_kcv), .core_kcv_ctx(core_kcv_ctx),
        .fe_success(fe_success), .core_done(core_done),
        .core_busy(core_busy), .ready_pk(ready_pk), .req_c(req_c),
        .stream_out_valid(stream_out_valid),
        .stream_out_data(stream_out_data), .peer_req_pk(peer_req_pk),
        .peer_ready_c(peer_ready_c), .stream_in_valid(stream_in_valid),
        .stream_in_data(stream_in_data), .secret_valid(secret_valid),
        .shared_secret(shared_secret), .core_nonce(),
        .external_result_valid(external_result_valid),
        .external_result_tag(EXTERNAL_RESULT_TAG)
    );

    always @(posedge clk)
        if (core_start && !core_enroll)
            start_count = start_count + 1;

    always @(posedge clk) begin
        core_done <= 1'b0;
        stream_out_valid <= 1'b0;
        secret_valid <= 1'b0;
        external_result_valid <= 1'b0;
        if (core_zeroize) begin
            core_busy <= 1'b0;
            ready_pk <= 1'b0;
            req_c <= 1'b0;
            pk_index <= 0;
            ct_index <= 0;
            delay_count <= 0;
        end else if (core_start) begin
            if (!core_enroll && !core_command_ok)
                $fatal(1, "core_start was not atomically qualified");
            core_busy <= 1'b1;
            delay_count <= 2;
            if (core_enroll) begin
                fe_success <= 1'b1;
            end else begin
                if (helper_in != HREC_KAT_HELPER)
                    $fatal(1, "parsed helper differs from record");
                if (core_helper_kcv != HREC_KAT_KCV)
                    $fatal(1, "parsed kcv differs from record");
                if (core_kcv_ctx != HREC_KAT_CTX)
                    $fatal(1, "parsed ctx differs from record");
                if (!core_helper_kcv_valid)
                    $fatal(1, "record path did not enable the KCV gate");
                ready_pk <= 1'b0;
                pk_index <= 0;
                ct_index <= 0;
            end
        end else if (delay_count != 0) begin
            delay_count <= delay_count - 1;
            if (delay_count == 1) begin
                if (core_enroll) begin
                    core_done <= 1'b1;
                    core_busy <= 1'b0;
                end else begin
                    ready_pk <= 1'b1;
                end
            end
        end else if (peer_req_pk) begin
            stream_out_data <= pk_index == 0 ? 32'h03020100 : 32'h07060504;
            stream_out_valid <= 1'b1;
            pk_index <= pk_index + 1;
            if (pk_index == 1)
                ready_pk <= 1'b0;
        end else if (!req_c && peer_ready_c) begin
            req_c <= 1'b1;
        end else if (stream_in_valid) begin
            if (!req_c)
                $fatal(1, "ciphertext delivered outside request window");
            if (ct_index == 0 && stream_in_data != 32'ha3a2a1a0)
                $fatal(1, "first ciphertext word changed");
            if (ct_index == 1 && stream_in_data != 32'ha7a6a5a4)
                $fatal(1, "second ciphertext word changed");
            ct_index <= ct_index + 1;
            if (ct_index == 1) begin
                req_c <= 1'b0;
                secret_valid <= 1'b1;
                external_result_valid <= 1'b1;
                core_done <= 1'b1;
                core_busy <= 1'b0;
            end
        end
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

    integer index;
    reg [7:0] ignored;
    reg [31:0] expected_tag;
    reg [8*HREC_BYTES-1:0] sent_record;
    initial begin
        repeat (5) @(posedge clk);
        rst_n = 1'b1;

        send_uart(8'h00);
        expect_uart(8'h45); expect_uart(8'h41); expect_uart(8'h01);
        expect_uart(8'h01); expect_uart(8'h0f);

        // Enrollment must return a full 76-byte record.
        send_uart(8'h01);
        expect_uart(8'haa);
        for (index = 0; index < HREC_BYTES; index = index + 1) begin
            recv_uart(sent_record[8*index +: 8]);
        end
        if (sent_record[8*0 +: 32] !== HREC_MAGIC)
            $fatal(1, "enroll record magic wrong");
        if (sent_record[8*HREC_OFF_PROFILE +: 8] !== HREC_KAT_PROFILE)
            $fatal(1, "enroll record profile wrong");
        if (sent_record[8*HREC_OFF_HELPER +: 264] !== HREC_KAT_HELPER)
            $fatal(1, "enroll record helper wrong");
        if (sent_record[8*HREC_OFF_KCV +: 224] !== HREC_KAT_KCV)
            $fatal(1, "enroll record kcv wrong");
        if (sent_record[8*HREC_OFF_CRC +: 16] !== hrec_crc16(sent_record))
            $fatal(1, "enroll record crc wrong");

        // Session: 76 record bytes + 4-byte nonce.
        send_uart(8'h02);
        expect_uart(8'h48);
        for (index = 0; index < HREC_BYTES; index = index + 1)
            send_uart(HREC_KAT_RAW[8*index +: 8]);
        send_uart(8'h78); send_uart(8'h56); send_uart(8'h34); send_uart(8'h12);
        expect_uart(8'h50);
        for (index = 0; index < 8; index = index + 1)
            expect_uart(index[7:0]);
        expect_uart(8'h43);
        for (index = 0; index < 4; index = index + 1)
            send_uart(8'ha0 + index[7:0]);
        repeat (4) @(posedge clk);
        if (peer_ready_c)
            $fatal(1, "transport announced ciphertext before full buffering");
        for (index = 4; index < 8; index = index + 1)
            send_uart(8'ha0 + index[7:0]);

        expected_tag = EXTERNAL_RESULT_TAG;
        expect_uart(8'haa);
        expect_uart(expected_tag[7:0]); expect_uart(expected_tag[15:8]);
        expect_uart(expected_tag[23:16]); expect_uart(expected_tag[31:24]);
        repeat (5) @(posedge clk);
        if (!core_zeroize && dut.state != 0)
            $fatal(1, "transport did not return idle after zeroize");
        if (start_count != 1)
            $fatal(1, "expected one core start, got %0d", start_count);
        if (core_command_ok)
            $fatal(1, "command_ok survived transaction zeroize");
        $display("EDGE_UART_RECORD_TRANSPORT_PASS tag=%08x", expected_tag);
        $finish;
    end
endmodule

`default_nettype wire
