module ADDER (
    input wire a,
    input wire [4:0] b,
    output wire [4:0] Y
);
    wire [4:0] a_t;
    assign a_t = {4'b0000, a};
    assign Y = a_t + b;
endmodule
