`timescale 1ns / 1ps

// Characterization-only UART endpoint. This module deliberately exports the
// raw PUF response and must never be included in a production/release image.
module puf_characterization_uart #(
    parameter integer CLKS_PER_BIT = 434,
    parameter integer RESPONSE_BITS = 264
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     uart_rx_i,
    output wire                     uart_tx_o,
    output wire                     tx_active,
    output reg                      puf_start,
    input  wire                     puf_done,
    input  wire [RESPONSE_BITS-1:0] puf_response
);
    localparam [7:0] CMD_INFO = 8'h00;
    localparam [7:0] CMD_RAW  = 8'h70;
    localparam [7:0] STATUS_SUCCESS = 8'hAA;
    localparam [7:0] STATUS_FAIL = 8'hFF;

    localparam [2:0] S_IDLE     = 3'd0;
    localparam [2:0] S_WAIT_PUF = 3'd1;
    localparam [2:0] S_TX_LOAD  = 3'd2;
    localparam [2:0] S_TX_PULSE = 3'd3;
    localparam [2:0] S_TX_WAIT  = 3'd4;

    wire       rx_dv;
    wire [7:0] rx_byte;
    wire       tx_done;
    reg        tx_dv;
    reg  [7:0] tx_byte;

    reg [2:0] state;
    reg [RESPONSE_BITS-1:0] tx_shift;
    reg [RESPONSE_BITS-1:0] response_latched;
    reg [5:0] tx_remaining;
    reg       raw_status_pending;
    reg [23:0] wait_cycles;

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
        .i_Clock(clk),
        .i_Rst(~rst_n),
        .i_Rx_Serial(uart_rx_i),
        .o_Rx_DV(rx_dv),
        .o_Rx_Byte(rx_byte)
    );

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .i_Clock(clk),
        .i_Rst(~rst_n),
        .i_Tx_DV(tx_dv),
        .i_Tx_Byte(tx_byte),
        .o_Tx_Active(tx_active),
        .o_Tx_Serial(uart_tx_o),
        .o_Tx_Done(tx_done)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state              <= S_IDLE;
            puf_start          <= 1'b0;
            tx_dv              <= 1'b0;
            tx_byte            <= 8'h00;
            tx_shift           <= {RESPONSE_BITS{1'b0}};
            response_latched   <= {RESPONSE_BITS{1'b0}};
            tx_remaining       <= 6'd0;
            raw_status_pending <= 1'b0;
            wait_cycles        <= 24'd0;
        end else begin
            puf_start <= 1'b0;
            tx_dv     <= 1'b0;

            case (state)
                S_IDLE: begin
                    wait_cycles <= 24'd0;
                    if (rx_dv && rx_byte == CMD_RAW) begin
                        puf_start <= 1'b1;
                        state <= S_WAIT_PUF;
                    end else if (rx_dv && rx_byte == CMD_INFO) begin
                        // Low byte is transmitted first: "PUF", v1.0, raw-cap.
                        tx_shift <= {
                            216'd0, 8'h01, 8'h00, 8'h01,
                            8'h46, 8'h55, 8'h50
                        };
                        tx_remaining <= 6'd6;
                        state <= S_TX_LOAD;
                    end else if (rx_dv) begin
                        tx_shift <= {{(RESPONSE_BITS-8){1'b0}}, 8'h3F};
                        tx_remaining <= 6'd1;
                        state <= S_TX_LOAD;
                    end
                end

                S_WAIT_PUF: begin
                    wait_cycles <= wait_cycles + 1'b1;
                    if (puf_done) begin
                        response_latched <= puf_response;
                        tx_byte <= STATUS_SUCCESS;
                        raw_status_pending <= 1'b1;
                        state <= S_TX_PULSE;
                    end else if (&wait_cycles) begin
                        tx_byte <= STATUS_FAIL;
                        raw_status_pending <= 1'b0;
                        tx_remaining <= 6'd1;
                        state <= S_TX_PULSE;
                    end
                end

                S_TX_LOAD: begin
                    tx_byte  <= tx_shift[7:0];
                    tx_shift <= {{8{1'b0}}, tx_shift[RESPONSE_BITS-1:8]};
                    state <= S_TX_PULSE;
                end

                S_TX_PULSE: begin
                    tx_dv <= 1'b1;
                    state <= S_TX_WAIT;
                end

                S_TX_WAIT: begin
                    if (tx_done) begin
                        if (raw_status_pending) begin
                            raw_status_pending <= 1'b0;
                            tx_shift <= response_latched;
                            tx_remaining <= 6'd33;
                            state <= S_TX_LOAD;
                        end else if (tx_remaining > 1) begin
                            tx_remaining <= tx_remaining - 1'b1;
                            state <= S_TX_LOAD;
                        end else begin
                            tx_remaining <= 6'd0;
                            state <= S_IDLE;
                        end
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
