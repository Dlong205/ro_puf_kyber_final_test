`timescale 1ns / 1ps
`default_nettype none

// Area-oriented fixed-profile KDF for the CPU-free Edge role.
//
// SHAKE256(key_in as 24 little-endian bytes, 64 output bytes).  Unlike the
// legacy 1600-bit round datapath, this implementation serializes theta by
// column and chi by row.  Latency is intentionally traded for LUT area; the
// complete KDF still finishes before ML-KEM is launched.
module kdf_keccak_compact (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         zeroize,
    input  wire         start,
    input  wire [191:0] key_in,
    output reg          done,
    output reg  [511:0] seed_out
);
    localparam [2:0] ST_IDLE   = 3'd0;
    localparam [2:0] ST_COL    = 3'd1;
    localparam [2:0] ST_THETA  = 3'd2;
    localparam [2:0] ST_RHOPI  = 3'd3;
    localparam [2:0] ST_CHI    = 3'd4;
    localparam [2:0] ST_IOTA   = 3'd5;
    localparam [2:0] ST_FINISH = 3'd6;

    reg [2:0] state;
    reg [4:0] round_index;
    reg [2:0] step_index;
    reg [63:0] lane_a [0:24];
    reg [63:0] lane_b [0:24];
    reg [63:0] column [0:4];
    integer i;

    function automatic [63:0] rol64;
        input [63:0] value;
        input integer amount;
        begin
            if (amount == 0)
                rol64 = value;
            else
                rol64 = (value << amount) | (value >> (64-amount));
        end
    endfunction

    function automatic integer rho_offset;
        input integer lane;
        begin
            case (lane)
                 0: rho_offset =  0;  1: rho_offset =  1;
                 2: rho_offset = 62;  3: rho_offset = 28;
                 4: rho_offset = 27;  5: rho_offset = 36;
                 6: rho_offset = 44;  7: rho_offset =  6;
                 8: rho_offset = 55;  9: rho_offset = 20;
                10: rho_offset =  3; 11: rho_offset = 10;
                12: rho_offset = 43; 13: rho_offset = 25;
                14: rho_offset = 39; 15: rho_offset = 41;
                16: rho_offset = 45; 17: rho_offset = 15;
                18: rho_offset = 21; 19: rho_offset =  8;
                20: rho_offset = 18; 21: rho_offset =  2;
                22: rho_offset = 61; 23: rho_offset = 56;
                default: rho_offset = 14;
            endcase
        end
    endfunction

    function automatic integer pi_index;
        input integer lane;
        integer x;
        integer y;
        begin
            x = lane % 5;
            y = lane / 5;
            pi_index = y + 5 * ((2*x + 3*y) % 5);
        end
    endfunction

    function automatic [63:0] round_constant;
        input [4:0] index;
        begin
            case (index)
                 0: round_constant = 64'h0000000000000001;
                 1: round_constant = 64'h0000000000008082;
                 2: round_constant = 64'h800000000000808a;
                 3: round_constant = 64'h8000000080008000;
                 4: round_constant = 64'h000000000000808b;
                 5: round_constant = 64'h0000000080000001;
                 6: round_constant = 64'h8000000080008081;
                 7: round_constant = 64'h8000000000008009;
                 8: round_constant = 64'h000000000000008a;
                 9: round_constant = 64'h0000000000000088;
                10: round_constant = 64'h0000000080008009;
                11: round_constant = 64'h000000008000000a;
                12: round_constant = 64'h000000008000808b;
                13: round_constant = 64'h800000000000008b;
                14: round_constant = 64'h8000000000008089;
                15: round_constant = 64'h8000000000008003;
                16: round_constant = 64'h8000000000008002;
                17: round_constant = 64'h8000000000000080;
                18: round_constant = 64'h000000000000800a;
                19: round_constant = 64'h800000008000000a;
                20: round_constant = 64'h8000000080008081;
                21: round_constant = 64'h8000000000008080;
                22: round_constant = 64'h0000000080000001;
                default: round_constant = 64'h8000000080008008;
            endcase
        end
    endfunction

    function automatic [63:0] chi_lane;
        input [63:0] x;
        input [63:0] y;
        input [63:0] z;
        begin
            chi_lane = x ^ ((~y) & z);
        end
    endfunction

    always @(posedge clk or negedge rst_n or posedge zeroize) begin
        if (!rst_n || zeroize) begin
            state       <= ST_IDLE;
            round_index <= 5'd0;
            step_index  <= 3'd0;
            seed_out    <= 512'd0;
            done        <= 1'b0;
            for (i = 0; i < 25; i = i + 1) begin
                lane_a[i] <= 64'd0;
                lane_b[i] <= 64'd0;
            end
            for (i = 0; i < 5; i = i + 1)
                column[i] <= 64'd0;
        end else begin
            done <= 1'b0;
            case (state)
                ST_IDLE: begin
                    if (start) begin
                        for (i = 0; i < 25; i = i + 1) begin
                            lane_a[i] <= 64'd0;
                            lane_b[i] <= 64'd0;
                        end
                        for (i = 0; i < 5; i = i + 1)
                            column[i] <= 64'd0;
                        // 24-byte message, SHAKE suffix 0x1f at byte 24,
                        // final pad bit at byte 135 of the 136-byte rate.
                        lane_a[0]  <= key_in[63:0];
                        lane_a[1]  <= key_in[127:64];
                        lane_a[2]  <= key_in[191:128];
                        lane_a[3]  <= 64'h000000000000001f;
                        lane_a[16] <= 64'h8000000000000000;
                        round_index <= 5'd0;
                        step_index  <= 3'd0;
                        seed_out    <= 512'd0;
                        state       <= ST_COL;
                    end
                end

                // theta: form one five-lane column parity per cycle.
                ST_COL: begin
                    case (step_index)
                        0: column[0] <= lane_a[0] ^ lane_a[5] ^ lane_a[10] ^ lane_a[15] ^ lane_a[20];
                        1: column[1] <= lane_a[1] ^ lane_a[6] ^ lane_a[11] ^ lane_a[16] ^ lane_a[21];
                        2: column[2] <= lane_a[2] ^ lane_a[7] ^ lane_a[12] ^ lane_a[17] ^ lane_a[22];
                        3: column[3] <= lane_a[3] ^ lane_a[8] ^ lane_a[13] ^ lane_a[18] ^ lane_a[23];
                        default: column[4] <= lane_a[4] ^ lane_a[9] ^ lane_a[14] ^ lane_a[19] ^ lane_a[24];
                    endcase
                    if (step_index == 3'd4) begin
                        step_index <= 3'd0;
                        state <= ST_THETA;
                    end else step_index <= step_index + 3'd1;
                end

                // Apply D[x] to all five lanes of one column per cycle.
                ST_THETA: begin
                    case (step_index)
                        0: begin
                            lane_a[0]  <= lane_a[0]  ^ column[4] ^ rol64(column[1],1);
                            lane_a[5]  <= lane_a[5]  ^ column[4] ^ rol64(column[1],1);
                            lane_a[10] <= lane_a[10] ^ column[4] ^ rol64(column[1],1);
                            lane_a[15] <= lane_a[15] ^ column[4] ^ rol64(column[1],1);
                            lane_a[20] <= lane_a[20] ^ column[4] ^ rol64(column[1],1);
                        end
                        1: begin
                            lane_a[1]  <= lane_a[1]  ^ column[0] ^ rol64(column[2],1);
                            lane_a[6]  <= lane_a[6]  ^ column[0] ^ rol64(column[2],1);
                            lane_a[11] <= lane_a[11] ^ column[0] ^ rol64(column[2],1);
                            lane_a[16] <= lane_a[16] ^ column[0] ^ rol64(column[2],1);
                            lane_a[21] <= lane_a[21] ^ column[0] ^ rol64(column[2],1);
                        end
                        2: begin
                            lane_a[2]  <= lane_a[2]  ^ column[1] ^ rol64(column[3],1);
                            lane_a[7]  <= lane_a[7]  ^ column[1] ^ rol64(column[3],1);
                            lane_a[12] <= lane_a[12] ^ column[1] ^ rol64(column[3],1);
                            lane_a[17] <= lane_a[17] ^ column[1] ^ rol64(column[3],1);
                            lane_a[22] <= lane_a[22] ^ column[1] ^ rol64(column[3],1);
                        end
                        3: begin
                            lane_a[3]  <= lane_a[3]  ^ column[2] ^ rol64(column[4],1);
                            lane_a[8]  <= lane_a[8]  ^ column[2] ^ rol64(column[4],1);
                            lane_a[13] <= lane_a[13] ^ column[2] ^ rol64(column[4],1);
                            lane_a[18] <= lane_a[18] ^ column[2] ^ rol64(column[4],1);
                            lane_a[23] <= lane_a[23] ^ column[2] ^ rol64(column[4],1);
                        end
                        default: begin
                            lane_a[4]  <= lane_a[4]  ^ column[3] ^ rol64(column[0],1);
                            lane_a[9]  <= lane_a[9]  ^ column[3] ^ rol64(column[0],1);
                            lane_a[14] <= lane_a[14] ^ column[3] ^ rol64(column[0],1);
                            lane_a[19] <= lane_a[19] ^ column[3] ^ rol64(column[0],1);
                            lane_a[24] <= lane_a[24] ^ column[3] ^ rol64(column[0],1);
                        end
                    endcase
                    if (step_index == 3'd4) begin
                        step_index <= 3'd0;
                        state <= ST_RHOPI;
                    end else step_index <= step_index + 3'd1;
                end

                // Rho rotations and Pi permutation are wiring-only and are
                // captured together into the alternate lane bank.
                ST_RHOPI: begin
                    for (i = 0; i < 25; i = i + 1)
                        lane_b[pi_index(i)] <= rol64(lane_a[i], rho_offset(i));
                    step_index <= 3'd0;
                    state <= ST_CHI;
                end

                // chi: update one 320-bit row per cycle.
                ST_CHI: begin
                    case (step_index)
                        0: begin
                            lane_a[0] <= chi_lane(lane_b[0],lane_b[1],lane_b[2]);
                            lane_a[1] <= chi_lane(lane_b[1],lane_b[2],lane_b[3]);
                            lane_a[2] <= chi_lane(lane_b[2],lane_b[3],lane_b[4]);
                            lane_a[3] <= chi_lane(lane_b[3],lane_b[4],lane_b[0]);
                            lane_a[4] <= chi_lane(lane_b[4],lane_b[0],lane_b[1]);
                        end
                        1: begin
                            lane_a[5] <= chi_lane(lane_b[5],lane_b[6],lane_b[7]);
                            lane_a[6] <= chi_lane(lane_b[6],lane_b[7],lane_b[8]);
                            lane_a[7] <= chi_lane(lane_b[7],lane_b[8],lane_b[9]);
                            lane_a[8] <= chi_lane(lane_b[8],lane_b[9],lane_b[5]);
                            lane_a[9] <= chi_lane(lane_b[9],lane_b[5],lane_b[6]);
                        end
                        2: begin
                            lane_a[10] <= chi_lane(lane_b[10],lane_b[11],lane_b[12]);
                            lane_a[11] <= chi_lane(lane_b[11],lane_b[12],lane_b[13]);
                            lane_a[12] <= chi_lane(lane_b[12],lane_b[13],lane_b[14]);
                            lane_a[13] <= chi_lane(lane_b[13],lane_b[14],lane_b[10]);
                            lane_a[14] <= chi_lane(lane_b[14],lane_b[10],lane_b[11]);
                        end
                        3: begin
                            lane_a[15] <= chi_lane(lane_b[15],lane_b[16],lane_b[17]);
                            lane_a[16] <= chi_lane(lane_b[16],lane_b[17],lane_b[18]);
                            lane_a[17] <= chi_lane(lane_b[17],lane_b[18],lane_b[19]);
                            lane_a[18] <= chi_lane(lane_b[18],lane_b[19],lane_b[15]);
                            lane_a[19] <= chi_lane(lane_b[19],lane_b[15],lane_b[16]);
                        end
                        default: begin
                            lane_a[20] <= chi_lane(lane_b[20],lane_b[21],lane_b[22]);
                            lane_a[21] <= chi_lane(lane_b[21],lane_b[22],lane_b[23]);
                            lane_a[22] <= chi_lane(lane_b[22],lane_b[23],lane_b[24]);
                            lane_a[23] <= chi_lane(lane_b[23],lane_b[24],lane_b[20]);
                            lane_a[24] <= chi_lane(lane_b[24],lane_b[20],lane_b[21]);
                        end
                    endcase
                    if (step_index == 3'd4) begin
                        step_index <= 3'd0;
                        state <= ST_IOTA;
                    end else step_index <= step_index + 3'd1;
                end

                ST_IOTA: begin
                    lane_a[0] <= lane_a[0] ^ round_constant(round_index);
                    if (round_index == 5'd23)
                        state <= ST_FINISH;
                    else begin
                        round_index <= round_index + 5'd1;
                        step_index <= 3'd0;
                        state <= ST_COL;
                    end
                end

                ST_FINISH: begin
                    seed_out <= {lane_a[7], lane_a[6], lane_a[5], lane_a[4],
                                 lane_a[3], lane_a[2], lane_a[1], lane_a[0]};
                    done <= 1'b1;
                    state <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule

`default_nettype wire
