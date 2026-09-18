`timescale 1ns / 1ps

// Phase B Zynq wrapper: real 100 MHz from the 50 MHz board oscillator through
// an MMCM + BUFG, LOCKED gates the system reset, one microbenchmark core and a
// minimal UART status endpoint.  FPGA primitive use is confined to this file.
module Puf64_Ro_Microbench_Zynq_Top #(
    parameter integer UART_CLKS_PER_BIT = 868,
    parameter integer REF_CYCLES = 1023
)(
    input  wire       CLK50MHZ,
    input  wire [1:0] SW,
    input  wire       UART_RXD,
    output wire       UART_TXD,
    output wire [1:0] LED
);
    localparam integer INPUT_CLOCK_HZ = 50000000;
    localparam integer SYSTEM_CLOCK_HZ = 100000000;
    localparam [7:0] CMD_INFO = 8'h00;
    localparam [7:0] CMD_MEASURE = 8'h01;
    localparam [7:0] STATUS_SUCCESS = 8'hAA;

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

    wire bench_busy, bench_done, bench_stable, bench_timeout;
    wire [31:0] bench_free, bench_measure;
    wire [15:0] bench_ref;
    wire bench_presc_q, bench_ro_en;
    reg  start_pulse;

    puf64_ro_microbench #(
        .REF_CYCLES(REF_CYCLES)
    ) u_bench (
        .clk(clk_sys), .rst_n(por_done), .start(start_pulse),
        .busy(bench_busy), .done(bench_done),
        .capture_stable(bench_stable), .capture_timeout(bench_timeout),
        .captured_free(bench_free), .captured_measure(bench_measure),
        .ref_cycles_obs(bench_ref),
        .presc_q_obs(bench_presc_q), .ro_en_obs(bench_ro_en)
    );

    wire rx_dv;
    wire [7:0] rx_byte;
    uart_rx #(.CLKS_PER_BIT(UART_CLKS_PER_BIT)) u_rx (
        .i_Clock(clk_sys), .i_Rst(~por_done),
        .i_Rx_Serial(UART_RXD),
        .o_Rx_DV(rx_dv), .o_Rx_Byte(rx_byte)
    );

    reg tx_dv;
    reg [7:0] tx_byte;
    wire tx_active, tx_done;
    uart_tx #(.CLKS_PER_BIT(UART_CLKS_PER_BIT)) u_tx (
        .i_Clock(clk_sys), .i_Rst(~por_done),
        .i_Tx_DV(tx_dv), .i_Tx_Byte(tx_byte),
        .o_Tx_Active(tx_active), .o_Tx_Serial(UART_TXD), .o_Tx_Done(tx_done)
    );

    localparam [2:0] T_IDLE = 3'd0;
    localparam [2:0] T_WAIT = 3'd1;
    localparam [2:0] T_LOAD = 3'd2;
    localparam [2:0] T_SEND = 3'd3;
    reg [2:0] tstate;
    reg [7:0] tx_buf [0:15];
    reg [4:0] tx_count;
    reg [4:0] tx_index;

    task automatic load_status;
        begin
            tx_buf[0] <= STATUS_SUCCESS;
            tx_buf[1] <= {3'b0, bench_timeout, bench_stable, bench_done, bench_ro_en, bench_presc_q};
            tx_buf[2] <= bench_free[7:0];
            tx_buf[3] <= bench_free[15:8];
            tx_buf[4] <= bench_free[23:16];
            tx_buf[5] <= bench_free[31:24];
            tx_buf[6] <= bench_measure[7:0];
            tx_buf[7] <= bench_measure[15:8];
            tx_buf[8] <= bench_measure[23:16];
            tx_buf[9] <= bench_measure[31:24];
            tx_buf[10] <= bench_ref[7:0];
            tx_buf[11] <= bench_ref[15:8];
            tx_buf[12] <= {7'b0, mmcm_locked};
            tx_count <= 5'd13;
        end
    endtask

    always @(posedge clk_sys) begin
        if (!por_done) begin
            tstate <= T_IDLE;
            tx_dv <= 1'b0;
            start_pulse <= 1'b0;
            tx_count <= 5'd0;
            tx_index <= 5'd0;
        end else begin
            tx_dv <= 1'b0;
            start_pulse <= 1'b0;
            case (tstate)
                T_IDLE: begin
                    if (rx_dv && rx_byte == CMD_INFO) begin
                        tx_buf[0] <= 8'h50;
                        tx_buf[1] <= 8'h55;
                        tx_buf[2] <= 8'h46;
                        tx_buf[3] <= 8'h10;
                        tx_buf[4] <= {7'b0, mmcm_locked};
                        tx_buf[5] <= bench_ref[7:0];
                        tx_buf[6] <= bench_ref[15:8];
                        tx_buf[7] <= 8'h01;
                        tx_count <= 5'd8;
                        tx_index <= 5'd0;
                        tstate <= T_LOAD;
                    end else if (rx_dv && rx_byte == CMD_MEASURE) begin
                        start_pulse <= 1'b1;
                        tstate <= T_WAIT;
                    end else if (rx_dv) begin
                        tx_byte <= 8'h3F;
                        tx_dv <= 1'b1;
                    end
                end
                T_WAIT: begin
                    if (bench_done) begin
                        load_status();
                        tx_index <= 5'd0;
                        tstate <= T_LOAD;
                    end
                end
                T_LOAD: begin
                    if (!tx_active) begin
                        tx_byte <= tx_buf[tx_index];
                        tx_dv <= 1'b1;
                        tstate <= T_SEND;
                    end
                end
                T_SEND: begin
                    if (tx_done) begin
                        if (tx_index == tx_count - 1) begin
                            tstate <= T_IDLE;
                        end else begin
                            tx_index <= tx_index + 1'b1;
                            tstate <= T_LOAD;
                        end
                    end
                end
                default: tstate <= T_IDLE;
            endcase
        end
    end

    assign LED[0] = tx_active;
    assign LED[1] = bench_busy;
    wire unused_sw = &SW;
endmodule
