/*
 * Xilinx carry-chain backend for compare_cla.
 * This is the only fuzzy-extractor RTL file allowed to instantiate CARRY4.
 */
`timescale 1ns / 1ps

`include "config.vh"

module compare_cla_xilinx #(
	parameter N = 7,
	parameter [N-1:0] CONST = 0,
	parameter EQ = 1,
	parameter W = 1
) (
	input [N-1:0] in,
	output out
);
	localparam OPTIM = (CONST[0] == EQ) && W == 1;
	localparam _N = OPTIM ? (N - 1) : N;
	wire [_N-1:0] _in;

	if (OPTIM)
		assign _in = in >> 1;
	else
		assign _in = in;

	localparam _B = `CONFIG_LUT_SZ / W;
	localparam B = _B ? _B : 1;
	localparam LUTS = (_N + B - 1) / B;
	localparam C = (LUTS + 3) / 4;

	wire [C*4-1:0] co;
	wire [C*4-1:0] _sin;
	wire [C-1:0] _cin;
	wire [LUTS-1:0] luts;
	genvar i;

	assign out = co[LUTS-1];

	for (i = 0; i < LUTS; i = i + 1) begin : LUT
		if ((i + 1) * B > N)
			assign luts[i] = _in[N-1:(LUTS-1)*B] == CONST[N-1:(LUTS-1)*B];
		else
			assign luts[i] = _in[i*B+:B] == CONST[i*B+:B];
	end
	assign _sin = luts;

	for (i = 0; i < C; i = i + 1) begin : CIN
		if (OPTIM)
			assign _cin[i] = i ? co[i*4-1] : in[0];
		else
			assign _cin[i] = i ? co[i*4-1] : EQ;
	end

	CARRY4 u_CARRY4 (
		.CO(co[3:0]),
		.O(),
		.CI(),
		.CYINIT(_cin[0]),
		.DI({4{!EQ}}),
		.S(_sin[3:0])
	);

	if (C > 1) begin
		CARRY4 u_CARRY4 [C-1:1] (
			.CO(co[C*4-1:4]),
			.O(),
			.CI(_cin[C-1:1]),
			.CYINIT(),
			.DI({4{!EQ}}),
			.S(_sin[C*4-1:4])
		);
	end
endmodule
