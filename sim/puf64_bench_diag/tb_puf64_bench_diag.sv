`timescale 1ns / 1ps

module tb_puf64_bench_diag;
    localparam integer N = 4;
    localparam integer REF = 1023;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst_n = 1'b0;
    reg rx_dv = 1'b0;
    reg [7:0] rx_byte = 8'h00;
    reg tx_ready = 1'b0;
    wire tx_valid;
    wire [7:0] tx_data;
    reg mmcm_locked = 1'b1;
    wire bench_start;
    reg bench_done = 1'b0;
    reg tel_valid = 1'b0;
    reg tel_stable = 1'b1;
    reg tel_timeout = 1'b0;
    reg [1:0] tel_a = 2'd0;
    reg [1:0] tel_b = 2'd1;
    reg [31:0] tel_c0 = 32'd0;
    reg [31:0] tel_c1 = 32'd0;

    reg [7:0] rxbuf [0:255];
    integer rxn = 0;
    integer failures = 0;
    integer i;

    puf64_bench_diag #(
        .NUM_RO(N), .REF_CYCLES(REF),
        .BUILD_ID(16'h002A), .TOPOLOGY_ID(16'hC0DE)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .rx_dv(rx_dv), .rx_byte(rx_byte),
        .tx_ready(tx_ready), .tx_valid(tx_valid), .tx_data(tx_data),
        .mmcm_locked(mmcm_locked),
        .bench_start(bench_start), .bench_done(bench_done),
        .telemetry_valid(tel_valid), .telemetry_stable(tel_stable),
        .telemetry_timeout(tel_timeout),
        .telemetry_pair_a(tel_a), .telemetry_pair_b(tel_b),
        .telemetry_count0(tel_c0), .telemetry_count1(tel_c1)
    );

    // Pseudo-random backpressure (reproducible LFSR).
    reg [7:0] lfsr = 8'hA5;
    always @(posedge clk) begin
        lfsr <= {lfsr[6:0], lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3]};
        tx_ready <= lfsr[0];
    end

    always @(posedge clk) begin
        if (tx_valid && tx_ready) begin
            rxbuf[rxn] = tx_data;
            rxn = rxn + 1;
        end
    end

    task automatic send_byte(input [7:0] value);
        begin
            @(posedge clk);
            rx_byte = value;
            rx_dv = 1'b1;
            @(posedge clk);
            rx_dv = 1'b0;
            repeat ((lfsr % 4) + 1) @(posedge clk);
        end
    endtask

    task automatic expect_len(input integer n, input string label);
        integer target;
        begin
            target = n;
            while (rxn < target) @(posedge clk);
            if (rxn != target) begin
                failures = failures + 1;
                $display("FAIL %0s extra bytes", label);
            end
        end
    endtask

    task automatic check_byte(input integer off, input [7:0] want,
                              input string label);
        begin
            if (rxbuf[off] !== want) begin
                failures = failures + 1;
                $display("FAIL %0s off=%0d got=%02x exp=%02x",
                         label, off, rxbuf[off], want);
            end
        end
    endtask

    // Bench telemetry model: disjoint pairs (0,1),(2,3).
    reg timeout_mode = 1'b0;
    reg [3:0] bstate = 4'd0;
    integer bi = 0;
    integer bdelay = 0;
    always @(posedge clk) begin
        case (bstate)
            4'd0: begin
                if (bench_start) begin
                    bi <= 0;
                    bdelay <= 0;
                    bstate <= 4'd4;
                end
            end
            4'd4: begin
                if (bdelay == 200) bstate <= 4'd1;
                else bdelay <= bdelay + 1;
            end
            4'd1: begin
                tel_valid <= 1'b1;
                tel_a <= bi[1:0];
                tel_b <= (bi + 1);
                tel_c0 <= 32'd1000 + bi * 7;
                tel_c1 <= 32'd1000 + (bi + 1) * 7;
                tel_stable <= timeout_mode ? 1'b0 : 1'b1;
                tel_timeout <= timeout_mode;
                bstate <= 4'd2;
            end
            4'd2: begin
                tel_valid <= 1'b0;
                if (bi + 2 >= N) begin
                    bench_done <= 1'b1;
                    bstate <= 4'd3;
                end else begin
                    bi <= bi + 2;
                    bstate <= 4'd1;
                end
            end
            4'd3: begin
                bench_done <= 1'b0;
                bstate <= 4'd0;
            end
            default: bstate <= 4'd0;
        endcase
    end

    initial begin
        rst_n = 1'b0;
        repeat (8) @(posedge clk);
        rst_n = 1'b1;
        repeat (4) @(posedge clk);

        // INFO
        rxn = 0;
        send_byte(8'h00);
        expect_len(21, "INFO");
        check_byte(0, 8'h50, "INFO"); check_byte(1, 8'h55, "INFO");
        check_byte(2, 8'h46, "INFO"); check_byte(3, 8'hD1, "INFO");
        check_byte(4, 8'h2A, "INFO"); check_byte(6, 8'h04, "INFO");
        check_byte(9, REF[7:0], "INFO"); check_byte(10, REF[15:8], "INFO");
        check_byte(11, 8'h01, "INFO"); check_byte(20, 8'h01, "INFO");

        // RUN -> busy -> done
        rxn = 0;
        send_byte(8'h01);
        repeat (2) @(posedge clk);
        send_byte(8'h02);
        expect_len(4 + 1, "STATUS_BUSY");  // A5 busy done err + 1 bitmap byte
        check_byte(0, 8'hA5, "STATUS"); check_byte(1, 8'h01, "STATUS busy");
        while (dut.run_done !== 1'b1) @(posedge clk);
        rxn = 0;
        send_byte(8'h02);
        expect_len(4 + 1, "STATUS_DONE");
        check_byte(1, 8'h00, "STATUS not busy");
        check_byte(2, 8'h01, "STATUS done");
        check_byte(3, 8'h00, "STATUS err");
        check_byte(4, 8'h0F, "STATUS bitmap");

        // READ every index once
        for (i = 0; i < N; i = i + 1) begin
            rxn = 0;
            send_byte(8'h03);
            send_byte(i[7:0]);
            expect_len(22, "READ");
            check_byte(0, 8'hA6, "READ"); check_byte(1, 8'hD1, "READ");
            check_byte(7, i[7:0], "READ idx");
            check_byte(8, 8'(1000 + i * 7), "READ count_lo");
            check_byte(9, 8'((1000 + i * 7) >> 8), "READ count_hi");
            if (rxbuf[10][0] !== 1'b1 || rxbuf[10][1] !== 1'b1) begin
                failures = failures + 1;
                $display("FAIL READ flags idx=%0d got=%02x", i, rxbuf[10]);
            end
        end

        // READ duplicate
        rxn = 0; send_byte(8'h03); send_byte(8'd1);
        expect_len(22, "READ_DUP");
        check_byte(7, 8'd1, "READ_DUP idx");
        check_byte(8, 8'(1000 + 7), "READ_DUP count");

        // READ out of range
        rxn = 0; send_byte(8'h03); send_byte(8'd4);
        expect_len(2, "READ_RANGE");
        check_byte(0, 8'hFF, "RANGE"); check_byte(1, 8'hE3, "RANGE code");

        // RUN while busy -> E1
        rxn = 0; send_byte(8'h01);
        repeat (2) @(posedge clk);
        rxn = 0; send_byte(8'h01);
        expect_len(2, "RUN_BUSY");
        check_byte(1, 8'hE1, "RUN_BUSY code");
        // abort then wait idle
        send_byte(8'h04);
        while (dut.run_busy === 1'b1) @(posedge clk);

        // Second RUN clears old data: start run, READ before done -> E2
        rxn = 0; send_byte(8'h01);
        repeat (2) @(posedge clk);
        rxn = 0; send_byte(8'h03); send_byte(8'd0);
        expect_len(2, "READ_EARLY");
        check_byte(1, 8'hE2, "READ_EARLY code");

        // timeout propagation
        timeout_mode = 1'b1;
        while (dut.run_busy === 1'b1) @(posedge clk);
        while (dut.run_done !== 1'b1) @(posedge clk);
        rxn = 0; send_byte(8'h03); send_byte(8'd0);
        expect_len(22, "READ_TIMEOUT");
        if (rxbuf[10][2] !== 1'b1) begin
            failures = failures + 1;
            $display("FAIL timeout flag not propagated: %02x", rxbuf[10]);
        end
        timeout_mode = 1'b0;

        // reset mid-TX and mid-run
        rxn = 0; send_byte(8'h00);
        repeat (2) @(posedge clk);
        rst_n = 1'b0; repeat (4) @(posedge clk); rst_n = 1'b1;
        repeat (4) @(posedge clk);
        if (tx_valid !== 1'b0) begin
            failures = failures + 1;
            $display("FAIL tx_valid after reset");
        end

        if (failures) begin
            $fatal(1, "%0d diagnostic endpoint checks failed", failures);
        end
        $display("ALL PUF64 BENCH DIAG TESTS PASSED");
        $finish;
    end

    initial begin
        #2000000;
        $fatal(1, "diagnostic TB timeout");
    end
endmodule
