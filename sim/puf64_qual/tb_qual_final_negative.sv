`timescale 1ns / 1ps
// R6.1 scratch validation (final profile): with QUAL_TELEMETRY_ENABLE=0 the
// private command 0x70 must be rejected exactly like any unsupported command
// (FF 01, release 2-byte form), INFO byte4 stays 0x0f, and the sniffer
// readout is all-zero (sim no-leak assertion active).
module tb_qual_final_negative;
    localparam integer CPB = 16;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    reg sweep_start = 1'b0, sweep_done = 1'b0;
    reg tel_valid = 1'b0;
    reg [10:0] tel_index = 11'd0;
    reg [5:0] tel_a = 6'd0, tel_b = 6'd0;
    reg [31:0] tel_c0 = 32'd0, tel_c1 = 32'd0;
    reg tel_stable = 1'b0, tel_timeout = 1'b0;
    reg tel_ovf_a = 1'b0, tel_ovf_b = 1'b0, tel_winner = 1'b0;
    reg fe_done = 1'b0, fe_success_in = 1'b0;
    reg [7:0] fe_corr_in = 8'd0;
    reg kcv_done = 1'b0, kcv_match_in = 1'b0;
    reg zeroize = 1'b0;

    wire [81:0] qual_rd_data;
    wire [31:0] qual_frame_seq;
    wire [11:0] qual_entry_count;
    wire [7:0] qual_hdr_bch_corr, qual_hdr_status;
    wire qual_frame_valid;
    wire qual_rd_en;
    wire [10:0] qual_rd_addr;

    puf64_qual_telemetry_sniffer #(
        .NUM_PAIRS(2016), .QUALIFICATION_NONRELEASE(1'b0)
    ) u_sniff (
        .clk(clk), .rst_n(rst_n), .zeroize(zeroize),
        .sweep_start(sweep_start), .sweep_done(sweep_done),
        .tel_valid(tel_valid), .tel_index(tel_index),
        .tel_a(tel_a), .tel_b(tel_b), .tel_c0(tel_c0), .tel_c1(tel_c1),
        .tel_stable(tel_stable), .tel_timeout(tel_timeout),
        .tel_ovf_a(tel_ovf_a), .tel_ovf_b(tel_ovf_b), .tel_winner(tel_winner),
        .fe_done(fe_done), .fe_success_in(fe_success_in),
        .fe_corr_in(fe_corr_in), .kcv_done(kcv_done),
        .kcv_match_in(kcv_match_in),
        .rd_en(qual_rd_en), .rd_addr(qual_rd_addr), .rd_data(qual_rd_data),
        .frame_seq(qual_frame_seq), .entry_count(qual_entry_count),
        .hdr_bch_corr(qual_hdr_bch_corr), .hdr_status(qual_hdr_status),
        .frame_valid(qual_frame_valid)
    );

    reg uart_rx_i = 1'b1;
    wire uart_tx_o;
    wire tx_active;
    wire core_start, core_zeroize, core_enroll, core_command_ok;
    wire [263:0] helper_in;
    wire core_helper_kcv_valid;
    wire [223:0] core_helper_kcv;
    wire [55:0] core_kcv_ctx, core_enroll_ctx;
    wire [31:0] core_nonce;
    wire [3:0] record_status;
    wire record_fail, zeroize_done, peer_req_pk, stream_in_valid;
    wire [31:0] stream_in_data;
    wire peer_ready_c;

    edge_uart_transport #(
        .CLKS_PER_BIT(CPB), .RX_TIMEOUT(CPB*24),
        .DIAGNOSTIC_FAILURE_CODES(1'b0),
        .HREC_MAPPING_TAG(16'h81B5), .HREC_GENERATION(8'h01),
        .LEGACY_HELPER_ENABLE(1'b0), .ALLOW_ENROLL(1'b0),
        .EXTERNAL_RESULT_TAG(1'b1),
        .QUAL_TELEMETRY_ENABLE(1'b0), .QUAL_INFO_MARKER(8'h0f)
    ) u_tr (
        .clk(clk), .rst_n(rst_n), .uart_rx_i(uart_rx_i),
        .uart_tx_o(uart_tx_o), .tx_active(tx_active),
        .core_start(core_start), .core_zeroize(core_zeroize),
        .core_enroll(core_enroll), .core_command_ok(core_command_ok),
        .helper_in(helper_in), .helper_out(264'd0), .core_fe_kcv(224'd0),
        .core_helper_kcv_valid(core_helper_kcv_valid),
        .core_helper_kcv(core_helper_kcv), .core_kcv_ctx(core_kcv_ctx),
        .core_enroll_ctx(core_enroll_ctx), .core_nonce(core_nonce),
        .record_status(record_status), .record_fail(record_fail),
        .zeroize_done(zeroize_done),
        .fe_success(1'b0), .core_done(1'b0), .core_busy(1'b0),
        .core_mapped_error(1'b0), .core_mapped_error_reason(4'd0),
        .core_bch_corr(8'd0), .core_kcv_fail(1'b0), .core_early_reject(1'b0),
        .ready_pk(1'b0), .req_c(1'b0), .stream_out_valid(1'b0),
        .stream_out_data(32'd0), .peer_req_pk(peer_req_pk),
        .peer_ready_c(peer_ready_c), .stream_in_valid(stream_in_valid),
        .stream_in_data(stream_in_data),
        .secret_valid(1'b0), .shared_secret(256'd0),
        .external_result_valid(1'b0), .external_result_tag(32'd0),
        .qual_rd_data(qual_rd_data), .qual_frame_seq(qual_frame_seq),
        .qual_entry_count(qual_entry_count),
        .qual_hdr_bch_corr(qual_hdr_bch_corr),
        .qual_hdr_status(qual_hdr_status),
        .qual_frame_valid(qual_frame_valid),
        .qual_rd_en(qual_rd_en), .qual_rd_addr(qual_rd_addr)
    );

    wire rx_dv;
    wire [7:0] rx_byte;
    uart_rx #(.CLKS_PER_BIT(CPB)) u_dec (
        .i_Clock(clk), .i_Rst(~rst_n), .i_Rx_Serial(uart_tx_o),
        .o_Rx_DV(rx_dv), .o_Rx_Byte(rx_byte)
    );

    reg [7:0] rx_mem [0:15];
    integer rx_n = 0;
    always @(posedge clk) begin
        if (rx_dv) begin
            rx_mem[rx_n] <= rx_byte;
            rx_n <= rx_n + 1;
        end
    end

    task uart_send(input [7:0] b);
        integer k;
        begin
            uart_rx_i = 1'b0; repeat (CPB) @(posedge clk);
            for (k = 0; k < 8; k = k + 1) begin
                uart_rx_i = b[k]; repeat (CPB) @(posedge clk);
            end
            uart_rx_i = 1'b1; repeat (CPB) @(posedge clk);
            repeat (CPB*2) @(posedge clk);
        end
    endtask

    integer errors;
    initial begin
        errors = 0;
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        repeat (10) @(posedge clk);

        // frame passes through the sniffer (capture runs in final too)
        @(posedge clk); sweep_start = 1'b1;
        @(posedge clk); sweep_start = 1'b0;
        @(posedge clk);
        tel_valid = 1'b1; tel_index = 11'd5; tel_c0 = 32'd500;
        tel_c1 = 32'd520; tel_stable = 1'b1;
        @(posedge clk); tel_valid = 1'b0;
        @(posedge clk); sweep_done = 1'b1;
        @(posedge clk); sweep_done = 1'b0;
        repeat (5) @(posedge clk);

        // readout must be zero despite captured data
        if (qual_rd_data !== 82'd0 || qual_frame_seq !== 32'd0 ||
            qual_hdr_status !== 8'd0 || qual_frame_valid !== 1'b0) begin
            $display("FAIL final readout nonzero %h %h %h", qual_rd_data,
                     qual_frame_seq, qual_hdr_status);
            errors = errors + 1;
        end else $display("PASS final readout zero");

        // INFO release form
        uart_send(8'h00);
        wait (rx_n >= 5);
        if ({rx_mem[0],rx_mem[1],rx_mem[2],rx_mem[3],rx_mem[4]} !==
            {8'h45,8'h41,8'h01,8'h01,8'h0f}) begin
            $display("FAIL info"); errors = errors + 1;
        end else $display("PASS info 454101010f");
        rx_n = 0;

        // 0x70 rejected like any unsupported command
        uart_send(8'h70);
        wait (rx_n >= 2);
        repeat (CPB*4) @(posedge clk);
        if (rx_mem[0] !== 8'hff || rx_mem[1] !== 8'h01 || rx_n !== 2) begin
            $display("FAIL 0x70 resp %h %h n=%0d", rx_mem[0], rx_mem[1], rx_n);
            errors = errors + 1;
        end else $display("PASS 0x70 rejected FF 01 (2 bytes)");

        if (errors == 0) $display("QUAL_FINAL_NEGATIVE_SIM_PASS");
        else $display("QUAL_FINAL_NEGATIVE_SIM_FAIL errors=%0d", errors);
        $finish;
    end

    initial begin
        repeat (500000) @(posedge clk);
        $display("FAIL watchdog timeout");
        $finish;
    end
endmodule
