`timescale 1ns / 1ps

// DIAGNOSTIC bench endpoint core (PUF64 Diagnostic Bench Protocol v1 / D1).
// Byte-level RX/TX with a strict ready/valid handshake; the UART PHY lives in
// the board wrapper.  Not a production campaign endpoint.
module puf64_bench_diag #(
    parameter integer NUM_RO = 4,
    parameter integer REF_CYCLES = 1023,
    parameter integer INPUT_CLOCK_HZ = 50000000,
    parameter integer SYSTEM_CLOCK_HZ = 100000000,
    parameter integer BUILD_ID = 16'h0001,
    parameter integer TOPOLOGY_ID = 16'hC0DE,
    parameter integer RO_BITS = (NUM_RO <= 1) ? 1 : $clog2(NUM_RO)
)(
    input  wire               clk,
    input  wire               rst_n,
    input  wire               rx_dv,
    input  wire [7:0]         rx_byte,
    input  wire               tx_ready,
    output wire               tx_valid,
    output wire [7:0]         tx_data,
    input  wire               mmcm_locked,
    output reg                bench_start,
    input  wire               bench_done,
    input  wire               telemetry_valid,
    input  wire               telemetry_stable,
    input  wire               telemetry_timeout,
    input  wire [RO_BITS-1:0] telemetry_pair_a,
    input  wire [RO_BITS-1:0] telemetry_pair_b,
    input  wire [31:0]        telemetry_count0,
    input  wire [31:0]        telemetry_count1
);
    localparam integer BITMAP_BYTES = (NUM_RO + 7) / 8;

    localparam [7:0] CMD_INFO = 8'h00;
    localparam [7:0] CMD_RUN = 8'h01;
    localparam [7:0] CMD_STATUS = 8'h02;
    localparam [7:0] CMD_READ = 8'h03;
    localparam [7:0] CMD_ABORT = 8'h04;

    localparam [7:0] ERR_BUSY = 8'hE1;
    localparam [7:0] ERR_NOT_DONE = 8'hE2;
    localparam [7:0] ERR_RANGE = 8'hE3;
    localparam [7:0] ERR_UNKNOWN = 8'hEE;

    reg [15:0] ro_count [0:NUM_RO-1];
    reg [NUM_RO-1:0] ro_valid;
    reg [NUM_RO-1:0] ro_stable;
    reg [NUM_RO-1:0] ro_timeout;
    reg [NUM_RO-1:0] ro_wrap;

    reg run_busy;
    reg run_done;
    reg [7:0] run_error;

    reg [7:0] tx_buf [0:47];
    reg [6:0] tx_len;
    reg [6:0] tx_index;
    reg [1:0] rx_state;

    assign tx_valid = (tx_index < tx_len);
    assign tx_data = tx_buf[tx_index];

    integer b;
    always @(posedge clk) begin
        if (!rst_n) begin
            tx_len <= 7'd0;
            tx_index <= 7'd0;
            rx_state <= 2'd0;
            bench_start <= 1'b0;
            run_busy <= 1'b0;
            run_done <= 1'b0;
            run_error <= 8'h00;
            ro_valid <= '0;
            ro_stable <= '0;
            ro_timeout <= '0;
            ro_wrap <= '0;
        end else begin
            bench_start <= 1'b0;

            if (tx_valid && tx_ready)
                tx_index <= tx_index + 7'd1;

            if (telemetry_valid && telemetry_pair_a[0] == 1'b0 &&
                telemetry_pair_b == telemetry_pair_a + 1'b1) begin
                ro_count[telemetry_pair_a] <= telemetry_count0[15:0];
                ro_count[telemetry_pair_b] <= telemetry_count1[15:0];
                ro_valid[telemetry_pair_a] <= 1'b1;
                ro_valid[telemetry_pair_b] <= 1'b1;
                ro_stable[telemetry_pair_a] <= telemetry_stable;
                ro_stable[telemetry_pair_b] <= telemetry_stable;
                ro_timeout[telemetry_pair_a] <= telemetry_timeout;
                ro_timeout[telemetry_pair_b] <= telemetry_timeout;
            end

            if (run_busy && bench_done) begin
                run_busy <= 1'b0;
                run_done <= 1'b1;
            end

            if (rx_dv) begin
                if (rx_state == 2'd1) begin
                    rx_state <= 2'd0;
                    if (!run_done || run_busy) begin
                        run_error <= ERR_NOT_DONE;
                        tx_buf[0] <= 8'hFF; tx_buf[1] <= ERR_NOT_DONE;
                        tx_len <= 7'd2; tx_index <= 7'd0;
                    end else if (rx_byte >= NUM_RO) begin
                        run_error <= ERR_RANGE;
                        tx_buf[0] <= 8'hFF; tx_buf[1] <= ERR_RANGE;
                        tx_len <= 7'd2; tx_index <= 7'd0;
                    end else begin
                        tx_buf[0] <= 8'hA6;
                        tx_buf[1] <= 8'hD1;
                        tx_buf[2] <= BUILD_ID[7:0];
                        tx_buf[3] <= BUILD_ID[15:8];
                        tx_buf[4] <= NUM_RO[7:0];
                        tx_buf[5] <= TOPOLOGY_ID[7:0];
                        tx_buf[6] <= TOPOLOGY_ID[15:8];
                        tx_buf[7] <= rx_byte;
                        tx_buf[8] <= ro_count[rx_byte][7:0];
                        tx_buf[9] <= ro_count[rx_byte][15:8];
                        tx_buf[10] <= {3'b0, mmcm_locked, ro_wrap[rx_byte],
                                       ro_timeout[rx_byte], ro_stable[rx_byte],
                                       ro_valid[rx_byte]};
                        tx_buf[11] <= INPUT_CLOCK_HZ[7:0];
                        tx_buf[12] <= INPUT_CLOCK_HZ[15:8];
                        tx_buf[13] <= INPUT_CLOCK_HZ[23:16];
                        tx_buf[14] <= INPUT_CLOCK_HZ[31:24];
                        tx_buf[15] <= SYSTEM_CLOCK_HZ[7:0];
                        tx_buf[16] <= SYSTEM_CLOCK_HZ[15:8];
                        tx_buf[17] <= SYSTEM_CLOCK_HZ[23:16];
                        tx_buf[18] <= SYSTEM_CLOCK_HZ[31:24];
                        tx_buf[19] <= REF_CYCLES[7:0];
                        tx_buf[20] <= REF_CYCLES[15:8];
                        tx_buf[21] <= 8'h00;
                        tx_len <= 7'd22; tx_index <= 7'd0;
                    end
                end else if (tx_index >= tx_len) begin
                    case (rx_byte)
                        CMD_INFO: begin
                            tx_buf[0] <= 8'h50; tx_buf[1] <= 8'h55;
                            tx_buf[2] <= 8'h46; tx_buf[3] <= 8'hD1;
                            tx_buf[4] <= BUILD_ID[7:0];
                            tx_buf[5] <= BUILD_ID[15:8];
                            tx_buf[6] <= NUM_RO[7:0];
                            tx_buf[7] <= TOPOLOGY_ID[7:0];
                            tx_buf[8] <= TOPOLOGY_ID[15:8];
                            tx_buf[9] <= REF_CYCLES[7:0];
                            tx_buf[10] <= REF_CYCLES[15:8];
                            tx_buf[11] <= {7'b0, mmcm_locked};
                            tx_buf[12] <= INPUT_CLOCK_HZ[7:0];
                            tx_buf[13] <= INPUT_CLOCK_HZ[15:8];
                            tx_buf[14] <= INPUT_CLOCK_HZ[23:16];
                            tx_buf[15] <= INPUT_CLOCK_HZ[31:24];
                            tx_buf[16] <= SYSTEM_CLOCK_HZ[7:0];
                            tx_buf[17] <= SYSTEM_CLOCK_HZ[15:8];
                            tx_buf[18] <= SYSTEM_CLOCK_HZ[23:16];
                            tx_buf[19] <= SYSTEM_CLOCK_HZ[31:24];
                            tx_buf[20] <= 8'h01;
                            tx_len <= 7'd21; tx_index <= 7'd0;
                        end
                        CMD_RUN: begin
                            if (run_busy) begin
                                run_error <= ERR_BUSY;
                                tx_buf[0] <= 8'hFF; tx_buf[1] <= ERR_BUSY;
                                tx_len <= 7'd2; tx_index <= 7'd0;
                            end else begin
                                ro_valid <= '0; ro_stable <= '0;
                                ro_timeout <= '0; ro_wrap <= '0;
                                run_error <= 8'h00; run_done <= 1'b0;
                                run_busy <= 1'b1; bench_start <= 1'b1;
                            end
                        end
                        CMD_STATUS: begin
                            tx_buf[0] <= 8'hA5;
                            tx_buf[1] <= {7'b0, run_busy};
                            tx_buf[2] <= {7'b0, run_done};
                            tx_buf[3] <= run_error;
                            for (b = 0; b < BITMAP_BYTES; b = b + 1)
                                tx_buf[4+b] <= ro_valid[b*8 +: 8];
                            tx_len <= (4 + BITMAP_BYTES);
                            tx_index <= 7'd0;
                        end
                        CMD_READ: rx_state <= 2'd1;
                        CMD_ABORT: begin
                            run_busy <= 1'b0;
                            run_done <= 1'b0;
                            run_error <= 8'h00;
                        end
                        default: begin
                            run_error <= ERR_UNKNOWN;
                            tx_buf[0] <= 8'hFF; tx_buf[1] <= ERR_UNKNOWN;
                            tx_len <= 7'd2; tx_index <= 7'd0;
                        end
                    endcase
                end
            end
        end
    end
endmodule
