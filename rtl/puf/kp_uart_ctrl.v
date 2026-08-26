`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// kp_uart_ctrl — minimal UART bridge for kp_puf_top
//
// Protocol:
//   1. SLEEP: wait for 1 rx byte (seed), latch it, pulse `start`
//   2. WAITPUF: wait for `puf_done`
//   3. SENDC: echo seed byte over UART
//   4. SENDR: send 33 response bytes (264 bits)
//   5. back to SLEEP
//////////////////////////////////////////////////////////////////////////////////

module kp_uart_ctrl(
    input  clk,
    input  reset,
    input  [7:0]  rx_byte,
    input  rx_DV,
    input  [263:0] response,
    input  puf_done,
    input  uart_done,
    output reg [7:0] seed,
    output reg start,
    output reg [7:0] tx_byte,
    output reg tx_DV
    );

    reg [2:0] state;
    parameter SLEEP   = 3'd0,
              WAITPUF = 3'd1,
              SENDC   = 3'd2,
              WAITC   = 3'd3,
              SENDR   = 3'd4,
              WAITR   = 3'd5;

    reg [5:0] counter;   // 0..32 (33 bytes)
    reg [7:0] temp_seed;

    always @(posedge clk) begin
        if (reset) begin
            state     <= SLEEP;
            tx_byte   <= 8'd0;
            tx_DV     <= 1'b0;
            counter   <= 6'd0;
            temp_seed <= 8'd0;
            start     <= 1'b0;
            seed      <= 8'd0;
        end else begin
            case (state)
                SLEEP: begin
                    tx_DV   <= 1'b0;
                    start   <= 1'b0;
                    counter <= 6'd0;
                    if (rx_DV) begin
                        temp_seed <= rx_byte;
                        seed      <= rx_byte;
                        start     <= 1'b1;
                        state     <= WAITPUF;
                    end
                end
                WAITPUF: begin
                    start <= 1'b0;
                    if (puf_done) state <= SENDC;
                end
                SENDC: begin
                    tx_byte <= temp_seed;
                    tx_DV   <= 1'b1;
                    state   <= WAITC;
                end
                WAITC: begin
                    tx_DV <= 1'b0;
                    if (uart_done) begin
                        counter <= 6'd0;
                        state   <= SENDR;
                    end
                end
                SENDR: begin
                    tx_byte <= response[263 - counter*8 -: 8];
                    tx_DV   <= 1'b1;
                    state   <= WAITR;
                end
                WAITR: begin
                    tx_DV <= 1'b0;
                    if (uart_done) begin
                        if (counter == 6'd32) begin
                            state <= SLEEP;
                        end else begin
                            counter <= counter + 1;
                            state   <= SENDR;
                        end
                    end
                end
                default: state <= SLEEP;
            endcase
        end
    end

endmodule