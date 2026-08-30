`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// keccak_f1600_server.v — DEBUG VERSION with init fix
//
// CRITICAL FIX: init does NOT clear state_reg. In the VHDL design,
// RegisterFDRE.RST (which clears Q_buf) is connected to the SYSTEM RESET,
// not to keccak_init. The keccak_init signal only resets the StateMachine
// to S_INIT. This allows Kyber_Server's protocol to work:
//   1. Load data into FIFO → hash_core shifts into keccak state
//   2. keccak_init_pulse → reset FSM (data persists in shift register!)
//   3. Final word + padding → go → permutation on the absorbed data
//-----------------------------------------------------------------------------

module keccak_f1600_server(
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

    // ======================== DEBUG COUNTERS ========================
    `ifdef KYBER_DEBUG
    reg [31:0] dbg_cycle;
    reg [15:0] dbg_absorb_cnt;
    reg [15:0] dbg_squeeze_cnt;
    reg [7:0]  dbg_go_cnt;
    reg [7:0]  dbg_done_cnt;
    reg [1:0]  dbg_prev_state;
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            dbg_cycle <= 0;
            dbg_absorb_cnt <= 0;
            dbg_squeeze_cnt <= 0;
            dbg_go_cnt <= 0;
            dbg_done_cnt <= 0;
            dbg_prev_state <= S_IDLE;
        end else begin
            dbg_cycle <= dbg_cycle + 1;
            dbg_prev_state <= perm_state;
            
            if (absorb && (squeeze || extend)) dbg_absorb_cnt <= dbg_absorb_cnt + 1;
            if ((squeeze || extend) && !absorb) dbg_squeeze_cnt <= dbg_squeeze_cnt + 1;
            if (go) dbg_go_cnt <= dbg_go_cnt + 1;
            if (done) dbg_done_cnt <= dbg_done_cnt + 1;
        end
    end
    
    always @(posedge clk) begin
        if (!rst && dbg_cycle < 2000) begin
            if (go)
                $display("[KECCAK_SRV @%0d] GO! squeeze=%b absorb=%b din=%08h state[31:0]=%08h perm_state=%0d",
                    dbg_cycle, squeeze, absorb, din, state_reg[31:0], perm_state);
            
            if (done)
                $display("[KECCAK_SRV @%0d] DONE! state[31:0]=%08h state[63:32]=%08h algo_out[31:0]=%08h",
                    dbg_cycle, state_reg[31:0], state_reg[63:32], algo_out[31:0]);
            
            if (init)
                $display("[KECCAK_SRV @%0d] INIT (FSM reset only, state preserved) state[31:0]=%08h",
                    dbg_cycle, state_reg[31:0]);
            
            if (perm_state != dbg_prev_state)
                $display("[KECCAK_SRV @%0d] STATE %0d -> %0d", dbg_cycle, dbg_prev_state, perm_state);
            
            if ((squeeze || extend) && absorb && dbg_absorb_cnt < 20)
                $display("[KECCAK_SRV @%0d] ABSORB #%0d: din=%08h din_mux=%08h -> state[31:0]=%08h",
                    dbg_cycle, dbg_absorb_cnt, din, din_mux, state_reg[31:0]);
            
            if ((squeeze || extend) && !absorb && dbg_squeeze_cnt < 40)
                $display("[KECCAK_SRV @%0d] SQUEEZE #%0d: din=%08h dout=%08h extend=%b",
                    dbg_cycle, dbg_squeeze_cnt, din, state_reg[31:0], extend);
        end
        
        if (!rst && dbg_cycle > 0 && dbg_cycle % 10000 == 0)
            $display("[KECCAK_SRV @%0d] SUMMARY: absorbs=%0d squeezes=%0d gos=%0d dones=%0d perm_state=%0d",
                dbg_cycle, dbg_absorb_cnt, dbg_squeeze_cnt, dbg_go_cnt, dbg_done_cnt, perm_state);
    end
    `endif
    // ======================== END DEBUG ========================

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state_reg   <= 1600'h0;    // SYSTEM RESET: clear state
            round_count <= 5'd0;
            perm_state  <= S_IDLE;
            perm_active <= 1'b0;
        end else begin
            case (perm_state)
                S_IDLE: begin
                    if (init) begin
                        // INIT: Reset FSM only, DO NOT clear state_reg!
                        // Matches VHDL where RegisterFDRE.RST is system reset,
                        // and keccak_init only resets the StateMachine.
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
