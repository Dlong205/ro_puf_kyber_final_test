`timescale 1ns / 1ps
`default_nettype none

// Negative/framing tests for the versioned helper-record transport:
//   * operational lifecycle (ALLOW_ENROLL=0) rejects CMD_ENROLL
//   * bad CRC is rejected with the record error code
//   * a truncated record times out fail-closed
//   * a trailing byte after the nonce is rejected
//   * the record buffer is scrubbed after every failure
module tb_edge_uart_negative;
    localparam integer CLKS = 4;
    `include "helper_record_spec.vh"
    `include "helper_record_kat.vh"

    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0;
    reg uart_rx = 1'b1;
    wire uart_tx;

    wire core_start, core_zeroize, core_enroll;
    wire [263:0] helper_in;
    reg  [263:0] helper_out = HREC_KAT_HELPER;
    reg  [223:0] core_fe_kcv = HREC_KAT_KCV;
    wire core_kcv_enable;
    wire [223:0] core_kcv_ref;
    wire [55:0]  core_kcv_ctx;
    wire [3:0]   record_status;
    wire         record_fail;
    wire         zeroize_done;
    reg fe_success = 1'b1;
    reg core_done = 1'b0;
    reg core_busy = 1'b0;
    reg ready_pk = 1'b0;
    reg req_c = 1'b0;
    reg stream_out_valid = 1'b0;
    reg [31:0] stream_out_data = 32'd0;
    wire peer_req_pk, peer_ready_c, stream_in_valid;
    wire [31:0] stream_in_data;
    reg secret_valid = 1'b0;
    reg [255:0] shared_secret = 256'd0;
    integer start_count = 0;

    // Operational lifecycle: enrollment must be refused.
    edge_uart_transport #(
        .CLKS_PER_BIT(CLKS), .PK_WORDS(2), .CT_WORDS(2),
        .ALLOW_ENROLL(1'b0)
    ) dut (
        .clk(clk), .rst_n(rst_n), .uart_rx_i(uart_rx),
        .uart_tx_o(uart_tx), .tx_active(), .core_start(core_start),
        .core_zeroize(core_zeroize), .core_enroll(core_enroll),
        .helper_in(helper_in), .helper_out(helper_out),
        .core_fe_kcv(core_fe_kcv), .core_kcv_enable(core_kcv_enable),
        .core_kcv_ref(core_kcv_ref), .core_kcv_ctx(core_kcv_ctx),
        .record_status(record_status), .record_fail(record_fail),
        .zeroize_done(zeroize_done),
        .fe_success(fe_success), .core_done(core_done),
        .core_busy(core_busy), .ready_pk(ready_pk), .req_c(req_c),
        .stream_out_valid(stream_out_valid),
        .stream_out_data(stream_out_data), .peer_req_pk(peer_req_pk),
        .peer_ready_c(peer_ready_c), .stream_in_valid(stream_in_valid),
        .stream_in_data(stream_in_data), .secret_valid(secret_valid),
        .shared_secret(shared_secret)
    );

    always @(posedge clk)
        if (core_start)
            start_count = start_count + 1;

    // Capture the bytes the transport launches (white-box, avoids the
    // receive-side race when a fail byte is sent immediately after the
    // record's last byte).
    reg [7:0] tx_log [0:15];
    integer tx_log_n = 0;
    always @(posedge clk)
        if (dut.tx_dv) begin
            tx_log[tx_log_n] = dut.tx_byte;
            tx_log_n = tx_log_n + 1;
        end

    task automatic check_fail(input [7:0] code, input [127:0] name);
        integer guard;
        begin
            guard = 0;
            while (tx_log_n < 2 && guard < 20000) begin
                @(posedge clk);
                guard = guard + 1;
            end
            if (tx_log_n < 2)
                $fatal(1, "%0s: no fail bytes transmitted", name);
            if (tx_log[0] !== 8'hff || tx_log[1] !== code)
                $fatal(1, "%0s: fail bytes %02x %02x expected ff %02x",
                       name, tx_log[0], tx_log[1], code);
            if (start_count != 0)
                $fatal(1, "%0s: core was started", name);
            // Let the transport finish zeroize and return to idle before the
            // next command is issued.
            guard = 0;
            while (dut.state != 5'd0 && guard < 20000) begin
                @(posedge clk);
                guard = guard + 1;
            end
            if (dut.state != 5'd0)
                $fatal(1, "%0s: transport did not return idle", name);
        end
    endtask

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
    initial begin
        repeat (5) @(posedge clk);
        rst_n = 1'b1;

        // A. Enrollment is forbidden in the operational lifecycle.
        tx_log_n = 0;
        send_uart(8'h01);
        check_fail(8'h01, "enroll");
        $display("NEG_ENROLL_REJECTED_OK");

        // B. Record with bad CRC is rejected before any core start.
        tx_log_n = 0;
        send_uart(8'h02);
        expect_uart(8'h48);
        tx_log_n = 0;
        for (index = 0; index < HREC_BYTES; index = index + 1)
            send_uart(index == HREC_OFF_CRC ? (HREC_KAT_RAW[8*index +: 8] ^ 8'h01)
                                            : HREC_KAT_RAW[8*index +: 8]);
        check_fail({4'h0, HREC_ERR_CRC}, "badcrc");
        if (record_status != HREC_ERR_CRC || !record_fail)
            $fatal(1, "record telemetry not latched");
        $display("NEG_BAD_CRC_OK");

        // C. Truncated record must time out fail-closed.
        tx_log_n = 0;
        send_uart(8'h02);
        expect_uart(8'h48);
        tx_log_n = 0;
        for (index = 0; index < 40; index = index + 1)
            send_uart(HREC_KAT_RAW[8*index +: 8]);
        check_fail(8'hf0, "truncated");
        $display("NEG_TRUNCATED_OK");

        // D. A trailing byte after the nonce is a framing error.
        tx_log_n = 0;
        send_uart(8'h02);
        expect_uart(8'h48);
        tx_log_n = 0;
        for (index = 0; index < HREC_BYTES; index = index + 1)
            send_uart(HREC_KAT_RAW[8*index +: 8]);
        send_uart(8'h78); send_uart(8'h56); send_uart(8'h34); send_uart(8'h12);
        // Extra byte inside the post-record guard window.
        send_uart(8'he5);
        check_fail(8'hf1, "trailing");
        $display("NEG_TRAILING_OK");

        // E. Record buffer scrubbed after failures.
        repeat (5) @(posedge clk);
        if (dut.record_raw !== {(8*HREC_BYTES){1'b0}})
            $fatal(1, "record buffer not scrubbed");
        $display("NEG_RECORD_SCRUB_OK");

        $display("EDGE_UART_NEGATIVE_PASS");
        $finish;
    end

    initial begin
        repeat (200000) @(posedge clk);
        $fatal(1, "timeout");
    end
endmodule

`default_nettype wire
