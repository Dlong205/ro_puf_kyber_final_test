`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// system_uart_ctrl.v — UART command interface for Kyber PUF System
//
// Protocol:
//   PC → FPGA: 0x01 = ENROLL, 0x02 = RECONSTRUCT (+ 33 bytes helper data)
//   FPGA → PC: 33 bytes helper data (Enroll) or 0xAA/0xFF status (Recon)
//-----------------------------------------------------------------------------

module system_uart_ctrl (
    input clk,
    input reset,
    
    input  [7:0] rx_byte,
    input        rx_DV,
    input        tx_done,         // Handshake from UART TX
    output reg [7:0] tx_byte,
    output reg       tx_DV,
    
    // System control
    output reg        sys_start_enroll,
    output reg        sys_start_recon,
    input             sys_done,
    input             sys_success,   // From master FSM: was reconstruction successful?
    
    // Helper Data Interface
    input  [263:0]    helper_out,  // from Enroll
    output reg [263:0] helper_in   // to Recon
);

    parameter IDLE         = 3'd0,
              WAIT_SYS     = 3'd1,
              SEND_HELPER  = 3'd2,
              SEND_WAIT_TX = 3'd3,    // Wait for TX to finish before next byte
              RECV_HELPER  = 3'd4,
              SEND_STATUS  = 3'd5,
              SEND_STATUS_WAIT = 3'd6;
              
    reg [2:0] state;
    reg [5:0] byte_cnt;
    reg [263:0] shift_reg;
    reg is_enroll_cmd;  // Track which command triggered the operation

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state            <= IDLE;
            sys_start_enroll <= 0;
            sys_start_recon  <= 0;
            tx_DV            <= 0;
            byte_cnt         <= 0;
            helper_in        <= 0;
            shift_reg        <= 0;
            is_enroll_cmd    <= 0;
        end else begin
            // Default: deassert pulses
            tx_DV            <= 0;
            sys_start_enroll <= 0;
            sys_start_recon  <= 0;
            
            case (state)
                IDLE: begin
                    if (rx_DV) begin
                        if (rx_byte == 8'h01) begin // ENROLL CMD
                            sys_start_enroll <= 1;
                            is_enroll_cmd    <= 1;
                            state            <= WAIT_SYS;
                        end
                        else if (rx_byte == 8'h02) begin // RECON CMD
                            byte_cnt <= 0;
                            state    <= RECV_HELPER;
                        end
                    end
                end
                
                WAIT_SYS: begin
                    if (sys_done) begin
                        if (is_enroll_cmd) begin
                            // Enroll done: send 33 bytes of helper data
                            shift_reg <= helper_out;
                            byte_cnt  <= 0;
                            state     <= SEND_HELPER;
                        end else begin
                            // Reconstruct done: send status byte
                            state <= SEND_STATUS;
                        end
                    end
                end
                
                SEND_HELPER: begin
                    // Send MSB byte first, then shift left
                    tx_byte  <= shift_reg[263:256];
                    tx_DV    <= 1;
                    state    <= SEND_WAIT_TX;
                end
                
                SEND_WAIT_TX: begin
                    // Wait for UART TX module to finish transmitting
                    if (tx_done) begin
                        shift_reg <= {shift_reg[255:0], 8'd0};
                        byte_cnt  <= byte_cnt + 1;
                        if (byte_cnt == 32)
                            state <= IDLE;   // All 33 bytes sent
                        else
                            state <= SEND_HELPER; // Send next byte
                    end
                end
                
                RECV_HELPER: begin
                    // Receive 33 bytes from PC
                    if (rx_DV) begin
                        shift_reg <= {shift_reg[255:0], rx_byte};
                        byte_cnt  <= byte_cnt + 1;
                        if (byte_cnt == 32) begin
                            helper_in       <= {shift_reg[255:0], rx_byte};
                            is_enroll_cmd   <= 0;
                            sys_start_recon <= 1;
                            state           <= WAIT_SYS;
                        end
                    end
                end
                
                SEND_STATUS: begin
                    tx_byte <= sys_success ? 8'hAA : 8'hFF;
                    tx_DV   <= 1;
                    state   <= SEND_STATUS_WAIT;
                end
                
                SEND_STATUS_WAIT: begin
                    if (tx_done) state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end
endmodule
