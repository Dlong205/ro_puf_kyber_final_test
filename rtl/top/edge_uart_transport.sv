`timescale 1ns / 1ps
`default_nettype none

// UART bring-up transport for the CPU-free Edge role.  The 32-bit tag is a
// diagnostic equality check, not a cryptographic confirmation protocol.
module edge_uart_transport #(
    parameter integer CLKS_PER_BIT = 868,
    parameter integer PK_WORDS = 200,
    parameter integer CT_WORDS = 192
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         uart_rx_i,
    output wire         uart_tx_o,
    output wire         tx_active,

    output reg          core_start,
    output reg          core_zeroize,
    output reg          core_enroll,
    output reg  [263:0] helper_in,
    input  wire [263:0] helper_out,
    input  wire         fe_success,
    input  wire         core_done,
    input  wire         core_busy,

    input  wire         ready_pk,
    input  wire         req_c,
    input  wire         stream_out_valid,
    input  wire [31:0]  stream_out_data,
    output reg          peer_req_pk,
    output wire         peer_ready_c,
    output reg          stream_in_valid,
    output reg  [31:0]  stream_in_data,

    input  wire         secret_valid,
    input  wire [255:0] shared_secret
);
    localparam [7:0] CMD_INFO    = 8'h00;
    localparam [7:0] CMD_ENROLL  = 8'h01;
    localparam [7:0] CMD_SESSION = 8'h02;
    localparam [7:0] STATUS_OK   = 8'haa;
    localparam [7:0] STATUS_FAIL = 8'hff;

    localparam [4:0] S_IDLE         = 5'd0;
    localparam [4:0] S_INFO         = 5'd1;
    localparam [4:0] S_ENROLL_WAIT  = 5'd2;
    localparam [4:0] S_ENROLL_SEND  = 5'd3;
    localparam [4:0] S_HELPER_MARK  = 5'd4;
    localparam [4:0] S_CONTEXT_RX   = 5'd5;
    localparam [4:0] S_WAIT_PK      = 5'd6;
    localparam [4:0] S_PK_MARK      = 5'd7;
    localparam [4:0] S_PK_REQ       = 5'd8;
    localparam [4:0] S_PK_WAIT      = 5'd9;
    localparam [4:0] S_PK_SEND      = 5'd10;
    localparam [4:0] S_CT_MARK      = 5'd11;
    localparam [4:0] S_CT_RX        = 5'd12;
    localparam [4:0] S_CT_DELIVER   = 5'd13;
    localparam [4:0] S_SECRET_WAIT  = 5'd14;
    localparam [4:0] S_RESULT_SEND  = 5'd15;
    localparam [4:0] S_ZEROIZE      = 5'd16;
    localparam [4:0] S_FAIL_SEND    = 5'd17;

    wire       rx_dv;
    wire [7:0] rx_byte;
    wire       tx_done;
    reg        tx_dv;
    reg  [7:0] tx_byte;
    reg        tx_inflight;
    reg        tx_done_d;
    wire       tx_done_pulse = tx_done && !tx_done_d;

    reg [4:0] state;
    reg [9:0] item_count;
    reg [1:0] byte_count;
    reg [31:0] word_shift;
    reg [31:0] nonce;
    reg [31:0] result_tag;
    reg        ct_buffer_ready;
    reg [31:0] ct_buffer [0:CT_WORDS-1];

    // Kyber_Server samples ready_c before entering its continuous ciphertext
    // receive state.  UART is far too slow to supply that stream on demand,
    // so acknowledge readiness only after the complete ciphertext is buffered.
    assign peer_ready_c = ct_buffer_ready;

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
        .i_Clock(clk), .i_Rst(~rst_n), .i_Rx_Serial(uart_rx_i),
        .o_Rx_DV(rx_dv), .o_Rx_Byte(rx_byte)
    );

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .i_Clock(clk), .i_Rst(~rst_n), .i_Tx_DV(tx_dv),
        .i_Tx_Byte(tx_byte), .o_Tx_Active(tx_active),
        .o_Tx_Serial(uart_tx_o), .o_Tx_Done(tx_done)
    );

    function automatic [7:0] select_word_byte;
        input [31:0] value;
        input [1:0] index;
        begin
            case (index)
                2'd0: select_word_byte = value[7:0];
                2'd1: select_word_byte = value[15:8];
                2'd2: select_word_byte = value[23:16];
                default: select_word_byte = value[31:24];
            endcase
        end
    endfunction

    function automatic [7:0] info_byte;
        input [2:0] index;
        begin
            case (index)
                3'd0: info_byte = 8'h45; // E
                3'd1: info_byte = 8'h41; // A
                3'd2: info_byte = 8'h01;
                3'd3: info_byte = 8'h00;
                default: info_byte = 8'h07; // enroll, session, diagnostic tag
            endcase
        end
    endfunction

    // Keep transport state reset synchronous. Several outputs feed the
    // accelerator RAM/FIFO control path; an asynchronous reset here is
    // otherwise promoted into a large high-fanout reset network by Vivado.
    always @(posedge clk) begin
        if (!rst_n) begin
            state           <= S_IDLE;
            core_start      <= 1'b0;
            core_zeroize    <= 1'b0;
            core_enroll     <= 1'b0;
            helper_in       <= 264'd0;
            peer_req_pk     <= 1'b0;
            stream_in_valid <= 1'b0;
            stream_in_data  <= 32'd0;
            tx_dv           <= 1'b0;
            tx_byte         <= 8'd0;
            tx_inflight     <= 1'b0;
            tx_done_d       <= 1'b0;
            item_count      <= 10'd0;
            byte_count      <= 2'd0;
            word_shift      <= 32'd0;
            nonce           <= 32'd0;
            result_tag      <= 32'd0;
            ct_buffer_ready <= 1'b0;
        end else begin
            core_start      <= 1'b0;
            core_zeroize    <= 1'b0;
            peer_req_pk     <= 1'b0;
            stream_in_valid <= 1'b0;
            tx_dv           <= 1'b0;
            tx_done_d       <= tx_done;
            if (tx_done_pulse)
                tx_inflight <= 1'b0;

            case (state)
                S_IDLE: begin
                    item_count <= 10'd0;
                    byte_count <= 2'd0;
                    if (rx_dv && rx_byte == CMD_INFO) begin
                        state <= S_INFO;
                    end else if (rx_dv && rx_byte == CMD_ENROLL && !core_busy) begin
                        core_enroll <= 1'b1;
                        core_start <= 1'b1;
                        state <= S_ENROLL_WAIT;
                    end else if (rx_dv && rx_byte == CMD_SESSION && !core_busy) begin
                        core_enroll <= 1'b0;
                        state <= S_HELPER_MARK;
                    end else if (rx_dv) begin
                        state <= S_FAIL_SEND;
                    end
                end

                S_INFO: begin
                    if (!tx_inflight) begin
                        tx_byte <= info_byte(item_count[2:0]);
                        tx_dv <= 1'b1;
                        tx_inflight <= 1'b1;
                    end
                    if (tx_done_pulse) begin
                        if (item_count == 10'd4)
                            state <= S_IDLE;
                        else
                            item_count <= item_count + 1'b1;
                    end
                end

                S_ENROLL_WAIT: begin
                    if (core_done) begin
                        item_count <= 10'd0;
                        state <= fe_success ? S_ENROLL_SEND : S_FAIL_SEND;
                    end
                end

                // STATUS_OK followed by the 33-byte public helper, LSB first.
                S_ENROLL_SEND: begin
                    if (!tx_inflight) begin
                        tx_byte <= item_count == 0 ? STATUS_OK :
                                   helper_out[8*(item_count-1) +: 8];
                        tx_dv <= 1'b1;
                        tx_inflight <= 1'b1;
                    end
                    if (tx_done_pulse) begin
                        if (item_count == 10'd33)
                            state <= S_IDLE;
                        else
                            item_count <= item_count + 1'b1;
                    end
                end

                // 'H' requests 33 helper bytes followed by a 4-byte nonce.
                S_HELPER_MARK: begin
                    if (!tx_inflight) begin
                        tx_byte <= 8'h48;
                        tx_dv <= 1'b1;
                        tx_inflight <= 1'b1;
                    end
                    if (tx_done_pulse) begin
                        item_count <= 10'd0;
                        state <= S_CONTEXT_RX;
                    end
                end

                S_CONTEXT_RX: begin
                    if (rx_dv) begin
                        if (item_count < 33)
                            helper_in[8*item_count +: 8] <= rx_byte;
                        else
                            nonce[8*(item_count-33) +: 8] <= rx_byte;
                        if (item_count == 10'd36) begin
                            core_start <= 1'b1;
                            state <= S_WAIT_PK;
                        end else begin
                            item_count <= item_count + 1'b1;
                        end
                    end
                end

                S_WAIT_PK: begin
                    if (ready_pk) begin
                        item_count <= 10'd0;
                        state <= S_PK_MARK;
                    end else if (core_done) begin
                        state <= S_FAIL_SEND;
                    end
                end

                S_PK_MARK: begin
                    if (!tx_inflight) begin
                        tx_byte <= 8'h50;
                        tx_dv <= 1'b1;
                        tx_inflight <= 1'b1;
                    end
                    if (tx_done_pulse)
                        state <= S_PK_REQ;
                end

                S_PK_REQ: begin
                    peer_req_pk <= 1'b1;
                    state <= S_PK_WAIT;
                end

                S_PK_WAIT: begin
                    if (stream_out_valid) begin
                        word_shift <= stream_out_data;
                        byte_count <= 2'd0;
                        state <= S_PK_SEND;
                    end
                end

                S_PK_SEND: begin
                    if (!tx_inflight) begin
                        tx_byte <= select_word_byte(word_shift, byte_count);
                        tx_dv <= 1'b1;
                        tx_inflight <= 1'b1;
                    end
                    if (tx_done_pulse) begin
                        if (byte_count == 2'd3) begin
                            if (item_count == PK_WORDS-1)
                                state <= S_CT_MARK;
                            else begin
                                item_count <= item_count + 1'b1;
                                state <= S_PK_REQ;
                            end
                        end else begin
                            byte_count <= byte_count + 1'b1;
                        end
                    end
                end

                S_CT_MARK: begin
                    if (!tx_inflight) begin
                        tx_byte <= 8'h43;
                        tx_dv <= 1'b1;
                        tx_inflight <= 1'b1;
                    end
                    if (tx_done_pulse) begin
                        item_count <= 10'd0;
                        byte_count <= 2'd0;
                        ct_buffer_ready <= 1'b0;
                        state <= S_CT_RX;
                    end
                end

                S_CT_RX: begin
                    if (rx_dv) begin
                        word_shift[8*byte_count +: 8] <= rx_byte;
                        if (byte_count == 2'd3) begin
                            ct_buffer[item_count] <= {rx_byte, word_shift[23:0]};
                            byte_count <= 2'd0;
                            if (item_count == CT_WORDS-1) begin
                                item_count <= 10'd0;
                                ct_buffer_ready <= 1'b1;
                                state <= S_CT_DELIVER;
                            end else begin
                                item_count <= item_count + 1'b1;
                            end
                        end else begin
                            byte_count <= byte_count + 1'b1;
                        end
                    end
                end

                S_CT_DELIVER: begin
                    if (req_c && ct_buffer_ready) begin
                        stream_in_data <= ct_buffer[item_count];
                        stream_in_valid <= 1'b1;
                        if (item_count == CT_WORDS-1) begin
                            state <= S_SECRET_WAIT;
                        end else begin
                            item_count <= item_count + 1'b1;
                        end
                    end
                end

                S_SECRET_WAIT: begin
                    if (secret_valid) begin
                        // Kyber_Server continues to use ready_c after the last
                        // ciphertext word while its NTT enters the CCA path.
                        // Match Kyber_Client: retire ready_c only when the
                        // shared secret is complete.
                        ct_buffer_ready <= 1'b0;
                        result_tag <= nonce ^ shared_secret[31:0] ^
                            shared_secret[63:32] ^ shared_secret[95:64] ^
                            shared_secret[127:96] ^ shared_secret[159:128] ^
                            shared_secret[191:160] ^ shared_secret[223:192] ^
                            shared_secret[255:224];
                        item_count <= 10'd0;
                        state <= S_RESULT_SEND;
                    end
                end

                // STATUS_OK plus a deliberately non-cryptographic 32-bit tag.
                S_RESULT_SEND: begin
                    if (!tx_inflight) begin
                        tx_byte <= item_count == 0 ? STATUS_OK :
                                   select_word_byte(result_tag, item_count[1:0]-1'b1);
                        tx_dv <= 1'b1;
                        tx_inflight <= 1'b1;
                    end
                    if (tx_done_pulse) begin
                        if (item_count == 10'd4)
                            state <= S_ZEROIZE;
                        else
                            item_count <= item_count + 1'b1;
                    end
                end

                S_ZEROIZE: begin
                    core_zeroize <= 1'b1;
                    helper_in <= 264'd0;
                    nonce <= 32'd0;
                    result_tag <= 32'd0;
                    stream_in_data <= 32'd0;
                    word_shift <= 32'd0;
                    ct_buffer_ready <= 1'b0;
                    state <= S_IDLE;
                end

                S_FAIL_SEND: begin
                    if (!tx_inflight) begin
                        tx_byte <= STATUS_FAIL;
                        tx_dv <= 1'b1;
                        tx_inflight <= 1'b1;
                    end
                    if (tx_done_pulse)
                        state <= S_ZEROIZE;
                end

                default: state <= S_ZEROIZE;
            endcase
        end
    end
endmodule

`default_nettype wire
