`timescale 1ns / 1ps

// C1-C4 diagnostic bench board wrapper (thin): MMCM 100 MHz + puf64_ro_bench +
// diagnostic endpoint + UART PHY.  FPGA primitives are confined to this file.
module Puf64_Ro_Bench_Zynq_Top #(
    parameter integer NUM_RO = 4,
    parameter integer REF_CYCLES = 1023,
    parameter integer UART_CLKS_PER_BIT = 868
)(
    input  wire       CLK50MHZ,
    input  wire [1:0] SW,
    input  wire       UART_RXD,
    output wire       UART_TXD,
    output wire [1:0] LED
);
    localparam integer NUM_RO_LOCAL = NUM_RO;
    localparam integer WIDTH = 16;
    localparam integer PAIR_COUNT = (NUM_RO * (NUM_RO - 1)) / 2;
    localparam integer RO_BITS = (NUM_RO <= 1) ? 1 : $clog2(NUM_RO);
    localparam integer IDX_W = (PAIR_COUNT <= 1) ? 1 : $clog2(PAIR_COUNT);
    localparam integer INPUT_CLOCK_HZ = 50000000;
    localparam integer SYSTEM_CLOCK_HZ = 100000000;

    wire clk_in = CLK50MHZ;
    wire clk_sys_pre;
    wire clk_sys;
    wire mmcm_locked;
    wire mmcm_fb;

    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKFBOUT_MULT_F(20.0),
        .CLKFBOUT_PHASE(0.0),
        .CLKIN1_PERIOD(20.0),
        .CLKOUT0_DIVIDE_F(10.0),
        .CLKOUT0_DUTY_CYCLE(0.5),
        .CLKOUT0_PHASE(0.0),
        .DIVCLK_DIVIDE(1),
        .REF_JITTER1(0.0),
        .STARTUP_WAIT("FALSE")
    ) mmcm_i (
        .CLKOUT0(clk_sys_pre),
        .CLKFBOUT(mmcm_fb),
        .CLKFBIN(mmcm_fb),
        .CLKIN1(clk_in),
        .PWRDWN(1'b0),
        .RST(1'b0),
        .LOCKED(mmcm_locked)
    );

    BUFG bufg_sys (
        .I(clk_sys_pre),
        .O(clk_sys)
    );

    reg [15:0] por_cnt = 16'd0;
    reg por_done = 1'b0;
    always @(posedge clk_sys) begin
        if (!mmcm_locked) begin
            por_cnt <= 16'd0;
            por_done <= 1'b0;
        end else if (!por_done) begin
            por_cnt <= por_cnt + 1'b1;
            if (por_cnt == 16'hFFFF)
                por_done <= 1'b1;
        end
    end

    wire bench_start;
    wire bench_busy, bench_done;
    wire [PAIR_COUNT-1:0] bench_response;
    wire tel_valid, tel_stable, tel_timeout;
    wire [IDX_W-1:0] tel_index;
    wire [RO_BITS-1:0] tel_a, tel_b;
    wire [31:0] tel_c0, tel_c1;
    wire bench_winner;

    puf64_ro_bench #(
        .NUM_RO(NUM_RO_LOCAL), .WIDTH(WIDTH), .REF_CYCLES(REF_CYCLES)
    ) u_bench (
        .clk(clk_sys), .rst_n(por_done), .zeroize(1'b0), .start(bench_start),
        .busy(bench_busy), .done(bench_done), .response(bench_response),
        .telemetry_valid(tel_valid), .telemetry_stable(tel_stable),
        .telemetry_timeout(tel_timeout), .telemetry_index(tel_index),
        .telemetry_pair_a(tel_a), .telemetry_pair_b(tel_b),
        .telemetry_count0(tel_c0), .telemetry_count1(tel_c1),
        .telemetry_winner(bench_winner)
    );

    wire rx_dv;
    wire [7:0] rx_byte;
    uart_rx #(.CLKS_PER_BIT(UART_CLKS_PER_BIT)) u_rx (
        .i_Clock(clk_sys), .i_Rst(~por_done), .i_Rx_Serial(UART_RXD),
        .o_Rx_DV(rx_dv), .o_Rx_Byte(rx_byte)
    );

    wire tx_active, tx_done;
    wire ep_tx_valid;
    wire [7:0] ep_tx_data;
    wire ep_tx_ready = ~tx_active;
    reg tx_dv;
    reg [7:0] tx_byte;
    uart_tx #(.CLKS_PER_BIT(UART_CLKS_PER_BIT)) u_tx (
        .i_Clock(clk_sys), .i_Rst(~por_done),
        .i_Tx_DV(tx_dv), .i_Tx_Byte(tx_byte),
        .o_Tx_Active(tx_active), .o_Tx_Serial(UART_TXD), .o_Tx_Done(tx_done)
    );
    always @(posedge clk_sys) begin
        tx_dv <= 1'b0;
        if (ep_tx_valid && ep_tx_ready) begin
            tx_dv <= 1'b1;
            tx_byte <= ep_tx_data;
        end
    end

    puf64_bench_diag #(
        .NUM_RO(NUM_RO_LOCAL), .REF_CYCLES(REF_CYCLES),
        .INPUT_CLOCK_HZ(INPUT_CLOCK_HZ), .SYSTEM_CLOCK_HZ(SYSTEM_CLOCK_HZ),
        .BUILD_ID(16'h0001), .TOPOLOGY_ID(16'hC0DE)
    ) u_diag (
        .clk(clk_sys), .rst_n(por_done),
        .rx_dv(rx_dv), .rx_byte(rx_byte),
        .tx_ready(ep_tx_ready), .tx_valid(ep_tx_valid), .tx_data(ep_tx_data),
        .mmcm_locked(mmcm_locked),
        .bench_start(bench_start), .bench_done(bench_done),
        .telemetry_valid(tel_valid), .telemetry_stable(tel_stable),
        .telemetry_timeout(tel_timeout),
        .telemetry_pair_a(tel_a), .telemetry_pair_b(tel_b),
        .telemetry_count0(tel_c0), .telemetry_count1(tel_c1)
    );

    assign LED[0] = tx_active;
    assign LED[1] = bench_busy;
    wire unused_sw = &SW;
    wire unused_resp = ^bench_response;
    wire unused_win = bench_winner;
endmodule
