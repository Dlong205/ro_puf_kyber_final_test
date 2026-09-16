`timescale 1ns / 1ps

// Diagnostic UART endpoint for the 32-RO/C(32,2) candidate pool.  Protocol
// 2.0 is intentionally distinct from the legacy 264-position image so a host
// cannot silently interpret pair metadata as an 8-bit LFSR challenge.
module puf_allpairs_uart #(
    parameter integer CLKS_PER_BIT = 434,
    parameter integer RESPONSE_BITS = 496
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     uart_rx_i,
    output wire                     uart_tx_o,
    output wire                     tx_active,
    output reg                      puf_start,
    input  wire                     puf_done,
    input  wire [RESPONSE_BITS-1:0] puf_response,
    input  wire                     telemetry_valid,
    input  wire [8:0]               telemetry_index,
    input  wire [4:0]               telemetry_pair_a,
    input  wire [4:0]               telemetry_pair_b,
    input  wire [31:0]              telemetry_count0,
    input  wire [31:0]              telemetry_count1,
    input  wire                     telemetry_winner
);
    localparam integer RAW_BYTES = (RESPONSE_BITS + 7) / 8;
    localparam [7:0] CMD_INFO = 8'h00;
    localparam [7:0] CMD_RAW = 8'h70;
    localparam [7:0] CMD_MARGIN = 8'h71;
    localparam [7:0] STATUS_SUCCESS = 8'hAA;
    localparam [7:0] STATUS_FAIL = 8'hFF;

    localparam [2:0] S_IDLE = 3'd0;
    localparam [2:0] S_WAIT_PUF = 3'd1;
    localparam [2:0] S_TX_LOAD = 3'd2;
    localparam [2:0] S_TX_PULSE = 3'd3;
    localparam [2:0] S_TX_WAIT = 3'd4;
    localparam [2:0] S_MARGIN_LOAD = 3'd5;
    localparam [2:0] S_MARGIN_PREFETCH = 3'd6;

    wire rx_dv;
    wire [7:0] rx_byte;
    wire tx_done;
    reg tx_dv;
    reg [7:0] tx_byte;
    reg [2:0] state;
    reg [RESPONSE_BITS-1:0] tx_shift;
    reg [RESPONSE_BITS-1:0] response_latched;
    reg [8:0] tx_remaining;
    reg raw_status_pending;
    reg margin_request;
    reg margin_status_pending;
    reg margin_tx_active;
    reg [8:0] telemetry_capture_count;
    reg [8:0] margin_tx_index;
    reg [3:0] margin_tx_byte_index;
    reg [23:0] wait_cycles;

    // 75-bit record: pair_a, pair_b, count0, count1, winner.  Vivado maps the
    // 496 records into block RAM so instrumentation switching stays compact.
    (* ram_style = "block" *) reg [74:0] telemetry_mem [0:RESPONSE_BITS-1];
    reg [74:0] telemetry_read_data;

    wire [4:0] current_pair_a = telemetry_read_data[4:0];
    wire [4:0] current_pair_b = telemetry_read_data[9:5];
    wire [31:0] current_count0 = telemetry_read_data[41:10];
    wire [31:0] current_count1 = telemetry_read_data[73:42];
    wire current_winner = telemetry_read_data[74];
    wire [31:0] current_margin = (current_count0 >= current_count1) ?
                                 current_count0 - current_count1 :
                                 current_count1 - current_count0;
    wire current_tie = current_count0 == current_count1;
    wire telemetry_capture_accept = margin_request && telemetry_valid &&
                                    telemetry_capture_count < RESPONSE_BITS &&
                                    telemetry_index == telemetry_capture_count;
    wire telemetry_frame_complete = telemetry_capture_count == RESPONSE_BITS ||
                                    (telemetry_capture_accept &&
                                     telemetry_capture_count == RESPONSE_BITS - 1);

    always @(posedge clk) begin
        if (telemetry_capture_accept)
            telemetry_mem[telemetry_capture_count] <= {
                telemetry_winner, telemetry_count1, telemetry_count0,
                telemetry_pair_b, telemetry_pair_a
            };
        if (state == S_MARGIN_PREFETCH)
            telemetry_read_data <= telemetry_mem[margin_tx_index];
    end

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
        .i_Clock(clk), .i_Rst(~rst_n), .i_Rx_Serial(uart_rx_i),
        .o_Rx_DV(rx_dv), .o_Rx_Byte(rx_byte)
    );
    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .i_Clock(clk), .i_Rst(~rst_n), .i_Tx_DV(tx_dv),
        .i_Tx_Byte(tx_byte), .o_Tx_Active(tx_active),
        .o_Tx_Serial(uart_tx_o), .o_Tx_Done(tx_done)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= S_IDLE;
            puf_start <= 1'b0;
            tx_dv <= 1'b0;
            tx_byte <= 8'h00;
            tx_shift <= '0;
            response_latched <= '0;
            tx_remaining <= '0;
            raw_status_pending <= 1'b0;
            margin_request <= 1'b0;
            margin_status_pending <= 1'b0;
            margin_tx_active <= 1'b0;
            telemetry_capture_count <= '0;
            margin_tx_index <= '0;
            margin_tx_byte_index <= '0;
            wait_cycles <= '0;
        end else begin
            puf_start <= 1'b0;
            tx_dv <= 1'b0;
            case (state)
                S_IDLE: begin
                    wait_cycles <= '0;
                    margin_request <= 1'b0;
                    if (rx_dv && rx_byte == CMD_RAW) begin
                        puf_start <= 1'b1;
                        state <= S_WAIT_PUF;
                    end else if (rx_dv && rx_byte == CMD_MARGIN) begin
                        telemetry_capture_count <= '0;
                        margin_request <= 1'b1;
                        puf_start <= 1'b1;
                        state <= S_WAIT_PUF;
                    end else if (rx_dv && rx_byte == CMD_INFO) begin
                        // "PUF", protocol 2.0, capabilities raw+margin+allpairs.
                        tx_shift <= {
                            {(RESPONSE_BITS-48){1'b0}},
                            8'h07, 8'h00, 8'h02, 8'h46, 8'h55, 8'h50
                        };
                        tx_remaining <= 9'd6;
                        state <= S_TX_LOAD;
                    end else if (rx_dv) begin
                        tx_shift <= {{(RESPONSE_BITS-8){1'b0}}, 8'h3F};
                        tx_remaining <= 9'd1;
                        state <= S_TX_LOAD;
                    end
                end

                S_WAIT_PUF: begin
                    wait_cycles <= wait_cycles + 1'b1;
                    if (telemetry_capture_accept)
                        telemetry_capture_count <= telemetry_capture_count + 1'b1;
                    if (puf_done) begin
                        if (margin_request && !telemetry_frame_complete) begin
                            tx_byte <= STATUS_FAIL;
                            margin_status_pending <= 1'b0;
                        end else begin
                            response_latched <= puf_response;
                            tx_byte <= STATUS_SUCCESS;
                            raw_status_pending <= !margin_request;
                            margin_status_pending <= margin_request;
                        end
                        margin_request <= 1'b0;
                        state <= S_TX_PULSE;
                    end else if (&wait_cycles) begin
                        tx_byte <= STATUS_FAIL;
                        raw_status_pending <= 1'b0;
                        margin_status_pending <= 1'b0;
                        margin_request <= 1'b0;
                        tx_remaining <= 9'd1;
                        state <= S_TX_PULSE;
                    end
                end

                S_TX_LOAD: begin
                    tx_byte <= tx_shift[7:0];
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
                            tx_remaining <= RAW_BYTES;
                            state <= S_TX_LOAD;
                        end else if (margin_status_pending) begin
                            margin_status_pending <= 1'b0;
                            margin_tx_active <= 1'b1;
                            margin_tx_index <= '0;
                            margin_tx_byte_index <= '0;
                            state <= S_MARGIN_PREFETCH;
                        end else if (margin_tx_active) begin
                            if (margin_tx_byte_index == 4'd15) begin
                                margin_tx_byte_index <= '0;
                                if (margin_tx_index == RESPONSE_BITS - 1) begin
                                    margin_tx_active <= 1'b0;
                                    state <= S_IDLE;
                                end else begin
                                    margin_tx_index <= margin_tx_index + 1'b1;
                                    state <= S_MARGIN_PREFETCH;
                                end
                            end else begin
                                margin_tx_byte_index <= margin_tx_byte_index + 1'b1;
                                state <= S_MARGIN_LOAD;
                            end
                        end else if (tx_remaining > 1) begin
                            tx_remaining <= tx_remaining - 1'b1;
                            state <= S_TX_LOAD;
                        end else begin
                            tx_remaining <= '0;
                            state <= S_IDLE;
                        end
                    end
                end

                S_MARGIN_LOAD: begin
                    // 16-byte LE record:
                    // index[15:0], pair_a, {reserved,tie,winner,pair_b[4:0]},
                    // count0, count1, abs(count0-count1).
                    case (margin_tx_byte_index)
                        4'd0:  tx_byte <= margin_tx_index[7:0];
                        4'd1:  tx_byte <= {7'd0, margin_tx_index[8]};
                        4'd2:  tx_byte <= {3'd0, current_pair_a};
                        4'd3:  tx_byte <= {1'b0, current_tie, current_winner, current_pair_b};
                        4'd4:  tx_byte <= current_count0[7:0];
                        4'd5:  tx_byte <= current_count0[15:8];
                        4'd6:  tx_byte <= current_count0[23:16];
                        4'd7:  tx_byte <= current_count0[31:24];
                        4'd8:  tx_byte <= current_count1[7:0];
                        4'd9:  tx_byte <= current_count1[15:8];
                        4'd10: tx_byte <= current_count1[23:16];
                        4'd11: tx_byte <= current_count1[31:24];
                        4'd12: tx_byte <= current_margin[7:0];
                        4'd13: tx_byte <= current_margin[15:8];
                        4'd14: tx_byte <= current_margin[23:16];
                        default: tx_byte <= current_margin[31:24];
                    endcase
                    state <= S_TX_PULSE;
                end

                S_MARGIN_PREFETCH: state <= S_MARGIN_LOAD;
                default: state <= S_IDLE;
            endcase
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (RESPONSE_BITS != 496)
            $error("all-pairs UART protocol requires exactly 496 records");
        if ((RESPONSE_BITS % 8) != 0)
            $error("all-pairs RAW response must be byte aligned");
    end
`endif

endmodule
