`timescale 1ns / 1ps

module kp_puf_control #(
    parameter int BIT_COUNT = 264,
    parameter int REF_CYCLES = 255
)(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    output logic        lfsr_dv,
    output logic        count_en,
    output logic        ref_en,
    output logic        lfsr_en,
    output logic        sr_en,
    output logic        ro_en,
    output logic        cnt_rst,
    output logic        busy,
    output logic        done
);

    typedef enum logic [2:0] {
        S_IDLE    = 3'd0,
        S_LOAD    = 3'd1,
        S_MEASURE = 3'd2,
        S_CAPTURE = 3'd3,
        S_NEXT    = 3'd4,
        S_DONE    = 3'd5
    } state_t;

    state_t state, next_state;
    logic [8:0] bit_cnt;
    logic [15:0] ref_cycle_cnt;
    logic       bit_done;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            bit_cnt       <= '0;
            ref_cycle_cnt <= '0;
            bit_done      <= 1'b0;
        end else begin
            state <= next_state;
            
            case (state)
                S_IDLE: begin
                    bit_cnt       <= '0;
                    ref_cycle_cnt <= '0;
                    bit_done      <= 1'b0;
                end
                S_LOAD: begin
                    bit_cnt       <= '0;
                    ref_cycle_cnt <= '0;
                    bit_done      <= 1'b0;
                end
                S_MEASURE: begin
                    ref_cycle_cnt <= ref_cycle_cnt + 1;
                end
                S_CAPTURE: begin
                    bit_done      <= 1'b1;
                    ref_cycle_cnt <= '0;
                end
                S_NEXT: begin
                    bit_cnt       <= bit_cnt + 1;
                    bit_done      <= 1'b0;
                    ref_cycle_cnt <= '0;
                end
                S_DONE: begin
                    bit_cnt       <= '0;
                    ref_cycle_cnt <= '0;
                    bit_done      <= 1'b0;
                end
            endcase
            
            // Debug
            `ifndef SYNTHESIS
            if (state != next_state) begin
                $display("CTRL FSM: %s -> %s, bit_cnt=%0d, ref_cycle_cnt=%0d", 
                    state.name(), next_state.name(), bit_cnt, ref_cycle_cnt);
            end
            `endif
        end
    end

    always_comb begin
        next_state = state;
        case (state)
            S_IDLE:    if (start)                    next_state = S_LOAD;
            S_LOAD:    next_state = S_MEASURE;
            S_MEASURE: if (ref_cycle_cnt == REF_CYCLES - 1) next_state = S_CAPTURE;
            S_CAPTURE: next_state = S_NEXT;
            S_NEXT:    if (bit_cnt == BIT_COUNT - 1) next_state = S_DONE;
                       else                        next_state = S_MEASURE;
            S_DONE:    next_state = S_IDLE;
        endcase
    end

    always_comb begin
        lfsr_dv = 1'b0;
        count_en = 1'b0;
        ref_en = 1'b0;
        lfsr_en = 1'b0;
        sr_en = 1'b0;
        ro_en = 1'b0;
        cnt_rst = 1'b1;
        busy = 1'b0;
        done = 1'b0;

        case (state)
            S_IDLE: begin
                cnt_rst = 1'b1;
            end
            S_LOAD: begin
                lfsr_dv = 1'b1;
                lfsr_en = 1'b1;
                cnt_rst = 1'b1;
                busy = 1'b1;
            end
            S_MEASURE: begin
                count_en = 1'b1;
                ref_en = 1'b1;
                lfsr_en = 1'b0;
                ro_en = 1'b1;
                cnt_rst = 1'b0;
                busy = 1'b1;
            end
            S_CAPTURE: begin
                count_en = 1'b1;
                lfsr_en = 1'b0;
                sr_en = 1'b1;
                ro_en = 1'b0;
                cnt_rst = 1'b0;
                busy = 1'b1;
            end
            S_NEXT: begin
                lfsr_en = 1'b1;
                ro_en   = 1'b1;  // ROs must oscillate so counter clock is active
                cnt_rst = 1'b1;  // now counter actually sees this reset!
                busy = 1'b1;
            end
            S_DONE: begin
                done = 1'b1;
                cnt_rst = 1'b1;
            end
        endcase
    end

endmodule