`timescale 1ns / 1ps
module Kyber_Server(
	input clk, rst, start,
	input wen,
	input [2:0] k,
	input ready_c,
	input req_pk,
	input [31:0] din,
	// output ofifo_req_t,
	output reg ready_pk,
	output req_c,
	output reg valid,
	output reg [31:0] dout,
	output valid_out, // Added valid_out port
	input [255:0] seed_d,
	input [255:0] seed_z,
    output reg [255:0] K,
    output wire done
);

// assign ofifo_req_t = ofifo0_req;
// assign ofifo_dout_t = ofifo0_dout;

reg [255:0] d, rho, sigma, hash_pk, hash_c;
reg [255:0] m, z;
wire [1:0] m_dec;
wire m_ena;

reg req_pk_r1;
wire NTT_finish;
wire ntt_noise_done;
wire ena_sft;
reg CCA_enc;
wire CCA_enc_start;

reg [5:0] data_ctr;
reg [5:0] din_ctr_end, dout_ctr_end, u_ctr_end;
reg [3:0] data_rnd_ctr;
reg [3:0] din_rnd_end, dout_rnd_end, u_rnd_end;
reg [2:0] rot_ctr;
reg [5:0] pad_ctr;
wire [7:0] fifo_GENA_ctr;
wire matrix_stream_active;
reg [3:0] nonce;
reg [1:0] absorb_ctr, absorb_ctr_r1;
reg [1:0] row, col;

wire ready_t;
reg [24:0] NTT_din;
wire [23:0] NTT_dout;
wire NTT_valid;

wire [72:0] patt, eta3, endp;
reg [72:0] patt_r, eta3_r, endp_r;
reg patt_bit, eta3_bit;

reg [5:0] state, next_state;

// Completion is distinct from valid: valid also marks public-key stream words.
// done pulses on the final KDF word, when K is committed and the FSM returns
// to idle on the same clock edge.
assign done = (state == 6'h31) && (next_state == 6'h00);

reg [2:0] state11_delay_ctr;
reg keccak_init_pulse;

reg keccak_init;
wire keccak_ready;
wire keccak_squeeze;
reg extend;
wire [31:0] keccak_dout;
reg [2:0] keccak_ctr;
wire [5:0] squeeze_ctr;

// The rebuilt SHA3 core exposes a ready/valid stream, while the legacy Kyber
// FSM expects the first digest word to remain stationary until its capture
// state is active.  Hold the stream and reset only the local word index on the
// transition into each fixed-size digest capture window.
wire squeeze_init_early = (state != next_state) &&
	((next_state == 6'h14) ||
	 (next_state == 6'h21) ||
	 (next_state == 6'h2b) ||
	 (next_state == 6'h2e));

reg [31:0] ififo_din;
reg ififo_last;
reg ififo_absorb;
reg [1:0] ififo_mode;
reg ififo_wen;
wire ififo_empty;
wire ofifo0_req, ofifo1_req;
reg ofifo0_req_r1, ofifo1_req_r1;
wire ofifo1_preload;
reg ofifo1_preload_r1;
wire [23:0] ofifo0_dout;
wire [24:0] ofifo1_dout;
wire ofifo0_full, ofifo0_empty;
wire ofifo0_prog_full;
wire ofifo1_prog_full;
wire ofifo1_full, ofifo1_empty;
reg ofifo_ena;

wire [31:0] IFIFO_dout;
wire IFIFO_full, IFIFO_empty;

wire [31:0] decode_din;
wire decode_fifo_empty;
reg decode_sel;
wire [23:0] decode_dout;
wire decode_req;
reg decode_req_r1;
wire decode_valid;

wire [23:0] DFIFO0_din;
wire DFIFO0_wen;
wire [23:0] DFIFO0_dout;
wire req_D0;
reg req_D0_r1;
wire DFIFO0_empty, DFIFO0_full;
reg DFIFO0_full_r1;
wire [8:0] DFIFO0_prog_thresh;
wire DFIFO0_prog_full, DFIFO0_full_eff;
reg DFIFO0_load_b;

reg [9:0] DFIFO1_din;
reg DFIFO1_wen;
wire [9:0] DFIFO1_dout;
wire req_D1;
reg req_D1_r1;
wire DFIFO1_empty, DFIFO1_full;

reg [21:0] cmp0, cmp1;
reg equal;

wire [23:0] encode_din;
reg encode_wen;
wire [31:0] encode_dout;
wire encode_valid;

reg [33:0] OFIFO_din;
reg OFIFO_wen;
wire [33:0] OFIFO_dout;
reg OFIFO_req;
reg OFIFO_req_r1;
wire OFIFO_full, OFIFO_empty;
reg OFIFO_empty_r1;
wire OFIFO_seed, OFIFO_last;
reg OFIFO_tx_done;

// FIPS 203 implicit rejection hashes z || c, where c is the exact received
// 768-byte ML-KEM-512 ciphertext.  The decode path consumes its input FIFO and
// cannot reconstruct non-canonical/modified bytes, so retain one ciphertext
// for replay through the existing SHAKE256 core after the compare.  A
// synchronous generic_bram keeps this 6-Kibit buffer out of LUT fabric on FPGA
// and remains portable to an ASIC SRAM/register-file mapping.
reg [7:0] ciphertext_wr_ctr;
reg [7:0] j_replay_ctr;
reg final_kdf_active;
wire [31:0] ciphertext_replay_dout;
wire [7:0] ciphertext_replay_addr;

// Port B is prefetched while z is being absorbed.  During replay it requests
// word n+1 while word n is presented to the hash FIFO, compensating for the
// one-cycle synchronous RAM read latency without inserting bubbles.
assign ciphertext_replay_addr =
	(state == 6'h8 && j_replay_ctr < 8'd191) ?
		j_replay_ctr + 1'b1 : 8'd0;

generic_bram #(
	.DEPTH(256),
	.WIDTH(32)
) ciphertext_store (
	.clk(clk),
	.en_a(state == 6'h23 && wen && ciphertext_wr_ctr < 8'd192),
	.we_a(state == 6'h23 && wen && ciphertext_wr_ctr < 8'd192),
	.addr_a(ciphertext_wr_ctr),
	.din_a(din),
	.dout_a(),
	.en_b(state == 6'h9 || state == 6'h8),
	.we_b(1'b0),
	.addr_b(ciphertext_replay_addr),
	.din_b(32'b0),
	.dout_b(ciphertext_replay_dout)
);

always @(posedge clk) begin
    if(rst) begin
        state <= 6'h 0;
        state11_delay_ctr <= 0;
        keccak_init_pulse <= 0;
    end else begin
        if (state == 6'h a && next_state == 6'h 11)
            state11_delay_ctr <= 0;
		else if (state == 6'h 11)
			// J(z || c) spans six SHAKE256 rate blocks.  State 11 waits
			// while the queued blocks drain, so saturate instead of wrapping
			// and accidentally enqueueing the final padding word again.
			state11_delay_ctr <= (final_kdf_active &&
				state11_delay_ctr == 3'd7) ? state11_delay_ctr :
				state11_delay_ctr + 1'b1;
        else
            state11_delay_ctr <= 0;
        
        // Start a new hash only on the normal padding path.  The direct a->11
        // path is a continuation of the message already being absorbed.
        keccak_init_pulse <= (state == 6'h 10 && next_state == 6'h 11);
        state <= next_state;
    end
end
always @* case(state)
	6'h 0 : next_state = start ? state + 1'h 1 : state;
	6'h 2 : next_state = rot_ctr == 3'h 7 ? 6'h c : state;
	6'h 3 : next_state = rot_ctr == 3'h 7 ? 6'h d : state;
	6'h 4 : next_state = rot_ctr == 3'h 7 ? CCA_enc ? 6'h b : 6'h e : state;
	6'h 5, 6'h 7 : next_state = rot_ctr == 3'h 7 ? state + 1'h 1 : state;
	6'h 6 : next_state = rot_ctr == 3'h 7 ? 6'h a : state;
	// Always replay all 192 ciphertext words after z.  Computing J(z || c) for
	// accepted and rejected inputs equalizes the large protocol-level timing
	// difference; the final key mux still selects K-bar when equal is true.
	6'h 8 : next_state = j_replay_ctr == 8'd191 ? 6'h f : state;
	6'h 9 : next_state = rot_ctr == 3'h 7 ? 6'h 8 : state;
	6'h a : next_state = 6'h 11;
	6'h b, 6'h c, 6'h d, 6'h e : next_state = 6'h 10;
	6'h 10: next_state = pad_ctr == 5'h 0 ? state + 1'h 1 : state;
	6'h 11: next_state = final_kdf_active ?
		((state11_delay_ctr != 3'd0 && ififo_empty) ? 6'h12 : 6'h11) :
		((state11_delay_ctr < 3'd4) ? 6'h11 : 6'h12);
	6'h 12: next_state = keccak_ready ? state + 1'h 1 : state;
	6'h 13: if(((patt_bit | eta3_bit) & ofifo1_full) |
			(~patt_bit & ~eta3_bit & ofifo0_full))
			next_state = state;
		else case(keccak_ctr)
			// KeyGen schedule: a patt block starts a fresh PRF, an eta3-only
			// block continues that SHAKE256 stream, and matrix XOF blocks are
			// chained until rejection sampling has a complete polynomial.
			3'h 1 : next_state = ofifo_ena ?
				patt_r[72] ? 6'h 3 :
				eta3_r[72] ? 6'h 3e :
				(absorb_ctr[1] | absorb_ctr[0]) ? 6'h 16 : 6'h 4
				: state + 1'h 1;
			3'h 2 : next_state = 6'h 18;
			// CCA re-encryption uses the same stream protocol as Encaps:
			// patt starts PRF(r,nonce), eta3 emits its 56-byte continuation,
			// and an untagged slot starts/continues matrix rejection sampling.
			// The former reversed branch started a new nonce during eta3 and
			// left the second secret polynomial with only 14 raw words.
			3'h 3 : next_state = ofifo_ena ?
				patt_r[72] ? 6'h 3 :
				eta3_r[72] ? 6'h 3e :
				(absorb_ctr[1] | absorb_ctr[0]) ? 6'h 16 : 6'h 4
				: 6'h 2e;
			3'h 4 : next_state = 6'h 2f;
			// With the rebuilt hash schedule H(c) and G(m'||H(pk)) finish
			// at counters 2 and 3, so the post-compare KDF finishes at 5,
			// matching the Client.  Waiting for 7 hashes two unrelated PRF
			// blocks and returns the wrong shared secret.
			3'h 5 : next_state = CCA_enc ? 6'h 31 : state + 1'h 1;
			3'h 7 : next_state = 6'h 31;
			default : next_state = state + 1'h 1;
		endcase
	6'h 14: next_state = squeeze_ctr == 6'h f ? state + 1'h 1 : state;
	6'h 15: next_state = 6'h 3;
	6'h 16: next_state = rot_ctr == 3'h 7 ? state + 1'h 1 : state;
	6'h 17: next_state = 6'h 10;
	6'h 18: next_state = (fifo_GENA_ctr[7] && matrix_stream_active) ? state + 1'h 1 : state;
	6'h 19: next_state = ready_t ? state + 1'h 1 : state;
	6'h 1a: next_state = rot_ctr == 3'h 7 ? state + 1'h 1 : state;
	6'h 1b: next_state = data_ctr == dout_ctr_end && data_rnd_ctr == dout_rnd_end && OFIFO_req_r1 ? state + 1'h 1 : state;
	6'h 1c: next_state = ififo_empty ? state + 1'h 1 : state;
	6'h 1e: next_state = pad_ctr == 5'h 0 ? state + 1'h 1 : state;
	6'h 20: next_state = keccak_ready ? state + 1'h 1 : state;
	// Capture H(pk) by accepted digest words, not elapsed cycles.  The rebuilt
	// sponge deliberately holds word 0 for one cycle at the state boundary;
	// rot_ctr would therefore leave after only seven valid words.
	6'h 21: next_state = squeeze_ctr == 3'h 7 ? state + 1'h 1 : state;
	6'h 22: next_state = ready_c ? state + 1'h 1 : state;
	6'h 23: next_state = data_ctr == din_ctr_end && data_rnd_ctr == din_rnd_end && decode_req_r1 ? state + 1'h 1 : state;
	6'h 24: next_state = ififo_empty ? state + 1'h 1 : state;
	6'h 25, 6'h 26 : next_state = rot_ctr == 3'h 7 ? state + 1'h 1 : state;
	6'h 28: next_state = pad_ctr == 5'h 0 ? state + 1'h 1 : state;
	6'h 2a: next_state = keccak_ready ? state + 1'h 1 : state;
	6'h 2b: next_state = squeeze_ctr == 3'h 7 ? state + 1'h 1 : state;
	6'h 2c: next_state = NTT_finish ? state + 1'h 1 : state;
	6'h 2d: next_state = 6'h 5;
	6'h 2e: next_state = squeeze_ctr == 4'h f ? 6'h 3 : state;
	// Drain the final CCA matrix XOF until rejection sampling has emitted all
	// 128 packed words.  A fixed 32-cycle tail can leave the NTT permanently
	// waiting for the last data-dependent coefficients.
	6'h 2f: next_state = (fifo_GENA_ctr[7] && matrix_stream_active) ?
				state + 1'h 1 : state;
	6'h 30: next_state = NTT_finish ? 6'h 9 : state;
	6'h 31: next_state = squeeze_ctr == 3'h 7 ? 6'h 0 : state;
	6'h 3e: next_state = rot_ctr == 3'h 7 ? state + 1'h 1 : state;
	6'h 3f: next_state = 6'h 10;
	default : next_state = state + 1'h 1;
endcase

always @(posedge clk) begin
	if(rst || start) begin
		ciphertext_wr_ctr <= 8'd0;
	end else if(state == 6'h23 && wen && ciphertext_wr_ctr < 8'd192) begin
		ciphertext_wr_ctr <= ciphertext_wr_ctr + 1'b1;
	end
end

always @(posedge clk) begin
	if(rst || state == 6'h30)
		j_replay_ctr <= 8'd0;
	else if(state == 6'h8 && j_replay_ctr < 8'd191)
		j_replay_ctr <= j_replay_ctr + 1'b1;
end

always @(posedge clk) begin
	if(rst || start || state == 6'h0)
		final_kdf_active <= 1'b0;
	else if(state == 6'h30 && next_state != state)
		final_kdf_active <= 1'b1;
end

always @(posedge clk) begin
	if(rst) d <= 0;
	else case(state)
	6'h 1 : d <= seed_d;
	6'h 2 : d <= {d[31:0],d[255:32]};
	default : d <= d;
	endcase
end
always @(posedge clk) begin
	if(squeeze_ctr[3] && (state == 6'h 14 || state == 6'h 2e))
		sigma <= {keccak_dout,sigma[255:32]};
	else if(state == 4'h 3)
		sigma <= {sigma[31:0],sigma[255:32]};
	else
		sigma <= sigma;
end
always @(posedge clk) begin
	// During key generation the first half of G(d) is the public matrix
	// seed rho.  During CCA decapsulation the same output lane is K-bar;
	// keep the original rho intact for re-encryption.
	if(~CCA_enc && ~squeeze_ctr[3] && state == 6'h 14)
		rho <= {keccak_dout,rho[255:32]};
	else if(state == 6'h 1a || state == 6'h 4)
		rho <= {rho[31:0],rho[255:32]};
	else
		rho <= rho;
end
always @(posedge clk) begin
	if(ena_sft)
		m <= {m[1:0],m[255:2]};
	else if(m_ena)
		m <= {m_dec,m[255:2]};
	else case(state)
		// The 128 decoded bit-pairs have already reconstructed the same
		// word order used by the Client's G(m || H(pk)) input.  Keep that
		// order for CCA re-encryption; swapping the 128-bit halves changes
		// the derived coins and makes every regenerated coefficient differ.
		6'h 2d : m <= m;
		6'h 5 : m <= {m[31:0],m[255:32]};
		default : m <= m;
	endcase
end
always @(posedge clk) case(state)
	6'h 6 : hash_pk <= {hash_pk[31:0],hash_pk[255:32]};
	6'h 21 : hash_pk <= (keccak_squeeze && squeeze_ctr < 6'd8) ? {keccak_dout,hash_pk[255:32]} : hash_pk;
	default : hash_pk <= hash_pk;
endcase
always @(posedge clk) case(state)
	6'h 8 : hash_c <= {hash_c[31:0],hash_c[255:32]};
	6'h 2b : hash_c <= (keccak_squeeze && squeeze_ctr < 6'd8) ? {keccak_dout,hash_c[255:32]} : hash_c;
	default : hash_c <= hash_c;
endcase
always @(posedge clk) begin
	if(rst)
		K <= 256'h0;
	else case(state)
		6'h 7 : K <= {K[31:0],K[255:32]};
		// First half of G(m' || H(pk)): keep K-bar intact throughout CCA
		// re-encryption so state 7 feeds the correct value to the final KDF.
		6'h 2e : K <= (keccak_squeeze && squeeze_ctr < 6'd8) ?
					 {keccak_dout,K[255:32]} : K;
		// On a valid ciphertext FIPS 203 Decaps_internal returns K-bar.  Keep
		// the value captured above; on rejection capture J(z || c) from the
		// constant-schedule replay through the SHAKE256 core.
		6'h 31 : K <= equal ? K :
					 ((keccak_squeeze && squeeze_ctr < 6'd8) ?
					  {keccak_dout,K[255:32]} : K);
		default : K <= K;
	endcase
end
always @(posedge clk) begin
	if(rst) z <= 0;
	else case(state)
	6'h 1 : z <= seed_z;
	6'h 9 : z <= {z[31:0],z[255:32]};
	default : z <= z;
	endcase
end
always @(posedge clk) begin
	if(start | CCA_enc_start) begin
		patt_r <= patt;
		eta3_r <= eta3;
		endp_r <= endp;
	end
	else if(keccak_ready && (keccak_ctr==3'h 1 || keccak_ctr==3'h 3)) begin
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
always @(posedge clk) case(state)
	6'h 0 : ready_pk <= 1'h 0;
	6'h 1b: ready_pk <= 1'h 1;
	default : ready_pk <= ready_pk;
endcase
assign req_c = state == 6'h 23;
always @(*) case(k)
	3'h 2 : begin
		din_ctr_end = 6'h 16;
		din_rnd_end = 4'h 5;
		dout_ctr_end = 6'h 1e;
		dout_rnd_end = 4'h 5;
		u_ctr_end = 6'h 17;
		u_rnd_end = 4'h 4;
	end
	3'h 3 : begin
		din_ctr_end = 6'h 22;
		din_rnd_end = 4'h 7;
		dout_ctr_end = 6'h 18;
		dout_rnd_end = 4'h 8;
		u_ctr_end = 6'h 1;
		u_rnd_end = 4'h 7;
	end
	default : begin
		din_ctr_end = 6'h 12;
		din_rnd_end = 4'h b;
		dout_ctr_end = 6'h 12;
		dout_rnd_end = 4'h b;
		u_ctr_end = 6'h b;
		u_rnd_end = 4'h a;
	end
endcase
always @(posedge clk) case(state)
	4'h 0, 4'h 1 : data_ctr <= 6'h 0;
	6'h 1b : data_ctr <= OFIFO_req & ~OFIFO_empty ? data_ctr == 6'h 22 ? 6'h 1 : data_ctr + 1'h 1 : data_ctr;
	6'h 21 : data_ctr <= 6'h 0;
	6'h 23 : data_ctr <= decode_req ? data_ctr == 6'h 22 ? 6'h 1 : data_ctr + 1'h 1 : data_ctr;
	default : data_ctr <= data_ctr;
endcase
always @(posedge clk) case(state)
	4'h 0, 4'h 1 : data_rnd_ctr <= 4'h 0;
	5'h 1b : data_rnd_ctr <= data_ctr == 6'h 22 && OFIFO_req && ~OFIFO_empty ? data_rnd_ctr + 1'h1 : data_rnd_ctr;
	6'h 21 : data_rnd_ctr <= 4'h 0;
	6'h 23 : data_rnd_ctr <= data_ctr == 6'h 22 && decode_req ? data_rnd_ctr + 1'h1 : data_rnd_ctr;
	default : data_rnd_ctr <= data_rnd_ctr;
endcase
always @(posedge clk) case(state)
	6'h 0 : rot_ctr <= 4'h 0;
	6'h2, 6'h3, 6'h4, 6'h5, 6'h6, 6'h7, 6'h8, 6'h 9 : rot_ctr <= rot_ctr + 1'h 1;
	6'h 16, 6'h 3e : rot_ctr <= rot_ctr + 1'h 1;
	6'h 1a, 6'h 21 : rot_ctr <= rot_ctr + 1'h 1;
	6'h 25, 6'h 26 : rot_ctr <= rot_ctr + 1'h 1;
	default : rot_ctr <= rot_ctr;
endcase
always @(posedge clk) case(state)
	6'h 0 : pad_ctr <= 5'h 0;
	6'h 2 : pad_ctr <= 5'h 7;
	6'h 3, 6'h 3e : pad_ctr <= 5'h 17;
	6'h 4, 6'h 16 : pad_ctr <= 5'h 1f;
	6'h 5 : pad_ctr <= 5'h 0;
	6'h 7 : pad_ctr <= 5'h f;
	// z || c contains 200 message words.  After the SHAKE domain word only
	// two zero words are needed before the final 0x80000000 rate word.
	6'h 9 : pad_ctr <= 5'h 1;
	6'h 1b: case(k)
		3'h 2 : pad_ctr <= 5'h 1;
		3'h 3 : pad_ctr <= 5'h 7;
		default : pad_ctr <= 5'h d;
	endcase
	6'h 23: case(k)
		3'h 2 : pad_ctr <= 5'h 9;
		3'h 3 : pad_ctr <= 5'h 1f;
		default : pad_ctr <= 5'h d;
	endcase
	6'h 10: pad_ctr <= (pad_ctr == 0) ? 0 : pad_ctr - 1'h 1;
	6'h 1e: pad_ctr <= pad_ctr - 1'h 1;
	6'h 28: pad_ctr <= pad_ctr - 1'h 1;
	default : pad_ctr <= pad_ctr;
endcase
always @(posedge clk) begin
	if(state == 6'h 0 || state == 6'h 2d)
		absorb_ctr <= 2'h 0;
	else if(keccak_ready && (keccak_ctr == 3'h 1 || keccak_ctr == 3'h 3)) case({patt_r[72],eta3_r[72]})
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
	if(state == 6'h 0 || state == 6'h 2d)
		row <= 2'h 0;
	else if(keccak_ready && absorb_ctr == 2'h 3 && col == k-1)
		row <= row == k-1 ? 2'h 0 : row + 1'h 1;
	else
		row <= row;
end
always @(posedge clk) begin
	if(state == 6'h 0 || state == 6'h 2d)
		col <= 2'h 0;
	else if(keccak_ready && absorb_ctr == 2'h 3)
		col <= col == k-1 ? 2'h 0 : col + 1'h 1;
	else
		col <= col;
end
always @(posedge clk) begin
	if(state == 6'h 0 || state == 6'h 2d)		
		nonce <= 4'h 0;
	// Advance once after a complete PRF stream.  For eta1=3 the first
	// permutation is patt+eta3 and the continuation is eta3-only, so XOR is
	// true exactly once; for eta=2 the single patt block also has XOR true.
	else if(keccak_ready && (keccak_ctr == 3'h 1 || keccak_ctr == 3'h 3) &&
			(patt_r[72] ^ eta3_r[72]))
		nonce <= nonce + 1'h 1;
	else		
		nonce <= nonce;	
end
always @(posedge clk) begin
	if(rst)
		CCA_enc <= 1'h 0;
	else if(start)
		CCA_enc <= 1'h 0;
	else if(state == 6'h 2d)
		CCA_enc <= 1'h 1;
	else
		CCA_enc <= CCA_enc;
end
assign CCA_enc_start = state == 6'h a;
// CCA re-encryption must wait for and consume the regenerated secret-noise
// polynomial exactly like the Client Encaps path.  Treating CCA as
// unconditionally "noise done" starts the NTT with an all-zero secret.
assign ntt_noise_done = (state == 6'h 19) & ~CCA_enc;
always @(posedge clk) begin
	if(state == 6'h 0)
		keccak_ctr <= 3'h 0;
	else if(keccak_ready) case(state)
		6'h 12 : keccak_ctr <= ~(ofifo_ena&~endp_r[72]) ? keccak_ctr + 1'h 1 : keccak_ctr;
		default : keccak_ctr <= keccak_ctr;
	endcase
	else
		keccak_ctr <= keccak_ctr;
end

always @(*) case(state)
	6'h 1 : keccak_init = 1'h 1;
	6'h 11 : keccak_init = keccak_init_pulse;
	// State 19 overlaps draining the preceding XOF block.  Reset at 1a,
	// immediately before public-key words enter the hash pipeline.
	6'h 1a : keccak_init = 1'h 1;
	6'h 22 : keccak_init = 1'h 1;
	// The CCA re-encryption leaves wr_idx at the end of its last stream.
	// Clear the sponge on the transition out of compare, one cycle before
	// state 7/9 starts writing K-bar/z for the final KDF.
	6'h 30 : keccak_init = (next_state != state);
	default : keccak_init = 1'h 0;
endcase
always @(*) case(state)
	// State 18 drains more than one SHAKE rate block while rejection
	// sampling matrix data, so it must explicitly continue the XOF stream.
	6'h 14, 6'h 18, 6'h 21 : extend = 1'h 1;
	6'h 2b : extend = 1'h 1;
	6'h 2e, 6'h 2f : extend = 1'h 1;
	6'h 31 : extend = 1'h 1;
	default : extend = 1'h 0;
endcase

always @(*) case(state)
	4'h 2 : ififo_din = d[31:0];
	4'h 3 : ififo_din = sigma[31:0];
	4'h 4 : ififo_din = rho[31:0];
	4'h 5 : ififo_din = m[31:0];
	4'h 6 : ififo_din = hash_pk[31:0];
	4'h 7 : ififo_din = K[31:0]; 
	4'h 8 : ififo_din = ciphertext_replay_dout;
	4'h 9 : ififo_din = z[31:0];
	4'h a : ififo_din = 32'h 00000006;
	4'h b : ififo_din = {16'h001f,6'h0,col,6'h0,row};
	// FIPS 203 K-PKE.KeyGen domain separation: G(d || k).  For the fixed
	// ML-KEM-512 parameter set, byte 32 is k=2 and byte 33 is the SHA3-512
	// suffix.  Packing is little-endian within the 32-bit absorb word.
	4'h c : ififo_din = 32'h 00000602;
	4'h d : ififo_din = {24'h 00001f,4'h0,nonce};
	4'h e : ififo_din = {16'h001f,6'h0,row,6'h0,col};
	4'h f : ififo_din = 32'h 0000001f;
	6'h 1b: ififo_din = OFIFO_dout;
	6'h 1d, 6'h 27: ififo_din = 32'h 00000006;
	6'h 23: ififo_din = IFIFO_dout;
	6'h 30: ififo_din = m[31:0];
	6'h 11: ififo_din = final_kdf_active ? 32'h80000000 :
				 {~absorb_ctr[1]&~absorb_ctr[0],31'h0};
	6'h 1f, 6'h 29 : ififo_din = 32'h 80000000;
	default : ififo_din = 32'h 0;
endcase
always @* case(state)
	6'h 2, 6'h 3, 6'h 4, 6'h 5, 6'h 6, 6'h 7, 6'h 8, 6'h 9 : ififo_wen = 1'h 1;
	6'h 16, 6'h 3e : ififo_wen = 1'h 1;
	6'h a, 6'h b, 6'h c, 6'h d, 6'h e, 6'h f, 6'h 17, 6'h 3f : ififo_wen = 1'h 1;
	6'h 10 : ififo_wen = 1'h 1;
	6'h 11 : ififo_wen = (state11_delay_ctr == 3'd0) ? 1'h 1 : 1'h 0;
	6'h 18, 6'h 2f : ififo_wen = 1'h 1;		// squeeze final SHAKE128 data into ofifo0
	6'h 1b : ififo_wen = OFIFO_req_r1 & ~OFIFO_empty_r1 & ~OFIFO_tx_done;
	6'h 1d, 6'h 1e, 6'h 1f : ififo_wen = 1'h 1;
	6'h 23 : ififo_wen = decode_req_r1;
	6'h 27, 6'h 28, 6'h 29 : ififo_wen = 1'h 1;
	default : ififo_wen = 1'h 0;
endcase
always @* case(state)
	6'h 11 : ififo_last = 1'h 1;
	6'h 1b : ififo_last = data_ctr == 6'h 22 ? 1'h 1 : 1'h 0;
	6'h 1f : ififo_last = 1'h 1;
	6'h 23 : ififo_last = data_ctr == 6'h 22 ? 1'h 1 : 1'h 0;
	// Rate boundaries for z[0..7] || c[0..191].  With a 34-word SHAKE256
	// rate, the five complete blocks end at ciphertext words below; state 11
	// marks the sixth and final padded block.
	6'h 8 : ififo_last =
		((j_replay_ctr == 8'd25)  || (j_replay_ctr == 8'd59) ||
		 (j_replay_ctr == 8'd93)  || (j_replay_ctr == 8'd127) ||
		 (j_replay_ctr == 8'd161));
	6'h 29 : ififo_last = 1'h 1;
	default : ififo_last = 1'h 0;
endcase
always @(*) begin
	if(final_kdf_active)
		// The sponge was hard-cleared on the state-30 boundary.  XOR is
		// equivalent to overwrite for the first block and is required for all
		// following z || c rate blocks.
		ififo_absorb = 1'b1;
	else case(state)
		6'h 1b, 6'h 1d, 6'h 1e, 6'h 1f : ififo_absorb = 1'h 1;
		6'h 23, 6'h 27, 6'h 28, 6'h 29 : ififo_absorb = 1'h 1;
		default : ififo_absorb = absorb_ctr[1]|absorb_ctr[0];
	endcase
end
reg [1:0] ififo_mode_n;
always @(*) case(next_state)
	6'h 0 : ififo_mode_n = 2'h 0;
	6'h 2 : ififo_mode_n = 2'h 3;
	6'h 3 : ififo_mode_n = 2'h 1;
	6'h 4 : ififo_mode_n = 2'h 0;
	6'h 5 : ififo_mode_n = 2'h 3;
	6'h 7, 6'h 9 : ififo_mode_n = 2'h 1;
	6'h 10: ififo_mode_n = 2'h 1;
	6'h 11: ififo_mode_n = 2'h 1;
	6'h 1b: ififo_mode_n = 2'h 1;
	6'h 23: ififo_mode_n = 2'h 1;
	default : ififo_mode_n = ififo_mode;
endcase
always @(posedge clk) ififo_mode <= ififo_mode_n;
always @(posedge clk) case(state)
	6'h 0 : ofifo_ena <= 1'h 0;
	6'h 11 : case(keccak_ctr)
		3'h 1 : ofifo_ena <= 1'h 1;
		3'h 3 : ofifo_ena <= 1'h 1;
		default : ofifo_ena <= 1'h 0;
	endcase
	6'h 19 : ofifo_ena <= 1'h 0;
	6'h 30 : ofifo_ena <= 1'h 0;
	default : ofifo_ena <= ofifo_ena;
endcase

always @(*) if (ofifo1_preload_r1) begin
	NTT_din = 25'h0;
end else case({ofifo0_req_r1,ofifo1_req_r1,req_D0_r1,req_D1_r1})
	4'b 1000, 4'b 1010 : NTT_din = ofifo0_dout;
	4'b 0100 : NTT_din = ofifo1_dout;
	4'b 0010 : NTT_din = DFIFO0_dout;
	default : NTT_din = DFIFO1_dout;
endcase

always @(posedge clk) case(state)
	6'h 0 : DFIFO0_load_b <= 1'h 0;
	6'h 30 : DFIFO0_load_b <= req_D0 ? 1'h 1 : DFIFO0_load_b;
	default : DFIFO0_load_b <= DFIFO0_load_b;
endcase
assign DFIFO0_prog_thresh = {k[2]^k[0],k[2]^k[1]^k[0],7'h7f};
assign DFIFO0_full_eff = DFIFO0_prog_full & ~k[2] | DFIFO0_full & k[2];
always @(posedge clk) case(state)
	6'h 0 : DFIFO0_full_r1 <= 1'h 0;
	6'h 23 : DFIFO0_full_r1 <= DFIFO0_full_eff ? 1'h 1 : DFIFO0_full_r1;
	default : DFIFO0_full_r1 <= DFIFO0_full_r1;
endcase
assign DFIFO0_din = (DFIFO0_full_eff | DFIFO0_full_r1) & ~CCA_enc ? DFIFO0_dout : decode_dout;
assign DFIFO0_wen = (DFIFO0_full_eff | DFIFO0_full_r1) & ~CCA_enc ? req_D0_r1 : decode_valid;

always @(*) case(state)
	6'h 2c : begin
		DFIFO1_din = DFIFO1_dout;
		DFIFO1_wen = req_D1_r1;
	end
	default : begin
		DFIFO1_din = decode_dout;
		DFIFO1_wen = (DFIFO0_full_eff | DFIFO0_full_r1) & decode_valid & ~CCA_enc;
	end
endcase

assign decode_din = DFIFO0_load_b ? OFIFO_dout : IFIFO_dout;
assign decode_fifo_empty = DFIFO0_load_b ? OFIFO_empty : IFIFO_empty;
always @(posedge clk) case(state)
	4'h 0 : decode_sel <= 1'h 0;
	// 5'h 17 : decode_sel <= 1'h 0;
	6'h 23 : decode_sel <= data_rnd_ctr == u_rnd_end && data_ctr == u_ctr_end && decode_req ? 1'h 1 : decode_sel;
	default : decode_sel <= decode_sel;
endcase
assign encode_din = NTT_dout;
always @* case(state)
	6'h 0: encode_wen = 1'h 0;
	default : encode_wen = ~CCA_enc & NTT_valid;
endcase

reg valid_out_reg;
always @(posedge clk) begin
    if (rst) begin
        valid_out_reg <= 1'b0;
    end
    else begin
        // Keep the peer write-enable aligned with the word registered into
        // dout, and suppress requests issued while the producer FIFO is empty.
        valid_out_reg <= req_pk_r1 & ready_pk & ~OFIFO_empty_r1 &
                         ~OFIFO_tx_done;
    end
end
assign valid_out = valid_out_reg;

always @(*) case(state)
	6'h 1a : OFIFO_din = {OFIFO_last,OFIFO_seed,rho[31:0]};
	default : OFIFO_din = OFIFO_req_r1 & ~CCA_enc & ~OFIFO_dout[32] ? OFIFO_dout : {OFIFO_last,OFIFO_seed,encode_dout};
endcase
always @(*) case(state)
	6'h 1a : OFIFO_wen = 1'h 1;
	6'h 1b : OFIFO_wen = OFIFO_req_r1 & ~CCA_enc & ~OFIFO_dout[32];
	default : OFIFO_wen = encode_valid & ~CCA_enc;
endcase
always @(*) begin
	if(DFIFO0_load_b)
		OFIFO_req = decode_req;
	else
		// The Client keeps req_pk asserted while its decoder drains the last
		// public-key words.  Restrict the destructive FIFO read to the actual
		// transmit state; otherwise those trailing request cycles consume the
		// circular copy of t that decapsulation needs for re-encryption.
		// OFIFO has a registered synchronous read port.  When the final rho
		// word (last=1) reaches dout, stop before issuing the otherwise one-cycle
		// look-ahead read that would consume t[0] from the requeued copy.
		OFIFO_req = (state == 6'h1b) & ready_pk & req_pk &
			    ~OFIFO_tx_done & ~OFIFO_dout[33];
end
assign OFIFO_seed = state == 6'h 1a;
assign OFIFO_last = OFIFO_seed && rot_ctr == 3'h 7;
always @(posedge clk) begin
	if(state == 6'h 0)
		OFIFO_tx_done <= 1'h 0;
	else if(OFIFO_dout[33])
		OFIFO_tx_done <= 1'h 1;
	else
		OFIFO_tx_done <= OFIFO_tx_done;
end

always @(*) case({req_D0_r1&~ready_t,req_D1_r1&CCA_enc}) 
	2'b 10 : begin
		cmp0 = {DFIFO0_dout[21:20]&{k[2],k[2]},DFIFO0_dout[19:0]};
		cmp1 = NTT_dout;
	end
	2'b 01 : begin
		cmp0 = {DFIFO1_dout[9:8]&{k[2],k[2]},DFIFO1_dout[7:0]};
		cmp1 = NTT_dout;
	end
	default : begin
		cmp0 = {DFIFO0_dout[21:20]&{k[2],k[2]},DFIFO0_dout[19:0]};
		cmp1 = NTT_dout;
	end
endcase
always @(posedge clk) begin
	if(start)
		equal <= 1'h 1;
	else if(req_D0_r1&~ready_t | req_D1_r1&CCA_enc)
		equal <= cmp0 == cmp1 ? equal : 1'h 0;
	else
		equal <= equal;
end

always @(posedge clk) begin
	if(req_pk_r1 & ready_pk & ~OFIFO_empty_r1 & ~OFIFO_tx_done) begin
		dout <= OFIFO_dout;
		valid <= 1'h 1;
	end
	else if(state == 6'h 31) begin
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
		ofifo1_preload_r1 <= 1'b0;
		req_D0_r1 <= 1'b0;
		req_D1_r1 <= 1'b0;
		decode_req_r1 <= 1'b0;
		OFIFO_empty_r1 <= 1'b1;
		OFIFO_req_r1 <= 1'b0;
		req_pk_r1 <= 1'b0;
	end
	else begin
		ofifo0_req_r1 <= ofifo0_req;
		ofifo1_req_r1 <= ofifo1_req;
		ofifo1_preload_r1 <= ofifo1_preload;
		req_D0_r1 <= req_D0;
		req_D1_r1 <= req_D1;
		decode_req_r1 <= decode_req;
		OFIFO_empty_r1 <= OFIFO_empty;
		OFIFO_req_r1 <= OFIFO_req;
		req_pk_r1 <= req_pk;
	end
end

NTT_core_Server ntt(
.clk(clk),
.rst(rst),
.start(start),
.k(k),
.CCA_enc(CCA_enc),
.CCA_enc_start(CCA_enc_start),
.ready_c(ready_c),
.ready_t(ready_t),
.fifo0_empty(ofifo0_empty),
.fifo1_empty(ofifo1_empty),
	// NTT starts when one complete 256-coefficient noise polynomial is
	// buffered (64 packed words), independent of the FIFO's physical depth.
	.fifo1_full(ofifo1_prog_full),
		.noise_done(ntt_noise_done),
.DFIFO0_full_eff(DFIFO0_full_eff),
.fifo0_req(ofifo0_req),
.fifo1_req_r9(ofifo1_req),
.fifo1_preload(ofifo1_preload),
.ena_sft(ena_sft),
.m_bits({m[129:128],m[1:0]}),
.req_D0(req_D0),
.req_D1(req_D1),
.din(NTT_din),
.m_ena(m_ena),
.m_dec(m_dec),
.finish(NTT_finish),
.valid(NTT_valid),
.dout(NTT_dout)
);
hash_core_Server hash(
.clk(clk),
.rst(rst),
.keccak_init(keccak_init),
.keccak_init_hard((state == 6'h1) || (state == 6'h1a) ||
				  (state == 6'h22) ||
				  (state == 6'h30 && next_state != state)),
.squeeze_init(squeeze_init_early),
.extend(extend),
.patt_bit((state == 6'h 2f) ? 1'b0 : patt_bit),
.eta3_bit((state == 6'h 2f) ? 1'b0 : eta3_bit),
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
.ofifo1_req(ofifo1_req & ~ofifo1_preload),
.ofifo0_prog_thresh(9'd200),
.ofifo0_dout(ofifo0_dout),
.ofifo1_dout(ofifo1_dout),
.ofifo0_full(ofifo0_full),
.ofifo1_full(ofifo1_full),
.ofifo0_empty(ofifo0_empty),
.ofifo1_empty(ofifo1_empty),
.ofifo0_prog_full(ofifo0_prog_full),
.ofifo1_prog_thresh(9'd64),
.ofifo1_prog_full(ofifo1_prog_full),
.keccak_ready(keccak_ready),
.fifo_GENA_ctr(fifo_GENA_ctr),
.matrix_stream_active(matrix_stream_active)
		);
	decode_Server decode(.clk(clk),.rst(rst),.din(decode_din),.fifo_empty(decode_fifo_empty),.CCA(CCA_enc),.sel(decode_sel),.k(k),.dout(decode_dout),.req(decode_req),.valid(decode_valid));
	encode_Server encode(.clk(clk),.rst(rst),.din(encode_din),.wen(encode_wen),.valid(encode_valid),.dout(encode_dout));
	pattern pattern(.k(k),.sel(CCA_enc),.patt(patt),.eta3(eta3),.endp(endp));
	
	// Replaced Xilinx FIFO generators with generic FIFO wrappers
	fifo_wrapper_32_16 IFIFO (
		.clk(clk),
		.rst_n(~rst),
		.wr_en(wen),
		.wr_data(din),
		.rd_en(decode_req),
		.dout(IFIFO_dout),
		.full(IFIFO_full),
		.empty(IFIFO_empty)
	);
	
	fifo_wrapper_34_16 OFIFO (
		.clk(clk),
		.rst_n(~rst),
		.wr_en(OFIFO_wen),
		.wr_data(OFIFO_din),
		.rd_en(OFIFO_req),
		.dout(OFIFO_dout),
		.full(OFIFO_full),
		.empty(OFIFO_empty)
	);
	
	fifo_wrapper_24_16 DFIFO0 (
		.clk(clk),
		.rst_n(~rst),
		.wr_en(DFIFO0_wen),
		.wr_data(DFIFO0_din),
		.rd_en(req_D0),
		.prog_full_thresh(DFIFO0_prog_thresh),
		.dout(DFIFO0_dout),
		.full(DFIFO0_full),
		.empty(DFIFO0_empty),
		.prog_full(DFIFO0_prog_full)
	);
	
	fifo_wrapper_10_16 DFIFO1 (
		.clk(clk),
		.rst_n(~rst),
		.wr_en(DFIFO1_wen),
		.wr_data(DFIFO1_din),
		.rd_en(req_D1),
		.dout(DFIFO1_dout),
		.full(DFIFO1_full),
		.empty(DFIFO1_empty)
	);
	
endmodule
