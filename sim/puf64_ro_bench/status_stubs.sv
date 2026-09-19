`timescale 1ns / 1ps

// Test doubles used ONLY by tb_puf64_ro_bench_status.  They replace the
// physical RO leaf and the ripple counter so that the unmodified
// puf64_ro_bench FSM can be driven into timeout / count-zero / overflow
// states that a healthy silicon RO cannot reach on demand.  The FSM under
// test is the production source; only these two leaf cells are substituted.
module kp_ro_cell #(
    parameter int FREQ_OFFSET = 0
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic       en,
    input  logic [3:0] cfg,
    output logic       o
);
`ifdef TB_SCENARIO_TIMEOUT
    // Follow the system clock so the ripple counter advances every system
    // clock; the capture pipeline can then never see two equal samples and the
    // FSM must terminate via its timeout watchdog.
    assign o = clk;
`else
    assign o = 1'b0;
`endif
endmodule

module kp_ripple_counter #(
    parameter integer WIDTH = 16
)(
    input  logic             clk,
    input  logic             clear,
    output logic [WIDTH-1:0] q,
    output logic             overflow,
    output logic             presc_q
);
`ifdef TB_SCENARIO_TIMEOUT
    logic [WIDTH-1:0] free_run;
    always_ff @(posedge clk) begin
        if (clear) free_run <= '0;
        else       free_run <= free_run + 1'b1;
    end
    assign q        = free_run;
    assign overflow = 1'b0;
    assign presc_q  = 1'b0;
`elsif TB_SCENARIO_ZERO
    assign q        = '0;
    assign overflow = 1'b0;
    assign presc_q  = 1'b0;
`elsif TB_SCENARIO_OVERFLOW
    assign q        = {{(WIDTH - 1){1'b0}}, 1'b1};
    assign overflow = 1'b1;
    assign presc_q  = 1'b0;
`else
    assign q        = {{(WIDTH - 1){1'b0}}, 1'b1};
    assign overflow = 1'b0;
    assign presc_q  = 1'b0;
`endif
endmodule
