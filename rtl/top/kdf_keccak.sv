`timescale 1ns / 1ps
`default_nettype none

// Key derivation used between the fuzzy extractor and Kyber subsystem.
//
// Function: SHAKE256(key_in as 24 little-endian bytes, 64 output bytes).
// The byte-oriented FIPS 202 controller handles padding and permutation block
// boundaries internally.  seed_out keeps the historical project convention:
// digest byte 0 is stored in seed_out[7:0].
module kdf_keccak (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [191:0] key_in,
    output reg          done,
    output reg  [511:0] seed_out
);

    localparam [2:0] ST_IDLE  = 3'd0;
    localparam [2:0] ST_START = 3'd1;
    localparam [2:0] ST_FEED  = 3'd2;
    localparam [2:0] ST_READ  = 3'd3;
    localparam [2:0] ST_WAIT  = 3'd4;

    reg [2:0]   state;
    reg [5:0]   byte_count;
    reg [191:0] key_shift;

    wire        sponge_start;
    wire        sponge_in_ready;
    wire        sponge_out_valid;
    wire [7:0]  sponge_out_data;
    wire        sponge_out_last;
    wire        sponge_done;
    wire        sponge_error;
    wire        sponge_busy_unused;

    assign sponge_start = (state == ST_START);

    fips202_sponge sponge (
        .clk           (clk),
        .rst_n         (rst_n),
        .start         (sponge_start),
        .mode          (2'b01),       // SHAKE256
        .msg_len_bytes (32'd24),
        .out_len_bytes (32'd64),
        .in_valid      (state == ST_FEED),
        .in_ready      (sponge_in_ready),
        .in_data       (key_shift[7:0]),
        .out_valid     (sponge_out_valid),
        .out_ready     (state == ST_READ),
        .out_data      (sponge_out_data),
        .out_last      (sponge_out_last),
        .busy          (sponge_busy_unused),
        .done          (sponge_done),
        .error         (sponge_error)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= ST_IDLE;
            byte_count <= 6'd0;
            key_shift  <= 192'd0;
            seed_out   <= 512'd0;
            done       <= 1'b0;
        end else begin
            done <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (start) begin
                        key_shift  <= key_in;
                        seed_out   <= 512'd0;
                        byte_count <= 6'd0;
                        state      <= ST_START;
                    end
                end

                ST_START: begin
                    // sponge_start is asserted throughout this cycle.
                    state <= ST_FEED;
                end

                ST_FEED: begin
                    if (sponge_in_ready) begin
                        key_shift <= {8'd0, key_shift[191:8]};
                        if (byte_count == 6'd23) begin
                            byte_count <= 6'd0;
                            state      <= ST_READ;
                        end else begin
                            byte_count <= byte_count + 6'd1;
                        end
                    end
                end

                ST_READ: begin
                    if (sponge_out_valid) begin
                        seed_out[(byte_count * 8) +: 8] <= sponge_out_data;
                        if (sponge_out_last) begin
                            byte_count <= 6'd0;
                            state      <= ST_WAIT;
                        end else begin
                            byte_count <= byte_count + 6'd1;
                        end
                    end
                end

                ST_WAIT: begin
                    if (sponge_done) begin
                        // Configuration is fixed and valid, so an error here
                        // indicates an internal protocol fault.  Return a
                        // deterministic all-zero result instead of stale data.
                        if (sponge_error)
                            seed_out <= 512'd0;
                        done  <= 1'b1;
                        state <= ST_IDLE;
                    end
                end

                default: begin
                    seed_out <= 512'd0;
                    state    <= ST_IDLE;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
