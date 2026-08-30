`timescale 1ns / 1ps
module Kyber_Client(
	input clk, rst, start,
	input wen,
	input [2:0] k,
	input ready_pk,
	input req_c,
	input [31:0] din,
	// output ofifo_req_t,
	// output [31:0] ofifo_dout_t,
	output ready_c,
	output req_pk,
	output reg valid,
	output reg [31:0] dout,
	output valid_out,
	input [255:0] seed_m,
    output reg [255:0] K,
    output wire done
);

// assign ofifo_req_t = ofifo1_req;
// assign ofifo_dout_t = ofifo1_dout;

reg [255:0] rho, r, hash_pk, hash_c;
reg [255:0] m;
wire ena_sft;

reg [5:0] data_ctr;
reg [5:0] din_ctr_end, dout_ctr_end;
reg [3:0] data_rnd_ctr;
reg [3:0] din_rnd_end, dout_rnd_end;
reg [2:0] rot_ctr;
reg [5:0] pad_ctr;
wire [7:0] fifo_GENA_ctr;
reg [3:0] nonce;
reg [1:0] absorb_ctr, absorb_ctr_r1;
reg [1:0] row, col;

wire ready_u;
reg req_c_r1;
reg [24:0] NTT_din;
wire [21:0] NTT_dout;
wire NTT_valid;

wire [72:0] patt, eta3, endp;
reg [72:0] patt_r, eta3_r, endp_r;
reg patt_bit, eta3_bit;

reg [5:0] state, next_state;

assign done = (state == 6'h2c) && (next_state == 6'h00);

reg [2:0] state11_delay_ctr;
reg keccak_init_pulse;

reg keccak_init;
wire keccak_ready;
wire keccak_squeeze;
reg extend;
wire [31:0] keccak_dout;
reg [2:0] keccak_ctr;
wire [5:0] squeeze_ctr;

// Reset the squeeze word index one cycle before entering a capture state.
// The state transition qualifier makes this a single-cycle pulse and lets the
// SHAKE output word remain pending until the capture state is active.
wire squeeze_init_early = (state != next_state) &&
	((next_state == 6'h14) ||
	 (next_state == 6'h20) ||
	 (next_state == 6'h21) ||
	 (next_state == 6'h2b));

reg [31:0] ififo_din;
reg ififo_last;
reg ififo_absorb;
reg [1:0] ififo_mode;
reg ififo_wen;
wire ififo_empty;
wire ofifo0_req, ofifo1_req;
reg ofifo0_req_r1, ofifo1_req_r1;
wire [23:0] ofifo0_dout;
wire [24:0] ofifo1_dout;
wire ofifo0_full, ofifo0_empty;
wire ofifo0_prog_full;
wire ofifo1_prog_full;
wire ofifo1_full, ofifo1_empty;
reg ofifo_ena;
wire ntt_noise_done;

wire [31:0] IFIFO_dout;
wire IFIFO_full, IFIFO_empty;

wire [23:0] decode_dout;
wire decode_req;
reg decode_req_r1;
wire decode_valid;

wire [23:0] DFIFO_din;
wire DFIFO_wen;
wire req_D;
reg req_D_r1;
wire [23:0] DFIFO_dout;
wire DFIFO_full, DFIFO_empty;

wire [31:0] encode_dout;
wire encode_valid;
reg [5:0] encode_ctr;

wire [31:0] OFIFO_din;
wire OFIFO_wen;
reg OFIFO_req_r1;
wire [31:0] OFIFO_dout;
wire OFIFO_full, OFIFO_empty;
reg OFIFO_empty_r1;

always @(posedge clk) begin
	if(rst) begin
		state <= 6'h 0;
		state11_delay_ctr <= 0;
		keccak_init_pulse <= 0;
	end else begin
		if (state == 6'h a && next_state == 6'h 11)
			state11_delay_ctr <= 0;
		else if (state == 6'h 11)
			state11_delay_ctr <= state11_delay_ctr + 1;
		else
			state11_delay_ctr <= 0;
		keccak_init_pulse <= (next_state == 6'h 11);
		state <= next_state;
	end
end
always @* case(state)
	6'h 0 : next_state = start ? state + 1'h 1 : state;
	6'h 2 : next_state = rot_ctr == 3'h 7 ? 6'h c : state;
	6'h 3 : next_state = rot_ctr == 3'h 7 ? 6'h d : state;
	6'h 4 : next_state = rot_ctr == 3'h 7 ? 6'h e : state;
	6'h 5, 6'h 7 : next_state = rot_ctr == 3'h 7 ? state + 1'h 1 : state;
	6'h 6 : next_state = rot_ctr == 3'h 7 ? 6'h a : state;
	6'h 8 : next_state = rot_ctr == 3'h 7 ? 6'h f : state;
	6'h a : next_state = 6'h 11;
	6'h 11: next_state = (state11_delay_ctr < 3'd4) ? 6'h 11 : 6'h 12;
	6'h c, 6'h d, 6'h e, 6'h f : next_state = 6'h 10;
	6'h 10: next_state = pad_ctr == 5'h 0 ? state + 1'h 1 : state;
	6'h 12: next_state = keccak_ready ? state + 1'h 1 : state;
	6'h 13: if((patt_bit | eta3_bit) & ofifo1_full)
			next_state = state;
			else case(keccak_ctr)
				3'h 3 : next_state = ofifo_ena ? patt_r[72] ? 6'h 4 : 6'h 3 : 6'h 21;
				3'h 4 : next_state = 6'h 18;
				3'h 5 : next_state = 6'h 2c;
				default : next_state = state + 1'h 1;
			endcase
	6'h 14: next_state = squeeze_ctr == 6'h 7 ? state + 1'h 1 : state;
	6'h 15: next_state = ready_pk ? 6'h 19 : state;
	6'h 16: next_state = rot_ctr == 3'h 7 ? state + 1'h 1 : state;
	6'h 17: next_state = 6'h 10;
	6'h 18: next_state = squeeze_ctr == 6'h 3F || fifo_GENA_ctr[7] ? 6'h 22 : state;
	6'h 19: next_state = data_ctr == din_ctr_end && data_rnd_ctr == din_rnd_end && decode_req_r1 ? state + 1'h 1 : state;
	6'h 1a: next_state = rot_ctr == 3'h 7 ? state + 1'h 1 : state;
	6'h 1b: next_state = ififo_empty ? state + 1'h 1 : state;
	6'h 1d: next_state = pad_ctr == 5'h 0 ? state + 1'h 1 : state;
	6'h 1f: next_state = keccak_ready ? state + 1'h 1 : state;
	6'h 20: next_state = squeeze_ctr == 3'h 7 ? 6'h 5 : state;
	6'h 21: next_state = squeeze_ctr == 6'h f ? 6'h 3 : state;
	6'h 22: next_state = ready_c ? state + 1'h 1 : state;
	6'h 23: next_state = data_ctr == dout_ctr_end && data_rnd_ctr == dout_rnd_end && OFIFO_req_r1 ? state + 1'h 1 : state;
	6'h 24: next_state = ififo_empty ? state + 1'h 1 : state;
	6'h 25: next_state = rot_ctr == 3'h 7 ? state + 1'h 1 : state;		// redundant cycles for case k=3, when 32-bit data is 34*8 
	6'h 26: next_state = rot_ctr == 3'h 7 ? state + 1'h 1 : state;		// redundant cycles for case k=3, when 32-bit data is 34*8 
	6'h 28: next_state = pad_ctr == 5'h 0 ? state + 1'h 1 : state;
	6'h 2a: next_state = keccak_ready ? state + 1'h 1 : state;
	6'h 2b: next_state = squeeze_ctr == 3'h 7 ? 6'h 7 : state;	
	6'h 2c: next_state = squeeze_ctr == 3'h 7 ? 6'h 0 : state;
	6'h 2e: next_state = rot_ctr == 3'h 7 ? state + 1'h 1 : state;
	6'h 2f: next_state = 6'h 10;
	default : next_state = state + 1'h 1;
endcase

always @(posedge clk) begin
	if(state == 6'h 1a && decode_req_r1)
		rho <= {IFIFO_dout,rho[255:32]};
	else if(state == 6'h 4)
		rho <= {rho[31:0],rho[255:32]};
	else
		rho <= rho;
end
always @(posedge clk) begin
	if(rst)
		K <= 256'h0;
	else case(state)
		6'h 3 : K <= {K[31:0],K[255:32]};
		// First half of G(m || H(pk)): the pre-key K-bar used as the
		// input to the final KDF after H(c) has been computed.
		6'h 21 : K <= (keccak_squeeze && squeeze_ctr < 6'd8) ?
					 {keccak_dout,K[255:32]} : K;
		6'h 7 : K <= {K[31:0],K[255:32]};
		// The legacy design streamed the final shared secret only on dout.
		// Retain those same eight KDF words in K for the AXI-facing port.
		6'h 2c : K <= (keccak_squeeze && squeeze_ctr < 6'd8) ?
					 {keccak_dout,K[255:32]} : K;
		default : K <= K;
	endcase
end
always @(posedge clk) case(state)
	6'h 21 : r <= (keccak_squeeze && squeeze_ctr >= 6'd8 && squeeze_ctr < 6'd16) ? {keccak_dout,r[255:32]} : r;
	6'h 3 : r <= {r[31:0],r[255:32]};
	default : r <= r;
endcase
always @(posedge clk) begin
	if(rst) m <= 0;
	else if(ena_sft)
		m <= {m[1:0],m[255:2]};
	else case(state)
		6'h 1 : m <= seed_m;
		6'h 2, 6'h 5 : m <= {m[31:0],m[255:32]};
		6'h 14: m <= (keccak_squeeze && squeeze_ctr < 6'd8) ? {keccak_dout,m[255:32]} : m;
		default : m <= m;
	endcase
end
always @(posedge clk) case(state)
	6'h 6 : hash_pk <= {hash_pk[31:0],hash_pk[255:32]};
	6'h 20 : hash_pk <= (keccak_squeeze && squeeze_ctr < 6'd8) ? {keccak_dout,hash_pk[255:32]} : hash_pk;
	default : hash_pk <= hash_pk;
endcase
always @(posedge clk) case(state)	
	6'h 8 : hash_c <= {hash_c[31:0],hash_c[255:32]};
	6'h 2b : hash_c <= (keccak_squeeze && squeeze_ctr < 6'd8) ? {keccak_dout,hash_c[255:32]} : hash_c;
	default : hash_c <= hash_c;
endcase
always @(posedge clk) begin
	if(start) begin
		patt_r <= patt;
		eta3_r <= eta3;
		endp_r <= endp;
	end
	else if(keccak_ready && keccak_ctr==3'h 3 && state == 6'h 12) begin
		patt_r <= {patt_r[71:0],1'h0};
		eta3_r <= {eta3_r[71:0],1'h0};
		endp_r <= {endp_r[71:0],1'h0};
	end
	else begin
		patt_r <= patt_r;
		eta3_r <= eta3_r;
		endp_r <= endp_r;
	end
end
always @(posedge clk) begin
	if(rst)
		{patt_bit,eta3_bit} <= 2'h 0;
	else if(keccak_ready)
		{patt_bit,eta3_bit} <= {patt_r[72],eta3_r[72]};
	else
		{patt_bit,eta3_bit} <= {patt_bit,eta3_bit};
end
assign req_pk = state == 5'h 19;
assign ntt_noise_done = (state >= 6'h 12);
always @(*) case(k)
	3'h 2 : begin
		din_ctr_end = 6'h 16;
		din_rnd_end = 4'h 5;
		dout_ctr_end = 6'h 16;
		dout_rnd_end = 4'h 5;
	end
	3'h 3 : begin
		din_ctr_end = 6'h 10;
		din_rnd_end = 4'h 8;
		dout_ctr_end = 6'h 22;
		dout_rnd_end = 4'h 7;
	end
	default : begin
		din_ctr_end = 6'h a;
		din_rnd_end = 4'h b;
		dout_ctr_end = 6'h 12;
		dout_rnd_end = 4'h b;
	end
endcase
always @(posedge clk) case(state)
	4'h 0, 4'h 1 : data_ctr <= 5'h 0;
	5'h 19 : data_ctr <= decode_req ? data_ctr == 6'h 22 ? 6'h 1 : data_ctr + 1'h 1 : data_ctr;
	6'h 20 : data_ctr <= 5'h 0;
	6'h 23 : data_ctr <= req_c & ~OFIFO_empty ? data_ctr == 6'h 22 ? 6'h 1 : data_ctr + 1'h 1 : data_ctr;
	default : data_ctr <= data_ctr;
endcase
always @(posedge clk) case(state)
	4'h 0, 4'h 1 : data_rnd_ctr <= 4'h 0;
	5'h 19 : data_rnd_ctr <= data_ctr == 6'h 22 && decode_req ? data_rnd_ctr + 1'h1 : data_rnd_ctr;
	6'h 20 : data_rnd_ctr <= 4'h 0;
	6'h 23 : data_rnd_ctr <= data_ctr == 6'h 22 && req_c && ~OFIFO_empty ? data_rnd_ctr + 1'h1 : data_rnd_ctr;
	default : data_rnd_ctr <= data_rnd_ctr;
endcase
always @(posedge clk) case(state)
	6'h 0 : rot_ctr <= 4'h 0;
	6'h2, 6'h3, 6'h4, 6'h5, 6'h6, 6'h7, 6'h8 : rot_ctr <= rot_ctr + 1'h 1;
	6'h 16, 6'h 2e : rot_ctr <= rot_ctr + 1'h 1;
	6'h 1a : rot_ctr <= decode_req_r1 ? rot_ctr + 1'h 1 : rot_ctr;
	6'h 25, 6'h 26 : rot_ctr <= rot_ctr + 1'h 1;
	default : rot_ctr <= rot_ctr;
endcase
always @(posedge clk) case(state)
	6'h 0 : pad_ctr <= 5'h 0;
	6'h 2 : pad_ctr <= 5'h 17;
	6'h 3, 6'h 2e : pad_ctr <= 5'h 17;
	6'h 4, 6'h 16 : pad_ctr <= 5'h 1f;
	6'h 5 : pad_ctr <= 5'h 0;
	6'h 7 : pad_ctr <= 5'h f;
	6'h 19: case(k)
		3'h 2 : pad_ctr <= 5'h 1;
		3'h 3 : pad_ctr <= 5'h 7;
		default : pad_ctr <= 5'h d;
	endcase
	6'h 23: case(k)
		3'h 2 : pad_ctr <= 5'h 9;
		3'h 3 : pad_ctr <= 5'h 1f;
		default : pad_ctr <= 5'h d;
	endcase
	6'h 10: pad_ctr <= pad_ctr - 1'h 1;
	6'h 1d: pad_ctr <= pad_ctr - 1'h 1;
	6'h 28: pad_ctr <= pad_ctr - 1'h 1;
	default : pad_ctr <= pad_ctr;
endcase
always @(posedge clk) begin
	if(state == 6'h 0 || state == 6'h 2d)
		absorb_ctr <= 2'h 0;
	else if(keccak_ready && keccak_ctr == 3'h 3) case({patt_r[72],eta3_r[72]})
		2'b 00, 2'b 11 : absorb_ctr <= absorb_ctr + 1'h 1;
		default : absorb_ctr <= 2'h 0;
	endcase
	else
		absorb_ctr <= absorb_ctr;
end
always @(posedge clk) begin
	if(keccak_ready)
		absorb_ctr_r1 <= absorb_ctr;
	else
		absorb_ctr_r1 <= absorb_ctr_r1;
end
always @(posedge clk) begin
	if(state == 6'h 0) begin		
		row <= 2'h 0;
		col <= 2'h 0;
	end
	else if(state == 6'h 4 & next_state == 6'h e) begin
		row <= row == k-1 ? 2'h 0 : row + 1'h 1;
		col <= row == k-1 ? col + 1'h 1 : col;
	end
	else begin
		row <= row;
		col <= col;
	end
end
always @(posedge clk) begin
	if(state == 6'h 0)		
		nonce <= 4'h 0;
	else if(state == 6'h 3 & next_state == 6'h d)
		nonce <= nonce + 1'h 1;
	else		
		nonce <= nonce;	
end
always @(posedge clk) begin
	if(state == 6'h 0)
		keccak_ctr <= 3'h 0;
	else if(keccak_ready) case(state)
		6'h 12 : keccak_ctr <= ~(ofifo_ena&~endp_r[72]) ? keccak_ctr + 1'h 1 : keccak_ctr;
		6'h 1f : keccak_ctr <= keccak_ctr + 1'h 1;
		default : keccak_ctr <= keccak_ctr;
	endcase
	else
		keccak_ctr <= keccak_ctr;
end

always @(*) case(state)
	6'h 1 : keccak_init = 1'h 1;
	6'h 11 : keccak_init = keccak_init_pulse;
	// Start H(pk) when reception actually begins, rather than while waiting
	// in state 15 for the Server to make the key available.
	6'h 19 : keccak_init = 1'h 1;
	6'h 22 : keccak_init = 1'h 1;
	default : keccak_init = 1'h 0;
endcase
always @(*) case(state)
	// State 18 drains more than one SHAKE rate block while rejection
	// sampling noise, so it must explicitly continue the XOF stream.
	6'h 14, 6'h 18, 6'h 20, 6'h 21 : extend = 1'h 1;
	6'h 2b : extend = 1'h 1;
	6'h 2c : extend = 1'h 1;
	default : extend = 1'h 0;
endcase
always @(*) case(state)
	4'h 2 : ififo_din = m[31:0];
	4'h 3 : ififo_din = r[31:0];
	4'h 4 : ififo_din = rho[31:0];
	4'h 5 : ififo_din = m[31:0];
	4'h 6 : ififo_din = hash_pk[31:0];
	4'h 7 : ififo_din = K[31:0]; 
	4'h 8 : ififo_din = hash_c[31:0];
	4'h a : ififo_din = 32'h 00000006;
	4'h c : ififo_din = 32'h 00000006;
	4'h d : ififo_din = {24'h 00001f,4'h0,nonce};
	4'h e : ififo_din = {16'h001f,6'h0,col,6'h0,row};
	4'h f : ififo_din = 32'h 0000001f;
	5'h 19, 5'h 1a : ififo_din = IFIFO_dout;
	5'h 1c, 6'h 27 : ififo_din = 32'h 00000006;
	6'h 23: ififo_din = OFIFO_dout;
	6'h 11: ififo_din = {~absorb_ctr[1]&~absorb_ctr[0],31'h0}; 
	6'h 1e, 6'h 29 : ififo_din = 32'h 80000000;
	default : ififo_din = 32'h 0;
endcase
always @* case(state)
	6'h 2, 6'h 3, 6'h 4, 6'h 5, 6'h 6, 6'h 7, 6'h 8 : ififo_wen = 1'h 1;
	6'h 16, 6'h 2e : ififo_wen = 1'h 1;
	6'h a, 6'h c, 6'h d, 6'h e, 6'h f, 6'h 17, 6'h 2f : ififo_wen = 1'h 1;
	6'h 10 : ififo_wen = 1'h 1;
	6'h 11 : ififo_wen = (state11_delay_ctr == 3'd0) ? 1'h 1 : 1'h 0;
	6'h 18 : ififo_wen = 1'h 1; 		// squeeze final SHAKE256 data into ofifo1
	6'h 19, 6'h 1a : ififo_wen = decode_req_r1;
	6'h 1c, 6'h 1d, 6'h 1e : ififo_wen = 1'h 1;
	6'h 23 : ififo_wen = OFIFO_req_r1 & ready_c & ~OFIFO_empty_r1;
	6'h 27, 6'h 28, 6'h 29 : ififo_wen = 1'h 1;
	default : ififo_wen = 1'h 0;
endcase
always @* case(state)
	6'h 11 : ififo_last = 1'h 1;
	6'h 19 : ififo_last = data_ctr == 6'h 22 ? 1'h 1 : 1'h 0;
	6'h 1e : ififo_last = 1'h 1;
	6'h 23 : ififo_last = data_ctr == 6'h 22 ? 1'h 1 : 1'h 0;
	6'h 29 : ififo_last = 1'h 1;
	default : ififo_last = 1'h 0;
endcase
always @(*) case(state)
	6'h 19, 6'h 1a, 6'h 1c, 6'h 1d, 6'h 1e : ififo_absorb = 1'h 1;
	6'h 23, 6'h 27, 6'h 28, 6'h 29 : ififo_absorb = 1'h 1;
	default : ififo_absorb = absorb_ctr[1]|absorb_ctr[0];
endcase
always @(posedge clk) case(state)
	6'h 0 : ififo_mode <= 2'h 0;
	6'h 2 : ififo_mode <= 2'h 1;
	6'h 3 : ififo_mode <= 2'h 1;
	6'h 4 : ififo_mode <= 2'h 0;
	6'h 5 : ififo_mode <= 2'h 3;
	6'h 7 : ififo_mode <= 2'h 1;
	6'h 18: ififo_mode <= (next_state == 6'h22) ? 2'h1 : ififo_mode;
	6'h 19: ififo_mode <= 2'h 1;
	6'h 22: ififo_mode <= 2'h 1;
	6'h 23: ififo_mode <= 2'h 1;
	default : ififo_mode <= ififo_mode;
endcase
always @(posedge clk) case(state)
	6'h 0 : ofifo_ena <= 1'h 0;
	6'h 12 : case(keccak_ctr)
		3'h 1, 3'h 3 : ofifo_ena <= 1'h 1;
		default : ofifo_ena <= 1'h 0;
	endcase
	6'h 22 : ofifo_ena <= 1'h 0;
	default : ofifo_ena <= ofifo_ena;
endcase

assign DFIFO_din = decode_dout;
assign DFIFO_wen = decode_valid;

reg valid_out_reg;
always @(posedge clk) begin
    if (rst) begin
        valid_out_reg <= 1'b0;
    end
    else begin
        // Advertise only a completed FIFO read.  A bare request can remain
        // high while the encoder FIFO is empty and would duplicate dout.
        valid_out_reg <= req_c_r1 & ready_c & ~OFIFO_empty_r1;
    end
end
assign valid_out = valid_out_reg;

always @(*) case({ofifo0_req_r1,ofifo1_req_r1,req_D_r1})
	default : NTT_din = ofifo0_dout;
	3'b 010 : NTT_din = ofifo1_dout;
	3'b 001 : NTT_din = DFIFO_dout;
endcase

assign OFIFO_din = encode_dout;
assign OFIFO_wen = encode_valid;

always @(posedge clk) begin
	if(req_c_r1 & ready_c & ~OFIFO_empty_r1) begin
		dout <= OFIFO_dout;
		valid <= 1'h 1;
	end
	else if(state == 6'h 2c) begin
		dout <= keccak_dout;
		valid <= 1'h 1;
	end
	else begin
		dout <= dout;
		valid <= 1'h 0;
	end
end

always @(posedge clk) begin
	if(rst) begin
		ofifo0_req_r1 <= 1'b0;
		ofifo1_req_r1 <= 1'b0;
		req_D_r1 <= 1'b0;
		decode_req_r1 <= 1'b0;
		OFIFO_empty_r1 <= 1'b1;
		OFIFO_req_r1 <= 1'b0;
		req_c_r1 <= 1'b0;
	end
	else begin
		ofifo0_req_r1 <= ofifo0_req;
		ofifo1_req_r1 <= ofifo1_req;
		req_D_r1 <= req_D;
		decode_req_r1 <= decode_req;
		OFIFO_empty_r1 <= OFIFO_empty;
		OFIFO_req_r1 <= req_c;
		req_c_r1 <= req_c;
	end
end

NTT_core_Client ntt(
.clk(clk),
.rst(rst),
.start(start),
.k(k),
.ready_u(ready_u),
.ready_c(ready_c),
.fifo0_empty(ofifo0_empty),
.fifo1_empty(ofifo1_empty),
.fifo1_full(ofifo1_full),
		.noise_done(ntt_noise_done),
.fifo0_req(ofifo0_req),
.fifo1_req_r9(ofifo1_req),
.req_D(req_D),
.m_bits({m[129:128],m[1:0]}),
.ena_sft(ena_sft),
.din(NTT_din),
.valid(NTT_valid),
.dout(NTT_dout)
);
hash_core_Client hash(
.clk(clk),
.rst(rst),
.keccak_init(keccak_init),
.keccak_init_hard((state == 6'h1) || (state == 6'h19) || (state == 6'h22)),
.squeeze_init(squeeze_init_early),
.extend(extend),
.patt_bit(patt_bit),
.eta3_bit(eta3_bit),
.absorb_ctr_r1(absorb_ctr_r1),
.keccak_ctr(keccak_ctr),
.squeeze_ctr(squeeze_ctr),
.ififo_wen(ififo_wen),
.ififo_din(ififo_din),
.ififo_absorb(ififo_absorb),
.ififo_mode(ififo_mode),
.ififo_last(ififo_last),
.ififo_empty(ififo_empty),
.keccak_dout(keccak_dout),
.keccak_squeeze(keccak_squeeze),
.ofifo_ena(ofifo_ena),
.ofifo0_req(ofifo0_req),
.ofifo1_req(ofifo1_req),
.ofifo0_prog_thresh(9'd200),
.ofifo0_dout(ofifo0_dout),
.ofifo1_dout(ofifo1_dout),
.ofifo0_full(ofifo0_full),
.ofifo1_full(ofifo1_full),
.ofifo0_empty(ofifo0_empty),
.ofifo1_empty(ofifo1_empty),
.ofifo0_prog_full(ofifo0_prog_full),
.ofifo1_prog_thresh(9'd18),
.ofifo1_prog_full(ofifo1_prog_full),
.keccak_ready(keccak_ready),
.fifo_GENA_ctr(fifo_GENA_ctr)
);
	decode_Client decode(.clk(clk),.rst(rst),.din(IFIFO_dout),.fifo_empty(IFIFO_empty),.dout(decode_dout),.req(decode_req),.valid(decode_valid));
	encode_Client encode(.clk(clk),.rst(rst),.din(NTT_dout),.wen(NTT_valid),.sel(ready_u),.k(k),.valid(encode_valid),.dout(encode_dout));
	pattern pattern(.k(k),.sel(1'h1),.patt(patt),.eta3(eta3),.endp(endp));
	
	// Replaced Xilinx FIFO generators with generic FIFO wrappers
	fifo_wrapper_32_16 #(.DEPTH(128)) IFIFO (
		.clk(clk),
		.rst_n(~rst),
		.wr_en(wen),
		.wr_data(din),
		.rd_en(decode_req),
		.dout(IFIFO_dout),
		.full(IFIFO_full),
		.empty(IFIFO_empty)
	);
	
	fifo_wrapper_32_16 #(.DEPTH(512)) OFIFO (
		.clk(clk),
		.rst_n(~rst),
		.wr_en(OFIFO_wen),
		.wr_data(OFIFO_din),
		.rd_en(req_c),
		.dout(OFIFO_dout),
		.full(OFIFO_full),
		.empty(OFIFO_empty)
	);
	
	fifo_wrapper_24_16 DFIFO (
		.clk(clk),
		.rst_n(~rst),
		.wr_en(DFIFO_wen),
		.wr_data(DFIFO_din),
		.rd_en(req_D),
		.prog_full_thresh(9'd0),
		.dout(DFIFO_dout),
		.full(DFIFO_full),
		.empty(DFIFO_empty),
		.prog_full()
	);
	
endmodule
