`timescale 1ns / 1ps
`default_nettype none

module tb_edge_uart_transport;
    localparam integer CLKS = 4;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0;
    reg uart_rx = 1'b1;
    wire uart_tx;

    wire core_start, core_zeroize, core_enroll;
    wire [263:0] helper_in;
    reg [263:0] helper_out = 264'd0;
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
    reg [255:0] shared_secret = {
        32'h77665544, 32'h33221100, 32'hffeeddcc, 32'hbbaa9988,
        32'h76543210, 32'hfedcba98, 32'h89abcdef, 32'h01234567
    };
    integer pk_index = 0;
    integer ct_index = 0;
    integer delay_count = 0;

    edge_uart_transport #(
        .CLKS_PER_BIT(CLKS), .PK_WORDS(2), .CT_WORDS(2)
    ) dut (
        .clk(clk), .rst_n(rst_n), .uart_rx_i(uart_rx),
        .uart_tx_o(uart_tx), .tx_active(), .core_start(core_start),
        .core_zeroize(core_zeroize), .core_enroll(core_enroll),
        .helper_in(helper_in), .helper_out(helper_out),
        .fe_success(fe_success), .core_done(core_done),
        .core_busy(core_busy), .ready_pk(ready_pk), .req_c(req_c),
        .stream_out_valid(stream_out_valid),
        .stream_out_data(stream_out_data), .peer_req_pk(peer_req_pk),
        .peer_ready_c(peer_ready_c), .stream_in_valid(stream_in_valid),
        .stream_in_data(stream_in_data), .secret_valid(secret_valid),
        .shared_secret(shared_secret)
    );

    always @(posedge clk) begin
        core_done <= 1'b0;
        stream_out_valid <= 1'b0;
        secret_valid <= 1'b0;
        if (core_zeroize) begin
            core_busy <= 1'b0;
            ready_pk <= 1'b0;
            req_c <= 1'b0;
            pk_index <= 0;
            ct_index <= 0;
            delay_count <= 0;
        end else if (core_start) begin
            core_busy <= 1'b1;
            delay_count <= 2;
            if (core_enroll) begin
                helper_out <= {33{8'h00}};
                fe_success <= 1'b1;
            end else begin
                if (helper_in != {
                    8'h20,8'h1f,8'h1e,8'h1d,8'h1c,8'h1b,8'h1a,8'h19,
                    8'h18,8'h17,8'h16,8'h15,8'h14,8'h13,8'h12,8'h11,
                    8'h10,8'h0f,8'h0e,8'h0d,8'h0c,8'h0b,8'h0a,8'h09,
                    8'h08,8'h07,8'h06,8'h05,8'h04,8'h03,8'h02,8'h01,8'h00
                })
                    $fatal(1, "helper context changed byte order");
                ready_pk <= 1'b0;
                pk_index <= 0;
                ct_index <= 0;
            end
        end else if (delay_count != 0) begin
            delay_count <= delay_count - 1;
            if (delay_count == 1) begin
                if (core_enroll) begin
                    helper_out <= {
                        8'h20,8'h1f,8'h1e,8'h1d,8'h1c,8'h1b,8'h1a,8'h19,
                        8'h18,8'h17,8'h16,8'h15,8'h14,8'h13,8'h12,8'h11,
                        8'h10,8'h0f,8'h0e,8'h0d,8'h0c,8'h0b,8'h0a,8'h09,
                        8'h08,8'h07,8'h06,8'h05,8'h04,8'h03,8'h02,8'h01,8'h00
                    };
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
            if (pk_index == 1) begin
                ready_pk <= 1'b0;
            end
        end else if (!req_c && peer_ready_c) begin
            // Match Kyber_Server: enter the receive state only after the
            // peer says the complete ciphertext stream is available.
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
    reg [31:0] expected_tag;
    initial begin
        repeat (5) @(posedge clk);
        rst_n = 1'b1;

        send_uart(8'h00);
        expect_uart(8'h45); expect_uart(8'h41); expect_uart(8'h01);
        expect_uart(8'h00); expect_uart(8'h07);

        send_uart(8'h01);
        expect_uart(8'haa);
        for (index = 0; index < 33; index = index + 1)
            expect_uart(index[7:0]);

        send_uart(8'h02);
        expect_uart(8'h48);
        for (index = 0; index < 33; index = index + 1)
            send_uart(index[7:0]);
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

        expected_tag = 32'h12345678 ^ 32'h01234567 ^ 32'h89abcdef ^
            32'hfedcba98 ^ 32'h76543210 ^ 32'hbbaa9988 ^ 32'hffeeddcc ^
            32'h33221100 ^ 32'h77665544;
        expect_uart(8'haa);
        expect_uart(expected_tag[7:0]); expect_uart(expected_tag[15:8]);
        expect_uart(expected_tag[23:16]); expect_uart(expected_tag[31:24]);
        repeat (5) @(posedge clk);
        if (!core_zeroize && dut.state != 0)
            $fatal(1, "transport did not return idle after zeroize");
        $display("EDGE_UART_TRANSPORT_PASS tag=%08x", expected_tag);
        $finish;
    end
endmodule

`default_nettype wire
