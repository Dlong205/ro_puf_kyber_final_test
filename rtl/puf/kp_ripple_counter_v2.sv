`timescale 1ns / 1ps

// R1 macro-V2 ripple counter.  Logically identical to kp_ripple_counter
// (which is frozen for the golden image and must not be modified):
//   count = floor(N_ro_edges / 2) mod 2**WIDTH
//   overflow = 1 iff floor(N_ro_edges / 2) >= 2**WIDTH
//
// Physical difference: every inversion is an explicit in-hierarchy LUT1
// (INIT 2'h1, DONT_TOUCH) instead of a bare `~` assign that synthesis
// flattened out of the macro root (golden: 1088 chain INVs at top level).
// Per counter: 1 prescaler INV + STAGES stage INVs.  The prescaler INV output
// fans out to stage[0].C and presc.D (toggle feedback); each stage[k] INV
// output fans out to stage[k+1].C (k < STAGES-1, chain net) and stage[k].D.
// 64 counters -> 64 prescaler INVs + 1088 stage INVs = 1152 explicit LUT1,
// all under the macro root.
module kp_ripple_counter_v2 #(
    parameter integer WIDTH = 16
)(
    input  logic             clk,
    input  logic             clear,
    output logic [WIDTH-1:0] q,
    output logic             overflow,
    output logic             presc_q
);
    localparam integer STAGES = WIDTH + 1;

    (* keep = "true" *) logic n_presc;
    (* keep = "true" *) logic [STAGES-1:0] n_qq;

    (* DONT_TOUCH = "true" *) LUT1 #(
        .INIT(2'h1)
    ) inv_presc (
        .O(n_presc), .I0(presc_q)
    );

    (* DONT_TOUCH = "true" *) FDCE presc_fdce (
        .Q(presc_q), .C(clk), .CE(1'b1), .CLR(clear), .D(n_presc)
    );

    (* keep = "true" *) logic [STAGES-1:0] qq;
    wire [STAGES:0] chain;
    assign chain[0] = n_presc;
    genvar k;
    generate
        for (k = 0; k < STAGES; k = k + 1) begin : stage
            (* DONT_TOUCH = "true" *) LUT1 #(
                .INIT(2'h1)
            ) inv (
                .O(n_qq[k]), .I0(qq[k])
            );
            (* DONT_TOUCH = "true" *) FDCE ff (
                .Q(qq[k]), .C(chain[k]), .CE(1'b1), .CLR(clear), .D(n_qq[k])
            );
            assign chain[k+1] = n_qq[k];
        end
    endgenerate

    assign q = qq[WIDTH-1:0];
    assign overflow = qq[WIDTH];
endmodule
