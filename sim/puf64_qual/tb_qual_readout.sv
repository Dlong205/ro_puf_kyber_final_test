`timescale 1ns / 1ps
// R6.1 scratch validation: sniffer capture + transport 0x70 readout.
// DUT: sniffer (QUAL=1) + transport (QUAL_TELEMETRY_ENABLE=1, INFO 0x71).
// Checks: INFO marker, 'Q' mark, header, 8 captured entries, zero tail,
// CRC16, and header survival across zeroize.  Fast UART (CLKS_PER_BIT=16).
module tb_qual_readout;
    localparam integer CPB = 16;
    localparam integer N = 2016;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #5 clk = ~clk;

    // --- sniffer stimulus ---
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
        .NUM_PAIRS(N), .QUALIFICATION_NONRELEASE(1'b1)
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

    // --- transport ---
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
        .DIAGNOSTIC_FAILURE_CODES(1'b1),
        .HREC_MAPPING_TAG(16'h81B5), .HREC_GENERATION(8'h01),
        .LEGACY_HELPER_ENABLE(1'b0), .ALLOW_ENROLL(1'b0),
        .EXTERNAL_RESULT_TAG(1'b1),
        .QUAL_TELEMETRY_ENABLE(1'b1), .QUAL_INFO_MARKER(8'h71)
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

    // --- TB-side UART decoder (DUT TX -> bytes) ---
    wire rx_dv;
    wire [7:0] rx_byte;
    uart_rx #(.CLKS_PER_BIT(CPB)) u_dec (
        .i_Clock(clk), .i_Rst(~rst_n), .i_Rx_Serial(uart_tx_o),
        .o_Rx_DV(rx_dv), .o_Rx_Byte(rx_byte)
    );

    reg [7:0] rx_mem [0:30000];
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

    function automatic [15:0] crc16(input integer n);
        integer i, j;
        reg [15:0] crc;
        begin
            crc = 16'hFFFF;
            for (i = 0; i < n; i = i + 1) begin
                crc = crc ^ (rx_mem[i] << 8);
                for (j = 0; j < 8; j = j + 1)
                    crc = (crc & 16'h8000) ? ((crc << 1) ^ 16'h1021) : (crc << 1);
            end
            crc16 = crc;
        end
    endfunction

    integer i, errors;
    reg [15:0] exp_crc, got_crc;
    initial begin
        errors = 0;
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        repeat (10) @(posedge clk);

        // 1) INFO marker check
        uart_send(8'h00);
        wait (rx_n >= 5);
        if ({rx_mem[0],rx_mem[1],rx_mem[2],rx_mem[3],rx_mem[4]} !==
            {8'h45,8'h41,8'h01,8'h01,8'h71}) begin
            $display("FAIL info tack %h %h %h %h %h", rx_mem[0],rx_mem[1],
                     rx_mem[2],rx_mem[3],rx_mem[4]);
            errors = errors + 1;
        end else $display("PASS info 4541010171");
        rx_n = 0;

        // 2) synthetic sweep: 8 pairs, margins 0,10,...,70
        @(posedge clk); sweep_start = 1'b1;
        @(posedge clk); sweep_start = 1'b0;
        for (i = 0; i < 8; i = i + 1) begin
            @(posedge clk);
            tel_valid = 1'b1; tel_index = i[10:0];
            tel_a = i[5:0]; tel_b = (i+1);
            tel_c0 = 1000 + i*10; tel_c1 = 1000;
            tel_winner = (tel_c0 < tel_c1);
            tel_stable = 1'b1;
        end
        @(posedge clk); tel_valid = 1'b0;
        @(posedge clk); sweep_done = 1'b1;
        @(posedge clk); sweep_done = 1'b0;
        @(posedge clk);
        fe_done = 1'b1; fe_success_in = 1'b1; fe_corr_in = 8'd3;
        @(posedge clk); fe_done = 1'b0;
        @(posedge clk);
        kcv_done = 1'b1; kcv_match_in = 1'b1;
        @(posedge clk); kcv_done = 1'b0;
        repeat (5) @(posedge clk);

        // 3) zeroize must preserve the completed frame
        zeroize = 1'b1; repeat (2) @(posedge clk); zeroize = 1'b0;
        repeat (5) @(posedge clk);

        // 4) readout
        uart_send(8'h70);
        wait (rx_n >= 1 + 10 + N*11 + 2);
        repeat (CPB*4) @(posedge clk);

        if (rx_mem[0] !== 8'h51) begin
            $display("FAIL mark %h", rx_mem[0]); errors = errors + 1;
        end else $display("PASS mark Q");
        // header: seq=1 count=8 bch=3 status=0x0D
        if (rx_mem[1] !== 8'd1 || rx_mem[2] !== 8'd0 ||
            rx_mem[3] !== 8'd0 || rx_mem[4] !== 8'd0) begin
            $display("FAIL seq"); errors = errors + 1;
        end else $display("PASS seq=1");
        if (rx_mem[5] !== 8'd8 || rx_mem[6] !== 8'd0) begin
            $display("FAIL count %h %h", rx_mem[5], rx_mem[6]);
            errors = errors + 1;
        end else $display("PASS count=8");
        if (rx_mem[7] !== 8'd3) begin
            $display("FAIL bch %h", rx_mem[7]); errors = errors + 1;
        end else $display("PASS bch=3");
        if (rx_mem[8] !== 8'h0D) begin
            $display("FAIL status %h (want 0D)", rx_mem[8]);
            errors = errors + 1;
        end else $display("PASS status=0D");
        // entries
        for (i = 0; i < 8; i = i + 1) begin
            integer base;
            reg [31:0] c0, c1;
            base = 11 + i*11;
            c0 = {rx_mem[base+3],rx_mem[base+2],rx_mem[base+1],rx_mem[base]};
            c1 = {rx_mem[base+7],rx_mem[base+6],rx_mem[base+5],rx_mem[base+4]};
            if (c0 !== (1000+i*10) || c1 !== 1000) begin
                $display("FAIL entry %0d c0=%0d c1=%0d", i, c0, c1);
                errors = errors + 1;
            end
            if (rx_mem[base+8] !== (i & 8'h3f) ||
                rx_mem[base+9] !== ((i+1) & 8'h3f)) begin
                $display("FAIL entry %0d a/b %h %h", i, rx_mem[base+8],
                         rx_mem[base+9]);
                errors = errors + 1;
            end
        end
        $display("PASS 8 entries (c0/c1/a/b)");
        // tail must be zero/invalid
        for (i = 8; i < N; i = i + 1) begin
            integer base;
            base = 11 + i*11;
            if (rx_mem[base] !== 8'd0 || rx_mem[base+10] !== 8'd0) begin
                $display("FAIL tail nonzero @%0d", i); errors = errors + 1;
                i = N;
            end
        end
        if (errors == 0) $display("PASS tail zero");
        // CRC over header+body
        exp_crc = crc16(10 + N*11);
        got_crc = {rx_mem[1+10+N*11+1], rx_mem[1+10+N*11]};
        // NOTE: crc16() reads rx_mem[0..n), but stream starts at rx_mem[1]
        $display("INFO crc calc-over-offset handled below");
        // recompute over the right window manually
        begin
            integer k, j;
            reg [15:0] crc;
            crc = 16'hFFFF;
            for (k = 1; k < 1 + 10 + N*11; k = k + 1) begin
                crc = crc ^ (rx_mem[k] << 8);
                for (j = 0; j < 8; j = j + 1)
                    crc = (crc & 16'h8000) ? ((crc << 1) ^ 16'h1021)
                                           : (crc << 1);
            end
            if (crc !== got_crc) begin
                $display("FAIL crc calc=%h rx=%h", crc, got_crc);
                errors = errors + 1;
            end else $display("PASS crc");
        end

        if (errors == 0) $display("QUAL_READOUT_SIM_PASS");
        else $display("QUAL_READOUT_SIM_FAIL errors=%0d", errors);
        $finish;
    end

    // watchdog
    initial begin
        repeat (8000000) @(posedge clk);
        $display("FAIL watchdog timeout rx_n=%0d", rx_n);
        $finish;
    end
endmodule
