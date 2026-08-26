`timescale 1ns / 1ps
//-----------------------------------------------------------------------------
// kdf_keccak.sv — Key Derivation Function using SHAKE256
//
// Takes 192-bit key from Fuzzy Extractor, expands to 512-bit seed for Kyber.
// Uses keccak_f1600_server as the hash primitive.
//
// keccak_f1600_server interface semantics:
//   din_mux = extend ? state_reg[31:0]          (squeeze/shift only)
//           : absorb ? (state_reg[31:0] ^ din)  (XOR input into state)
//           : din;                               (load din directly)
//
//   When (squeeze || extend), the state shifts: {din_mux, state_reg[1599:32]}
//   So to ABSORB: set absorb=1, extend=0, squeeze=1 (squeeze triggers shift)
//   To SQUEEZE OUT: set absorb=0, extend=1, squeeze=0 (extend recycles)
//
// SHAKE256 padding (little-endian 32-bit words):
//   After 6 key words (192 bits), place domain separator 0x1F,
//   then zeros, then 0x80000000 at the last word of the rate block.
//   Rate = 1088 bits = 34 words. Total shift = 50 words (full state).
//-----------------------------------------------------------------------------

module kdf_keccak (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [191:0] key_in,      // 192-bit input from Fuzzy Extractor
    output reg          done,
    output reg  [511:0] seed_out     // 512-bit output (seed_d[255:0], seed_z[511:256])
);

    typedef enum logic [3:0] {
        S_IDLE           = 4'd0,
        S_CLEAR          = 4'd1,  // Clear stale state (50 zero shifts)
        S_INIT           = 4'd2,  // Pulse init to reset keccak FSM
        S_ABSORB_KEY     = 4'd3,  // Absorb 6 words of key
        S_ABSORB_PAD1    = 4'd4,  // Absorb SHAKE256 domain separator 0x1F
        S_ABSORB_ZERO    = 4'd5,  // Absorb zero-padding words
        S_ABSORB_PAD2    = 4'd6,  // Absorb final pad 0x80000000
        S_ABSORB_CAP     = 4'd7,  // Shift through 16 capacity words (no XOR)
        S_GO             = 4'd8,  // Trigger Keccak permutation
        S_WAIT           = 4'd9,  // Wait for permutation to complete
        S_SQUEEZE        = 4'd10, // Read 16 output words (512 bits)
        S_DONE           = 4'd11
    } state_t;

    state_t state, next_state;
    
    reg [5:0] word_cnt;
    reg [191:0] key_reg;

    // Keccak control signals
    reg k_init, k_extend, k_absorb, k_go, k_squeeze;
    reg [31:0] k_din;
    wire k_done;
    wire [31:0] k_dout;

    keccak_f1600_server keccak_inst (
        .clk     (clk),
        .rst     (~rst_n),
        .init    (k_init),
        .squeeze (k_squeeze),
        .extend  (k_extend),
        .absorb  (k_absorb),
        .go      (k_go),
        .din     (k_din),
        .done    (k_done),
        .dout    (k_dout)
    );

    // Sequential logic: state register, counters, data path
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            word_cnt <= 0;
            key_reg  <= 0;
            seed_out <= 0;
            done     <= 0;
        end else begin
            state <= next_state;
            done  <= 1'b0;   // done must be a 1-cycle pulse (SoC sticky latch samples it)

            case (state)
                S_IDLE: begin
                    if (start) begin
                        key_reg  <= key_in;
                        word_cnt <= 0;
                    end
                end
                
                S_CLEAR: begin
                    word_cnt <= word_cnt + 1;
                end
                
                S_INIT: begin
                    word_cnt <= 0;
                end
                
                S_ABSORB_KEY: begin
                    word_cnt <= word_cnt + 1;
                    key_reg  <= {32'd0, key_reg[191:32]};
                end
                
                S_ABSORB_PAD1: begin
                    word_cnt <= word_cnt + 1;
                end
                
                S_ABSORB_ZERO: begin
                    word_cnt <= word_cnt + 1;
                end
                
                S_ABSORB_PAD2: begin
                    word_cnt <= 0;
                end
                
                S_ABSORB_CAP: begin
                    word_cnt <= word_cnt + 1;
                end
                
                S_GO: begin
                    word_cnt <= 0;
                end
                
                S_SQUEEZE: begin
                    word_cnt <= word_cnt + 1;
                    seed_out <= {k_dout, seed_out[511:32]};
                end
                
                S_DONE: begin
                    done <= 1;
                end
                
                default: ;
            endcase
        end
    end

    // Combinational logic: next state + keccak control signals
    always_comb begin
        next_state = state;
        k_init    = 0;
        k_extend  = 0;
        k_absorb  = 0;
        k_go      = 0;
        k_squeeze = 0;
        k_din     = 32'd0;
        
        case (state)
            S_IDLE: begin
                if (start) next_state = S_CLEAR;
            end
            
            // ── Phase 0: Clear stale state by shifting 50 zero words ──
            // absorb=0, extend=0 → din_mux = din = 0
            // squeeze=1 → triggers shift {0, state_reg[1599:32]}
            S_CLEAR: begin
                k_squeeze = 1;
                k_din     = 32'd0;
                if (word_cnt == 49) next_state = S_INIT;
            end
            
            // ── Phase 1: Init (reset Keccak FSM, state is now all zeros) ──
            S_INIT: begin
                k_init = 1;
                next_state = S_ABSORB_KEY;
            end
            
            // ── Phase 2: Absorb 6 key words ──
            // absorb=1, extend=0 → din_mux = state_reg[31:0] ^ din
            // squeeze=1 → triggers shift {din_mux, state_reg[1599:32]}
            S_ABSORB_KEY: begin
                k_absorb  = 1;
                k_squeeze = 1;
                k_din     = key_reg[31:0];
                if (word_cnt == 5) next_state = S_ABSORB_PAD1;
            end
            
            // ── Phase 3: Absorb SHAKE256 domain separator ──
            S_ABSORB_PAD1: begin
                k_absorb  = 1;
                k_squeeze = 1;
                k_din     = 32'h0000001f; // SHAKE256 = 0x1F
                next_state = S_ABSORB_ZERO;
            end
            
            // ── Phase 4: Absorb zero-padding (words 8..32) ──
            S_ABSORB_ZERO: begin
                k_absorb  = 1;
                k_squeeze = 1;
                k_din     = 32'd0;
                // Rate = 34 words. We already absorbed 6+1=7 words.
                // word_cnt is at 7 when we enter. Need to reach word 32 (33rd word).
                // Then word 33 (index 33) is the final pad.
                if (word_cnt == 32) next_state = S_ABSORB_PAD2;
            end
            
            // ── Phase 5: Absorb final pad byte (word 33, the last rate word) ──
            S_ABSORB_PAD2: begin
                k_absorb  = 1;
                k_squeeze = 1;
                k_din     = 32'h80000000;
                next_state = S_ABSORB_CAP;
            end
            
            // ── Phase 6: Shift through 16 capacity words (no XOR) ──
            // extend=1 → din_mux = state_reg[31:0] (recycle, no corruption)
            // squeeze=0, but we need the shift...
            // Actually: squeeze||extend triggers shift. So extend=1 alone works.
            S_ABSORB_CAP: begin
                k_extend = 1;
                // 50 total - 34 rate = 16 capacity words (indices 0..15)
                if (word_cnt == 15) next_state = S_GO;
            end
            
            // ── Phase 7: Trigger Keccak permutation ──
            S_GO: begin
                k_go = 1;
                next_state = S_WAIT;
            end
            
            // ── Phase 8: Wait for permutation (24 rounds) ──
            S_WAIT: begin
                if (k_done) next_state = S_SQUEEZE;
            end
            
            // ── Phase 9: Squeeze 16 words (512 bits) ──
            // extend=1 → din_mux = state_reg[31:0] (shift without corruption)
            S_SQUEEZE: begin
                k_extend = 1;
                if (word_cnt == 15) next_state = S_DONE;
            end
            
            S_DONE: begin
                if (!start) next_state = S_IDLE;
            end
            
            default: next_state = S_IDLE;
        endcase
    end
endmodule
