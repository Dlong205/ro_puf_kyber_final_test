`timescale 1ns / 1ps

// Local ripple counter: explicit FDCE prescaler (divide by 2) followed by
// WIDTH toggle stages (D = ~Q).  Every stage is clocked by the rising edge of
// the previous stage's ~Q, so the chain counts UP.  Spec (verified against an
// independent truth table):
//   q = floor(N_ro_edges / 2) mod 2**WIDTH
//   N: 0 1 2 3 4 -> q: 0 0 1 1 2
// Each Q clocks only the next stage, so every clock net has fanout 1 and no
// RO/prescaler net is promoted to a global clock buffer.
(* KEEP_HIERARCHY = "yes" *)
module kp_ripple_counter #(
    parameter integer WIDTH = 16
)(
    input  logic             clk,
    input  logic             clear,
    output logic [WIDTH-1:0] q,
    output logic             presc_q
);
    (* DONT_TOUCH = "true" *) FDCE presc_fdce (
        .Q(presc_q), .C(clk), .CE(1'b1), .CLR(clear), .D(~presc_q)
    );

    wire [WIDTH:0] chain;
    assign chain[0] = ~presc_q;
    genvar k;
    generate
        for (k = 0; k < WIDTH; k = k + 1) begin : stage
            (* DONT_TOUCH = "true" *) FDCE ff (
                .Q(q[k]), .C(chain[k]), .CE(1'b1), .CLR(clear), .D(~q[k])
            );
            assign chain[k+1] = ~q[k];
        end
    endgenerate
endmodule
