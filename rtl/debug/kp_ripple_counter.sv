`timescale 1ns / 1ps

// Local ripple counter with an explicit overflow stage.  WIDTH transmitted
// count bits plus one high overflow bit -> STAGES = WIDTH+1 toggle FDCEs.
// Every stage is clocked by the rising edge of the previous stage's ~Q, so the
// chain counts UP.  Spec:
//   count = floor(N_ro_edges / 2) mod 2**WIDTH
//   overflow = 1 iff floor(N_ro_edges / 2) >= 2**WIDTH
module kp_ripple_counter #(
    parameter integer WIDTH = 16
)(
    input  logic             clk,
    input  logic             clear,
    output logic [WIDTH-1:0] q,
    output logic             overflow,
    output logic             presc_q
);
    localparam integer STAGES = WIDTH + 1;

    (* DONT_TOUCH = "true" *) FDCE presc_fdce (
        .Q(presc_q), .C(clk), .CE(1'b1), .CLR(clear), .D(~presc_q)
    );

    (* keep = "true" *) logic [STAGES-1:0] qq;
    wire [STAGES:0] chain;
    assign chain[0] = ~presc_q;
    genvar k;
    generate
        for (k = 0; k < STAGES; k = k + 1) begin : stage
            (* DONT_TOUCH = "true" *) FDCE ff (
                .Q(qq[k]), .C(chain[k]), .CE(1'b1), .CLR(clear), .D(~qq[k])
            );
            assign chain[k+1] = ~qq[k];
        end
    endgenerate

    assign q = qq[WIDTH-1:0];
    assign overflow = qq[WIDTH];
endmodule
