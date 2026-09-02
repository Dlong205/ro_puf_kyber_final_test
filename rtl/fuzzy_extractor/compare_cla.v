/*
 * BCH Encode/Decoder Modules
 *
 * Copyright 2014 - Russ Dill <russ.dill@asu.edu>
 * Distributed under 2-clause BSD license as contained in COPYING file.
 */
`timescale 1ns / 1ps

`include "config.vh"

module compare_cla #(
	parameter N = 7,
	parameter [N-1:0] CONST = 0,
	parameter EQ = 1,
	parameter W = 1		/* Number of LUT bits needed per input */
) (
	input [N-1:0] in,
	output out
);
	/* ASIC builds never parse or elaborate a Xilinx primitive reference. */
`ifdef KP_TARGET_ASIC
	assign out = (in != CONST) ^ EQ;
`else
	if (!`CONFIG_HAS_CARRY4 || N * W <= `CONFIG_LUT_MAX_SZ) begin
		assign out = (in != CONST) ^ EQ;
	end else begin
		compare_cla_xilinx #(N, CONST, EQ, W) u_xilinx(in, out);
	end
`endif
endmodule

module eq_cla #(
	parameter N = 7,
	parameter [N-1:0] CONST = 0,
	parameter W = 1
) (
	input [N-1:0] in,
	output out
);
	compare_cla #(N, CONST, 1, W) u_cla(in, out);
endmodule

module neq_cla #(
	parameter N = 7,
	parameter [N-1:0] CONST = 0,
	parameter W = 1
) (
	input [N-1:0] in,
	output out
);
	compare_cla #(N, CONST, 0, W) u_cla(in, out);
endmodule

module zero_cla #(
	parameter N = 7,
	parameter W = 1
) (
	input [N-1:0] in,
	output out
);
	eq_cla #(N, 0, W) u_cla(in, out);
endmodule

module nonzero_cla #(
	parameter N = 7,
	parameter W = 1
) (
	input [N-1:0] in,
	output out
);
	neq_cla #(N, 0, W) u_cla(in, out);
endmodule
