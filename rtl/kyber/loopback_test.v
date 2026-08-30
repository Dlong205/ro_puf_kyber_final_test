`timescale 1ns / 1ps

module kyber_loopback_test (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [2:0]  k,
    output wire        uart_tx,
    output wire [5:0]  led_status
);

    // Loopback connections
    wire        server_valid, server_req_pk, server_req_c;
    wire [31:0] server_dout;
    wire        client_valid, client_req_pk, client_req_c;
    wire [31:0] client_dout;
    
    wire        server_ready_pk, server_ready_c;
    wire        server_req_pk_out, server_req_c_out;
    wire        client_ready_pk, client_ready_c;
    wire        client_req_pk, client_req_c;
    wire [31:0] server_dout, client_dout;
    
    wire        server_start, server_wen, client_start, client_wen;
    wire [2:0]  k_reg;
    
    // Loopback connections
    wire        server_wen_int, client_wen_int;
    wire [31:0] server_din, client_din;
    wire        server_ready_c, client_ready_pk;
    wire        server_req_pk_int, server_req_c_int;
    wire        client_req_pk_int, client_req_c_int;
    
    // Loopback connections
    assign server_wen_int     = client_dout[31] ? 1'b0 : client_dout[30];  // Use MSB as wen indicator
    assign client_wen_int     = server_dout[31] ? 1'b0 : server_dout[30];
    
    // Actually, let's use the valid signals properly
    // Server -> Client
    assign client_din      = server_dout;
    assign client_wen      = server_valid;
    assign client_ready_pk = 1'b1;  // Always ready to receive PK
    assign client_req_pk   = 1'b0;  // Not requesting PK from server in loopback
    assign client_req_c    = 1'b0;
    assign client_ready_c  = 1'b1;
    
    // Client -> Server (loopback)
    assign server_din      = client_dout;
    assign server_wen      = client_valid;
    assign server_ready_c  = 1'b1;
    assign server_req_pk   = 1'b0;
    assign server_req_c    = 1'b0;
    assign server_ready_pk = 1'b1;
    
    // Status registers
    reg [5:0] test_state;
    reg [31:0] cycle_count;
    reg [5:0] test_result;
    
    // Kyber Server instance
    Kyber_Server server_inst (
        .clk(clk),
        .rst(~rst_n),
        .start(start),
        .wen(server_wen),
        .k(3'd2),
        .ready_c(1'b1),
        .req_pk(1'b0),
        .din(server_din),
        .ready_pk(),
        .ready_c(),
        .req_pk(),
        .req_c(),
        .valid(server_valid),
        .dout(server_dout)
    );
    
    // Kyber Client instance
    Kyber_Client client_inst (
        .clk(clk),
        .rst(~rst_n),
        .start(start),
        .wen(1'b1),  // Always write to client
        .k(3'd2),
        .ready_pk(1'b1),
        .req_c(1'b0),
        .din(client_din),
        .ready_pk(),
        .ready_c(),
        .req_pk(),
        .req_c(),
        .valid(client_valid),
        .dout(client_dout)
    );
    
    // Simple state machine for test control
    localparam S_IDLE     = 6'd0;
    localparam S_KEYGEN   = 6'd1;
    localparam S_ENCAP    = 6'd2;
    localparam S_DECAP    = 6'd3;
    localparam S_VERIFY   = 6'd3;
    localparam S_DONE     = 6'd4;
    
    reg [5:0] test_state_reg, test_state_next;
    reg [31:0] cycle_counter;
    reg [31:0] pk_buffer [0:199];
    reg [31:0] ct_buffer [0:191];
    reg [31:0] ss_server [0:7];
    reg [31:0] ss_client [0:7];
    reg [7:0] pk_count, ct_count, ss_count;
    
    // UART transmitter
    reg uart_tx_reg;
    reg [13:0] uart_shift;
    reg [3:0] uart_bit_cnt;
    reg uart_active;
    reg [7:0] uart_byte;
    reg [3:0] uart_state;
    reg [7:0] uart_byte_queue [0:15];
    reg [3:0] uart_head, uart_tail;
    
    // LED status
    assign led_status[0] = test_state_reg[0];
    assign led_status[1] = test_state_reg[1];
    assign led_status[2] = test_state_reg[2];
    assign led_status[3] = test_state_reg[3];
    assign led_status[4] = test_state_reg[4];
    assign led_status[5] = test_state_reg[5];
    
    // UART transmitter (115200 baud @ 100MHz)
    always @(posedge clk) begin
        if (!rst_n) begin
            uart_tx_reg <= 1'b1;
            uart_active <= 1'b0;
            uart_bit_cnt <= 4'd0;
            uart_shift <= 14'h3FFF;
            uart_active <= 1'b0;
            uart_state <= 4'd0;
            uart_head <= 4'd0;
            uart_tail <= 4'd0;
        end else begin
            if (!uart_active && uart_head != uart_tail) begin
                uart_byte <= uart_byte_queue[uart_tail];
                uart_tail <= uart_tail + 1;
                uart_active <= 1'b1;
                uart_shift <= {1'b1, uart_byte_queue[uart_tail], 1'b0}; // stop, data, start
                uart_bit_cnt <= 4'd0;
                uart_tx_reg <= 1'b0; // Start bit
                uart_active <= 1'b1;
            end else if (uart_active) begin
                if (uart_bit_cnt < 10) begin
                    uart_tx_reg <= uart_shift[uart_bit_cnt];
                    uart_bit_cnt <= uart_bit_cnt + 1;
                end else begin
                    uart_tx_reg <= 1'b1;
                    uart_active <= 1'b0;
                    uart_bit_cnt <= 4'd0;
                end
            end
        end
    end
    
    // UART queue management
    always @(posedge clk) begin
        if (!rst_n) begin
            uart_head <= 4'd0;
            uart_tail <= 4'd0;
        end else if (uart_head != ((uart_tail + 1) & 4'hF) && uart_byte_valid) begin
            uart_byte_queue[uart_tail] <= uart_byte;
            uart_tail <= uart_tail + 1;
        end
    end
    
    // Helper function to send byte via UART
    function automatic void uart_send_byte(input [7:0] byte);
        begin
            uart_byte <= byte;
            uart_byte_valid <= 1'b1;
        end
    endfunction
    
    reg uart_byte_valid;
    
    // Test state machine
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            test_state_reg <= 6'd0;
            cycle_counter <= 32'd0;
            pk_count <= 8'd0;
            ct_count <= 8'd0;
            ss_count <= 8'd0;
            test_result <= 6'd0;
            cycle_counter <= 32'd0;
        end else begin
            cycle_counter <= cycle_counter + 1;
            
            case (test_state_reg)
                6'd0: begin // IDLE
                    if (start) begin
                        test_state_reg <= 6'd1;
                    end
                end
                
                6'd1: begin // KEYGEN
                    if (server_valid && server_dout[31] == 1'b0) begin // PK data
                        if (pk_count < 200) begin
                            // Store PK
                            pk_count <= pk_count + 1;
                        end
                    end
                    if (server_valid && server_dout[31] == 1'b1) begin // SK data
                        test_state_reg <= 6'd2; // Move to ENCAP
                    end
                end
                
                6'd2: begin // ENCAP
                    if (client_valid && !client_dout[31]) begin // CT data
                        if (ct_count < 192) begin
                            ct_count <= ct_count + 1;
                        end
                    end
                    if (client_valid && client_dout[31]) begin // SS from client
                        test_state_reg <= 6'd3;
                    end
                end
                
                6'd3: begin // DECAP
                    if (server_valid && server_dout[31]) begin // SS from server
                        if (ss_count < 8) begin
                            ss_count <= ss_count + 1;
                        end else begin
                            test_state_reg <= 6'd4; // VERIFY
                        end
                    end
                end
                
                6'd4: begin // VERIFY
                    // Compare SS
                    if (ss_server == ss_client) begin
                        // PASS
                    end else begin
                        // FAIL
                    end
                    test_state_reg <= 6'd5;
                end
                
                6'd5: begin // DONE
                    // Send UART result
                    uart_byte <= test_result ? 8'h50 : 8'h46; // 'P' or 'F'
                    uart_byte_valid <= 1'b1;
                    test_state_reg <= 6'd6;
                end
                
                default: test_state_reg <= 6'd0;
            endcase
        end
    end
    
    // UART byte valid flag
    reg uart_byte_valid;
    
    // Connect signals
    assign server_wen = client_valid;
    assign client_wen = server_valid;
    
    // Loopback connections
    wire server_wen = client_valid;
    wire client_wen = server_valid;
    
    // Output assignments
    assign server_din = client_dout;
    assign client_din = server_dout;
    
    // Status outputs
    assign server_ready_pk = 1'b1;
    assign server_ready_c = 1'b1;
    assign server_req_pk = 1'b0;
    assign server_req_c = 1'b0;
    
    assign client_ready_pk = 1'b1;
    assign client_ready_c = 1'b1;
    assign client_req_pk = 1'b0;
    assign client_req_c = 1'b0;
    
    // LED status
    assign led_status = test_state_reg;

endmodule