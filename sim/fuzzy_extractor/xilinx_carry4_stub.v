`timescale 1ns / 1ps

module CARRY4 (
    input  wire       CI,
    input  wire       CYINIT,
    input  wire [3:0] DI,
    input  wire [3:0] S,
    output wire [3:0] CO,
    output wire [3:0] O
);
    wire [3:0] cy;

    assign cy[0] = CI | CYINIT;
    assign O[0]  = S[0] ^ cy[0];
    assign cy[1] = S[0] ? cy[0] : DI[0];
    assign O[1]  = S[1] ^ cy[1];
    assign cy[2] = S[1] ? cy[1] : DI[1];
    assign O[2]  = S[2] ^ cy[2];
    assign cy[3] = S[2] ? cy[2] : DI[2];
    assign O[3]  = S[3] ^ cy[3];

    assign CO[0] = cy[1];
    assign CO[1] = cy[2];
    assign CO[2] = cy[3];
    assign CO[3] = S[3] ? cy[3] : DI[3];
endmodule