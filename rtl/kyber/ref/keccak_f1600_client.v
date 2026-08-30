`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// keccak_f1600_client.v
// Same logic as server. See keccak_f1600_server.v for documentation.
//-----------------------------------------------------------------------------

module keccak_f1600_client(
    input wire clk,
    input wire rst,
    input wire init,
    input wire squeeze,
    input wire extend,
    input wire absorb,
    input wire go,
    input wire [31:0] din,
    output wire done,
    output wire [31:0] dout
);

    reg [1599:0] state_reg;
    reg [4:0]    round_count;
    reg [1:0]    perm_state;
    reg          perm_active;

    localparam S_IDLE    = 2'd0;
    localparam S_PERMUTE = 2'd1;
    localparam S_DONE    = 2'd2;

    wire [31:0] din_mux;
    assign din_mux = extend ? state_reg[31:0] :
                     absorb ? (state_reg[31:0] ^ din) :
                     din;

    wire [1599:0] algo_out;
    wire [1599:0] algo_in;
    wire [4:0]    rc_flag;

    assign algo_in = (round_count == 5'd0) ? state_reg : algo_out;

    ALGORITHM algo_inst (
        .Clk        (clk),
        .reset      (~rst),
        .en_in      (perm_active),
        .en_ctr     (perm_active),
        .padding_in (algo_in),
        .RC_id_in   (round_count),
        .RC_flag    (rc_flag),
        .data_out   (algo_out)
    );

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state_reg   <= 1600'h0;
            round_count <= 5'd0;
            perm_state  <= S_IDLE;
            perm_active <= 1'b0;
        end else begin
            case (perm_state)
                S_IDLE: begin
                    if (init) begin
                        // Reset FSM only, NOT state_reg
                        round_count <= 5'd0;
                        perm_active <= 1'b0;
                    end else begin
                        if (squeeze || extend) begin
                            state_reg <= {din_mux, state_reg[1599:32]};
                        end
                        if (go) begin
                            perm_state  <= S_PERMUTE;
                            perm_active <= 1'b1;
                            round_count <= 5'd0;
                        end
                    end
                end

                S_PERMUTE: begin
                    if (perm_active) begin
                        round_count <= round_count + 5'd1;
                        if (round_count == 5'd23) begin
                            perm_active <= 1'b0;
                            perm_state  <= S_DONE;
                        end
                    end
                end

                S_DONE: begin
                    state_reg   <= algo_out;
                    perm_state  <= S_IDLE;
                    round_count <= 5'd0;
                end

                default: perm_state <= S_IDLE;
            endcase
        end
    end

    assign done = (perm_state == S_DONE);
    assign dout = state_reg[31:0];

endmodule