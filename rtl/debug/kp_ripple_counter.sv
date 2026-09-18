`timescale 1ns / 1ps

// Local ripple counter: explicit FDCE prescaler (divide by 2) followed by
// WIDTH toggle stages (D = ~Q).  Spec (verified by simulation):
//   q = ceil(N_ro_edges / 2) mod 2**WIDTH   (counts prescaler rising edges)
// Each Q clocks only the next stage, so every clock net has fanout 1 and no
// RO/prescaler net is promoted to a global clock buffer.
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
    assign chain[0] = presc_q;
    genvar k;
    generate
        for (k = 0; k < WIDTH; k = k + 1) begin : stage
            (* DONT_TOUCH = "true" *) FDCE ff (
                .Q(q[k]), .C(chain[k]), .CE(1'b1), .CLR(clear), .D(~q[k])
            );
            // Next stage is clocked by the falling edge of this stage (~Q) so
            // the chain counts UP; clocking on rising Q would count down.
            assign chain[k+1] = ~q[k];
        end
    endgenerate
endmodule
