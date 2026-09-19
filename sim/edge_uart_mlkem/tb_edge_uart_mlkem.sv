`timescale 1ns / 1ps
`default_nettype none

module tb_edge_uart_mlkem;
    localparam integer CLKS = 4;
    `include "helper_record_spec.vh"
    `include "helper_record_kat.vh"
    localparam [191:0] FE_KEY = {
        32'h17161514, 32'h13121110, 32'h0f0e0d0c,
        32'h0b0a0908, 32'h07060504, 32'h03020100
    };

    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0;
    reg uart_rx = 1'b1;
    wire uart_tx;

    wire core_start;
    wire core_zeroize;
    wire core_enroll;
    wire [263:0] helper_in;
    wire peer_req_pk;
    wire peer_ready_c;
    wire stream_in_valid;
    wire [31:0] stream_in_data;
    wire ready_pk;
    wire req_c;
    wire stream_out_valid;
    wire [31:0] stream_out_data;
    wire edge_busy;
    wire edge_done;
    wire scrub_done;
    wire protocol_start;
    wire secret_valid;
    wire [255:0] edge_key;

    wire client_ready_c;
    wire client_req_pk;
    reg client_req_c = 1'b0;
    reg client_start = 1'b0;
    reg client_wen = 1'b0;
    reg [31:0] client_din = 32'b0;
    wire client_valid_out;
    wire [31:0] client_data;
    wire client_done;
    wire [255:0] client_key;
    reg [31:0] ciphertext [0:191];
    reg [31:0] public_key [0:199];
    integer ct_count = 0;
    integer pk_feed_count = 0;

    edge_mlkem_core u_edge (
        .clk(clk), .rst_n(rst_n), .zeroize(core_zeroize),
        .start(core_start), .fe_key(FE_KEY),
        .stream_in_valid(stream_in_valid), .peer_ready_c(peer_ready_c),
        .peer_req_pk(peer_req_pk), .stream_in_data(stream_in_data),
        .ready_pk(ready_pk), .req_c(req_c),
        .stream_out_valid(stream_out_valid),
        .stream_out_data(stream_out_data), .busy(edge_busy),
        .done(edge_done), .scrub_done(scrub_done),
        .protocol_start(protocol_start), .secret_valid(secret_valid),
        .shared_secret(edge_key)
    );

    edge_uart_transport #(
        .CLKS_PER_BIT(CLKS), .PK_WORDS(200), .CT_WORDS(192)
    ) u_transport (
        .clk(clk), .rst_n(rst_n), .uart_rx_i(uart_rx),
        .uart_tx_o(uart_tx), .tx_active(), .core_start(core_start),
        .core_zeroize(core_zeroize), .core_enroll(core_enroll),
        .helper_in(helper_in), .helper_out(264'd0), .core_fe_kcv(224'd0),
        .core_helper_kcv_valid(), .core_helper_kcv(), .core_kcv_ctx(),
        .fe_success(1'b1),
        .core_done(edge_done), .core_busy(edge_busy),
        .ready_pk(ready_pk), .req_c(req_c),
        .stream_out_valid(stream_out_valid),
        .stream_out_data(stream_out_data), .peer_req_pk(peer_req_pk),
        .peer_ready_c(peer_ready_c), .stream_in_valid(stream_in_valid),
        .stream_in_data(stream_in_data), .secret_valid(secret_valid),
        .shared_secret(edge_key)
    );

    // The RTL client models a host peer: first receive and buffer the complete
    // UART public key, then replay it through the native Kyber handshake.
    Kyber_Client u_client (
        .clk(clk), .rst(!rst_n), .scrub_en(1'b0), .scrub_addr(11'd0),
        .start(client_start), .wen(client_wen), .k(3'd2),
        .ready_pk(ready_pk), .req_c(client_req_c),
        .din(client_din), .ready_c(client_ready_c), .req_pk(client_req_pk),
        .valid(), .valid_out(client_valid_out), .dout(client_data),
        .seed_m(256'h00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff),
        .K(client_key), .done(client_done)
    );

    always @(posedge clk) begin
        client_wen <= 1'b0;
        if (!rst_n) begin
            ct_count <= 0;
            pk_feed_count <= 0;
        end else if (client_req_pk && pk_feed_count < 200) begin
            client_din <= public_key[pk_feed_count];
            client_wen <= 1'b1;
            pk_feed_count <= pk_feed_count + 1;
        end else if (client_valid_out && ct_count < 192) begin
            ciphertext[ct_count] <= client_data;
            ct_count <= ct_count + 1;
        end
        if (rst_n && secret_valid)
            $display("SECRET_VALID equal=%b", u_edge.u_server.equal);
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
    initial begin
        repeat (5) @(posedge clk);
        rst_n = 1'b1;

        send_uart(8'h02);
        expect_uart(8'h48);
        for (index = 0; index < HREC_BYTES; index = index + 1)
            send_uart(HREC_KAT_RAW[8*index +: 8]);
        send_uart(8'h78); send_uart(8'h56);
        send_uart(8'h34); send_uart(8'h12);

        expect_uart(8'h50);
        for (index = 0; index < 200; index = index + 1) begin
            recv_uart(public_key[index][7:0]);
            recv_uart(public_key[index][15:8]);
            recv_uart(public_key[index][23:16]);
            recv_uart(public_key[index][31:24]);
        end
        expect_uart(8'h43);

        @(negedge clk);
        client_start = 1'b1;
        @(negedge clk);
        client_start = 1'b0;
        wait (client_ready_c);
        @(negedge clk);
        client_req_c = 1'b1;
        wait (ct_count == 192);
        @(negedge clk);
        client_req_c = 1'b0;
        for (index = 0; index < 192; index = index + 1) begin
            send_uart(ciphertext[index][7:0]);
            send_uart(ciphertext[index][15:8]);
            send_uart(ciphertext[index][23:16]);
            send_uart(ciphertext[index][31:24]);
        end

        expected_tag = 32'h12345678 ^ client_key[31:0] ^
            client_key[63:32] ^ client_key[95:64] ^ client_key[127:96] ^
            client_key[159:128] ^ client_key[191:160] ^
            client_key[223:192] ^ client_key[255:224];
        expect_uart(8'haa);
        expect_uart(expected_tag[7:0]);
        expect_uart(expected_tag[15:8]);
        expect_uart(expected_tag[23:16]);
        expect_uart(expected_tag[31:24]);
        if (u_edge.u_server.equal !== 1'b1)
            $fatal(1, "valid UART ciphertext was rejected");
        $display("EDGE_UART_MLKEM_INTEGRATION_PASS tag=%08x", expected_tag);
        $finish;
    end

    initial begin
        repeat (1000000) @(posedge clk);
        $fatal(1, "timeout transport=%0d server=%02x ct_count=%0d words=%0d ntt=%02x ntt_ctr=%x col=%x kctr=%x df0_full=%b df1_full=%b df1_empty=%b",
               u_transport.state, u_edge.u_server.state, ct_count,
               u_edge.u_server.ciphertext_wr_ctr,
               u_edge.u_server.ntt.state, u_edge.u_server.ntt.ctr_NTT,
               u_edge.u_server.ntt.ctr_col, u_edge.u_server.ntt.ctr_k,
               u_edge.u_server.DFIFO0_full_eff, u_edge.u_server.DFIFO1_full,
               u_edge.u_server.DFIFO1_empty);
    end
endmodule

`default_nettype wire
