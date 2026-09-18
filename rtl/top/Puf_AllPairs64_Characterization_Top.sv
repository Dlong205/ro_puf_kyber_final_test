`timescale 1ns / 1ps

// Zynq-7020 board wrapper for the PUF64 characterization image.
//
// This wrapper is FPGA-specific: the 50 MHz board oscillator at N18 is
// multiplied to a real 100 MHz system clock with an MMCME2_BASE primitive and
// a BUFG.  The portable core (kp_puf_allpairs_top / puf_allpairs_uart) only
// sees a plain clk port and knows nothing about the MMCM.
module Puf_AllPairs64_Characterization_Top #(
    parameter integer UART_CLKS_PER_BIT = 868
)(
    input  wire       CLK50MHZ,
    input  wire [1:0] SW,
    input  wire       UART_RXD,
    output wire       UART_TXD,
    output wire [1:0] LED
);
    localparam integer NUM_RO = 64;
    localparam integer PAIR_COUNT = NUM_RO * (NUM_RO - 1) / 2;
    localparam integer REF_CYCLES = 1023;
    localparam integer BUILD_ID = 16'h0001;
    localparam integer INPUT_CLOCK_HZ = 50000000;
    localparam integer SYSTEM_CLOCK_HZ = 100000000;
    localparam integer MEASUREMENT_WINDOW_NS = (REF_CYCLES * 1000) / (SYSTEM_CLOCK_HZ / 1000000);

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

    wire puf_start, puf_busy, puf_done, tx_active;
    wire [PAIR_COUNT-1:0] puf_response;
    wire telemetry_valid;
    wire telemetry_stable, telemetry_timeout;
    wire [10:0] telemetry_index;
    wire [5:0] telemetry_pair_a, telemetry_pair_b;
    wire [31:0] telemetry_count0, telemetry_count1;
    wire telemetry_winner;

    puf64_ro_bench #(
        .NUM_RO(NUM_RO), .WIDTH(16), .REF_CYCLES(REF_CYCLES)
    ) u_puf (
        .clk(clk_sys), .rst_n(por_done), .zeroize(1'b0), .start(puf_start),
        .busy(puf_busy), .done(puf_done), .response(puf_response),
        .telemetry_valid(telemetry_valid),
        .telemetry_stable(telemetry_stable),
        .telemetry_timeout(telemetry_timeout),
        .telemetry_index(telemetry_index),
        .telemetry_pair_a(telemetry_pair_a),
        .telemetry_pair_b(telemetry_pair_b),
        .telemetry_count0(telemetry_count0),
        .telemetry_count1(telemetry_count1),
        .telemetry_winner(telemetry_winner)
    );

    puf_allpairs_uart #(
        .CLKS_PER_BIT(UART_CLKS_PER_BIT),
        .NUM_RO(NUM_RO),
        .PAIR_COUNT(PAIR_COUNT),
        .RESPONSE_BITS(PAIR_COUNT),
        .INPUT_CLOCK_HZ(INPUT_CLOCK_HZ),
        .SYSTEM_CLOCK_HZ(SYSTEM_CLOCK_HZ),
        .REF_CYCLES_INFO(REF_CYCLES),
        .MEASUREMENT_WINDOW_NS(MEASUREMENT_WINDOW_NS),
        .WIDTH(16), .TOPOLOGY_ID(16'hC0DE), .BUILD_ID(BUILD_ID),
        .IS_DIAGNOSTIC(0)
    ) u_uart (
        .clk(clk_sys), .rst_n(por_done),
        .uart_rx_i(UART_RXD), .uart_tx_o(UART_TXD), .tx_active(tx_active),
        .puf_start(puf_start), .puf_done(puf_done),
        .puf_response(puf_response),
        .telemetry_valid(telemetry_valid),
        .telemetry_index(telemetry_index),
        .telemetry_pair_a(telemetry_pair_a),
        .telemetry_pair_b(telemetry_pair_b),
        .telemetry_count0(telemetry_count0),
        .telemetry_count1(telemetry_count1),
        .telemetry_winner(telemetry_winner),
        .mmcm_locked(mmcm_locked)
    );

    assign LED[0] = tx_active;
    assign LED[1] = puf_busy;
    wire unused_sw = &SW;
    wire unused_tel = telemetry_stable ^ telemetry_timeout;
endmodule
