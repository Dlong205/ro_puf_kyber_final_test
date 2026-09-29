`timescale 1ns / 1ps
`default_nettype none

// UART bring-up transport for the CPU-free Edge role.  The 32-bit tag is a
// diagnostic equality check, not a cryptographic confirmation protocol.
//
// Phase 1: the public helper is carried inside a 76-byte versioned record
// (scripts/helper_record_spec.py is the single source of truth).  The record
// is parsed and enforced here, before the core runs BCH/KDF/ML-KEM, so a
// wrong magic/version/profile/FE parameter/mapping/reserved byte/CRC or a
// truncated/extra/timed-out stream can never launch the PUF, FE, KDF or
// ML-KEM.  RTL remains the final security enforcement; the firmware mirror
// only rejects earlier on the SoC path.
module edge_uart_transport #(
    parameter integer CLKS_PER_BIT = 868,
    parameter integer PK_WORDS = 200,
    parameter integer CT_WORDS = 192,
    parameter integer RX_TIMEOUT = CLKS_PER_BIT * 24,
    // Non-release board diagnosis only.  This exposes stage identity, never
    // raw PUF response, FE key, KCV value or ML-KEM secret.
    parameter bit DIAGNOSTIC_FAILURE_CODES = 1'b0,
    parameter [7:0]   HREC_PROFILE = 8'h01,
    parameter [7:0]   HREC_FE_PARAM = 8'h01,
    parameter [7:0]   HREC_MAPPING_LEN_BYTES = 8'd33,
    parameter [15:0]  HREC_MAPPING_TAG = 16'hD501,
    parameter [7:0]   HREC_GENERATION = 8'h01,
    // Legacy 33-byte helper is a diagnostic-only escape hatch, OFF by default
    // so release builds cannot silently accept a bare helper.
    parameter bit     LEGACY_HELPER_ENABLE = 1'b0,
    // Enrollment is only permitted in provisioning/manufacturing lifecycle.
    parameter bit     ALLOW_ENROLL = 1'b0,
    // In the operational PUF64 boundary the nonce-bound result tag is
    // computed beside ML-KEM so the shared secret never becomes a top port.
    parameter bit     EXTERNAL_RESULT_TAG = 1'b0,
    // R6.1 qualification telemetry readout.  1 = qualification image
    // (NONRELEASE): private command 0x70 streams the captured sweep frame.
    // 0 = final/release: 0x70 is rejected exactly like any unsupported
    // command (fail 0x01); capture hardware still runs with identical loads.
    parameter bit     QUAL_TELEMETRY_ENABLE = 1'b0,
    // R6.1 image marker: release INFO byte is 0x0f; qualification images use
    // 0x71 ('q') so a qual image can never be mistaken for final on the bench.
    parameter [7:0]   QUAL_INFO_MARKER = 8'h0f
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         uart_rx_i,
    output wire         uart_tx_o,
    output wire         tx_active,

    output reg          core_start,
    output reg          core_zeroize,
    output reg          core_enroll,
    // Set only when one complete v2 record passes every parser check.  The
    // helper, helper KCV and context below are committed on the same edge.
    output reg          core_command_ok,
    output reg  [263:0] helper_in,
    input  wire [263:0] helper_out,
    input  wire [223:0] core_fe_kcv,
    output reg          core_helper_kcv_valid,
    output reg  [223:0] core_helper_kcv,
    output reg  [55:0]  core_kcv_ctx,
    // Enrollment context assembled from the exact header parameters the
    // emitted record carries (same source as build_enroll_record).  The core
    // must never reuse a context latched from a previous SESSION: at ENROLL
    // time core_kcv_ctx is still zero, which used to bind the published KCV
    // to the wrong context (security review finding).
    output wire [55:0]  core_enroll_ctx,
    output wire [31:0]  core_nonce,
    // Diagnostic record telemetry (characterization builds only).
    output reg  [3:0]   record_status,
    output reg          record_fail,
    output reg          zeroize_done,
    input  wire         fe_success,
    input  wire         core_done,
    input  wire         core_busy,
    input  wire         core_mapped_error,
    input  wire [3:0]   core_mapped_error_reason,
    input  wire [7:0]   core_bch_corr,
    input  wire         core_kcv_fail,
    input  wire         core_early_reject,

    input  wire         ready_pk,
    input  wire         req_c,
    input  wire         stream_out_valid,
    input  wire [31:0]  stream_out_data,
    output reg          peer_req_pk,
    output wire         peer_ready_c,
    output reg          stream_in_valid,
    output reg  [31:0]  stream_in_data,

    input  wire         secret_valid,
    input  wire [255:0] shared_secret,
    input  wire         external_result_valid,
    input  wire [31:0]  external_result_tag,
    // R6.1 qualification readout tap (sniffer-owned BRAM, transport FSM).
    // In final builds the sniffer zeroes these; the 0x70 command is gated
    // off by QUAL_TELEMETRY_ENABLE so no private data can be addressed.
    input  wire [81:0]  qual_rd_data,
    input  wire [31:0]  qual_frame_seq,
    input  wire [11:0]  qual_entry_count,
    input  wire [7:0]   qual_hdr_bch_corr,
    input  wire [7:0]   qual_hdr_status,
    input  wire         qual_frame_valid,
    output reg          qual_rd_en,
    output reg  [10:0]  qual_rd_addr
);
    `include "helper_record_spec.vh"

    localparam [7:0] CMD_INFO    = 8'h00;
    localparam [7:0] CMD_ENROLL  = 8'h01;
    localparam [7:0] CMD_SESSION = 8'h02;
    // R6.1 private qualification telemetry readout (qual images only).
    localparam [7:0] CMD_QUAL_TEL = 8'h70;
    localparam [7:0] QUAL_MARK    = 8'h51; // 'Q'
    // Full-sweep frame size (2016-pair RO64 all-pairs sweep).
    localparam integer QUAL_PAIRS = 2016;
    localparam [7:0] STATUS_OK   = 8'haa;
    localparam [7:0] STATUS_FAIL = 8'hff;

    // Transport-level failure codes (record validation uses HREC_ERR_*).
    localparam [7:0] FAIL_TIMEOUT = 8'hf0;
    localparam [7:0] FAIL_TRAILING = 8'hf1;

    localparam [4:0] S_IDLE         = 5'd0;
    localparam [4:0] S_INFO         = 5'd1;
    localparam [4:0] S_ENROLL_WAIT  = 5'd2;
    localparam [4:0] S_ENROLL_SEND  = 5'd3;
    localparam [4:0] S_HELPER_MARK  = 5'd4;
    localparam [4:0] S_CONTEXT_RX   = 5'd5;
    localparam [4:0] S_WAIT_PK      = 5'd6;
    localparam [4:0] S_PK_MARK      = 5'd7;
    localparam [4:0] S_PK_REQ       = 5'd8;
    localparam [4:0] S_PK_WAIT      = 5'd9;
    localparam [4:0] S_PK_SEND      = 5'd10;
    localparam [4:0] S_CT_MARK      = 5'd11;
    localparam [4:0] S_CT_RX        = 5'd12;
    localparam [4:0] S_CT_DELIVER   = 5'd13;
    localparam [4:0] S_SECRET_WAIT  = 5'd14;
    localparam [4:0] S_RESULT_SEND  = 5'd15;
    localparam [4:0] S_ZEROIZE      = 5'd16;
    localparam [4:0] S_FAIL_SEND    = 5'd17;
    localparam [4:0] S_NONCE_RX     = 5'd19;
    localparam [4:0] S_RECORD_RX    = 5'd20;
    localparam [4:0] S_POST_RECORD  = 5'd21;
    // R6.1 qualification readout states (qual images only).
    localparam [4:0] S_QUAL_MARK    = 5'd22;
    localparam [4:0] S_QUAL_HDR     = 5'd23;
    localparam [4:0] S_QUAL_RD      = 5'd24;
    localparam [4:0] S_QUAL_WAIT    = 5'd25;
    localparam [4:0] S_QUAL_SEND    = 5'd26;
    localparam [4:0] S_QUAL_CRC     = 5'd27;

    wire       rx_dv;
    wire [7:0] rx_byte;
    wire       tx_done;
    reg        tx_dv;
    reg  [7:0] tx_byte;
    reg        tx_inflight;
    reg        tx_done_d;
    wire       tx_done_pulse = tx_done && !tx_done_d;

    reg [4:0] state;
    reg [9:0] item_count;
    reg [1:0] byte_count;
    reg [31:0] word_shift;
    reg [31:0] nonce;
    reg [31:0] result_tag;
    reg        ct_buffer_ready;
    reg [31:0] ct_buffer [0:CT_WORDS-1];

    reg  [8*HREC_BYTES-1:0] record_raw;
    reg  [7:0] fail_code;
    // R6.1 qualification readout cursor/state (qual images only; inert in
    // final: 0x70 never reaches these states when QUAL_TELEMETRY_ENABLE=0).
    reg [11:0] qual_addr;
    reg [3:0]  qual_byte;
    reg [87:0] qual_word;
    reg [15:0] qual_crc;
    // Diagnostic-only extra byte: BCH correction count latched with a 0x32
    // failure. Count metadata only, never response/helper/key material.
    reg  [7:0] fail_extra;
    reg  [31:0] rx_idle_count;
    // Sequential CRC state: advanced one byte per received/sent UART byte.
    reg  [15:0] rx_crc;
    reg         crc_lo_ok;
    reg  [15:0] tx_crc;

    wire [3:0]   rec_status;
    wire [263:0] rec_helper;
    wire [223:0] rec_kcv;
    wire [55:0]  rec_ctx;
    wire [7:0]   rec_generation;

    // On the final record byte the parser must see the byte that is being
    // written this same cycle, otherwise a zero-cycle-dead nonce byte sent
    // back-to-back by the host would be lost.  Bytes 0..74 already live in
    // record_raw; substitute the incoming byte for slot 75.
    wire [8*HREC_BYTES-1:0] record_eval =
        (state == S_RECORD_RX && item_count == HREC_BYTES - 1)
        ? {rx_byte, record_raw[8*(HREC_BYTES-1)-1:0]}
        : record_raw;

    // crc_lo_ok is latched at byte 74; the high byte is compared against the
    // current rx_byte (byte 75, the last record byte).  Both are only sampled
    // by the parser on that final cycle.
    wire crc_ok_calc = crc_lo_ok && (rx_byte == rx_crc[15:8]);

    helper_record_parse u_parse (
        .raw(record_eval),
        .expected_profile(HREC_PROFILE),
        .expected_fe_param(HREC_FE_PARAM),
        .expected_mapping_len_bytes(HREC_MAPPING_LEN_BYTES),
        .expected_mapping_tag(HREC_MAPPING_TAG),
        .crc_ok(crc_ok_calc),
        .status(rec_status),
        .helper(rec_helper),
        .kcv_ref(rec_kcv),
        .kcv_ctx(rec_ctx),
        .generation(rec_generation)
    );

    // Kyber_Server samples ready_c before entering its continuous ciphertext
    // receive state.  UART is far too slow to supply that stream on demand,
    // so acknowledge readiness only after the complete ciphertext is buffered.
    assign peer_ready_c = ct_buffer_ready;

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
        .i_Clock(clk), .i_Rst(~rst_n), .i_Rx_Serial(uart_rx_i),
        .o_Rx_DV(rx_dv), .o_Rx_Byte(rx_byte)
    );

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .i_Clock(clk), .i_Rst(~rst_n), .i_Tx_DV(tx_dv),
        .i_Tx_Byte(tx_byte), .o_Tx_Active(tx_active),
        .o_Tx_Serial(uart_tx_o), .o_Tx_Done(tx_done)
    );

    function automatic [7:0] select_word_byte;
        input [31:0] value;
        input [1:0] index;
        begin
            case (index)
                2'd0: select_word_byte = value[7:0];
                2'd1: select_word_byte = value[15:8];
                2'd2: select_word_byte = value[23:16];
                default: select_word_byte = value[31:24];
            endcase
        end
    endfunction

    function automatic [7:0] info_byte;
        input [2:0] index;
        begin
            case (index)
                3'd0: info_byte = 8'h45; // E
                3'd1: info_byte = 8'h41; // A
                3'd2: info_byte = 8'h01;
                3'd3: info_byte = 8'h01; // protocol minor: helper-record v1
                // bit2 accelerator zeroize, bit3 versioned helper record.
                // R6.1: qualification images mark byte4 0x71 ('q'); release
                // images keep 0x0f via the QUAL_INFO_MARKER default.
                default: info_byte = QUAL_INFO_MARKER;
            endcase
        end
    endfunction

    // Enrollment record byte at index idx (0..73), assembled from the
    // provisioned header, the FE helper and the freshly computed KCV.  A byte
    // mux only: the CRC is appended sequentially during transmission so no
    // 592-stage combinational CRC cone is ever synthesized (security review
    // finding).
    function automatic [7:0] enroll_byte_fn;
        input [9:0] idx;
        begin
            if (idx >= HREC_OFF_HELPER && idx < HREC_OFF_HELPER + HREC_HELPER_BYTES)
                enroll_byte_fn = helper_out[8*(idx-HREC_OFF_HELPER) +: 8];
            else if (idx >= HREC_OFF_KCV && idx < HREC_OFF_KCV + HREC_KCV_BYTES)
                enroll_byte_fn = core_fe_kcv[8*(idx-HREC_OFF_KCV) +: 8];
            else case (idx)
                HREC_OFF_RECORD_VERSION:   enroll_byte_fn = HREC_RECORD_VERSION;
                HREC_OFF_PROTOCOL_VERSION: enroll_byte_fn = HREC_PROTOCOL_VERSION;
                HREC_OFF_PROFILE:          enroll_byte_fn = HREC_PROFILE;
                HREC_OFF_FE_PARAM:         enroll_byte_fn = HREC_FE_PARAM;
                HREC_OFF_MAPPING_LEN_BYTES: enroll_byte_fn = HREC_MAPPING_LEN_BYTES;
                HREC_OFF_MAPPING_TAG:      enroll_byte_fn = HREC_MAPPING_TAG[7:0];
                HREC_OFF_MAPPING_TAG + 1:  enroll_byte_fn = HREC_MAPPING_TAG[15:8];
                HREC_OFF_GENERATION:       enroll_byte_fn = HREC_GENERATION;
                HREC_OFF_RESERVED:         enroll_byte_fn = 8'h00;
                10'd0: enroll_byte_fn = HREC_MAGIC[7:0];
                10'd1: enroll_byte_fn = HREC_MAGIC[15:8];
                10'd2: enroll_byte_fn = HREC_MAGIC[23:16];
                10'd3: enroll_byte_fn = HREC_MAGIC[31:24];
                default: enroll_byte_fn = 8'h00;
            endcase
        end
    endfunction

    function automatic [7:0] qual_hdr_byte;
        input [9:0] idx;
        begin
            case (idx)
                10'd0: qual_hdr_byte = qual_frame_seq[7:0];
                10'd1: qual_hdr_byte = qual_frame_seq[15:8];
                10'd2: qual_hdr_byte = qual_frame_seq[23:16];
                10'd3: qual_hdr_byte = qual_frame_seq[31:24];
                10'd4: qual_hdr_byte = qual_entry_count[7:0];
                10'd5: qual_hdr_byte = {4'd0, qual_entry_count[11:8]};
                10'd6: qual_hdr_byte = qual_hdr_bch_corr;
                10'd7: qual_hdr_byte = qual_hdr_status;
                default: qual_hdr_byte = 8'h00;
            endcase
        end
    endfunction

    assign core_enroll_ctx = {HREC_GENERATION, HREC_MAPPING_TAG,
                              HREC_FE_PARAM, HREC_PROFILE,
                              HREC_PROTOCOL_VERSION, HREC_RECORD_VERSION};
    assign core_nonce = nonce;

    // Legacy 33-byte path (diagnostic only) drives helper_in directly.
    wire legacy_mode = LEGACY_HELPER_ENABLE;

    // Keep transport state reset synchronous. Several outputs feed the
    // accelerator RAM/FIFO control path; an asynchronous reset here is
    // otherwise promoted into a large high-fanout reset network by Vivado.
    always @(posedge clk) begin
        if (!rst_n) begin
            state           <= S_IDLE;
            core_start      <= 1'b0;
            core_zeroize    <= 1'b0;
            core_enroll     <= 1'b0;
            core_command_ok <= 1'b0;
            helper_in       <= 264'd0;
            core_helper_kcv_valid <= 1'b0;
            core_helper_kcv <= 224'd0;
            core_kcv_ctx    <= 56'd0;
            peer_req_pk     <= 1'b0;
            stream_in_valid <= 1'b0;
            stream_in_data  <= 32'd0;
            tx_dv           <= 1'b0;
            tx_byte         <= 8'd0;
            tx_inflight     <= 1'b0;
            tx_done_d       <= 1'b0;
            item_count      <= 10'd0;
            byte_count      <= 2'd0;
            word_shift      <= 32'd0;
            nonce           <= 32'd0;
            result_tag      <= 32'd0;
            ct_buffer_ready <= 1'b0;
            record_raw      <= {(8*HREC_BYTES){1'b0}};
            fail_code       <= 8'h00;
            qual_addr       <= 12'd0;
            qual_byte       <= 4'd0;
            qual_word       <= 88'd0;
            qual_crc        <= 16'hFFFF;
            qual_rd_en      <= 1'b0;
            qual_rd_addr    <= 11'd0;
            fail_extra      <= 8'h00;
            rx_idle_count   <= 32'd0;
            record_status   <= 4'd0;
            record_fail     <= 1'b0;
            zeroize_done    <= 1'b0;
            rx_crc          <= 16'hFFFF;
            crc_lo_ok       <= 1'b0;
            tx_crc          <= 16'hFFFF;
        end else begin
            core_start      <= 1'b0;
            core_zeroize    <= 1'b0;
            peer_req_pk     <= 1'b0;
            stream_in_valid <= 1'b0;
            tx_dv           <= 1'b0;
            tx_done_d       <= tx_done;
            zeroize_done    <= 1'b0;
            qual_rd_en      <= 1'b0;
            if (tx_done_pulse)
                tx_inflight <= 1'b0;

            case (state)
                S_IDLE: begin
                    item_count <= 10'd0;
                    byte_count <= 2'd0;
                    rx_idle_count <= 32'd0;
                    if (rx_dv && rx_byte == CMD_INFO) begin
                        state <= S_INFO;
                    end else if (rx_dv && rx_byte == CMD_ENROLL &&
                                 !core_busy && ALLOW_ENROLL) begin
                        core_command_ok <= 1'b0;
                        core_enroll <= 1'b1;
                        core_start <= 1'b1;
                        // Never let a previous SESSION's record context or
                        // reference leak into the enrollment transaction.
                        core_helper_kcv_valid <= 1'b0;
                        core_helper_kcv <= 224'd0;
                        core_kcv_ctx <= 56'd0;
                        record_status <= 4'd0;
                        record_fail <= 1'b0;
                        state <= S_ENROLL_WAIT;
                    end else if (rx_dv && rx_byte == CMD_SESSION &&
                                 !core_busy) begin                        core_enroll <= 1'b0;
                        core_command_ok <= 1'b0;
                        helper_in <= 264'd0;
                        core_helper_kcv <= 224'd0;
                        core_kcv_ctx <= 56'd0;
                        record_status <= 4'd0;
                        record_fail <= 1'b0;
                        // Release build always enforces the KCV gate; the
                        // legacy diagnostic path bypasses the record parser.
                        core_helper_kcv_valid <= !legacy_mode;
                        state <= S_HELPER_MARK;
                    end else if (rx_dv && rx_byte == CMD_QUAL_TEL &&
                                 !core_busy && QUAL_TELEMETRY_ENABLE) begin
                        // R6.1 private frame readout (qual images only).
                        // Final builds (QUAL=0) fall through to the
                        // unsupported-command fail below, byte-identical to
                        // release handling of any unknown command.
                        qual_addr <= 12'd0;
                        qual_byte <= 4'd0;
                        qual_crc <= 16'hFFFF;
                        state <= S_QUAL_MARK;
                    end else if (rx_dv) begin
                        core_command_ok <= 1'b0;
                        fail_code <= 8'h01; // unsupported command
                        state <= S_FAIL_SEND;
                    end
                end

                S_INFO: begin
                    if (!tx_inflight) begin
                        tx_byte <= info_byte(item_count[2:0]);
                        tx_dv <= 1'b1;
                        tx_inflight <= 1'b1;
                    end
                    if (tx_done_pulse) begin
                        if (item_count == 10'd4)
                            state <= S_IDLE;
                        else
                            item_count <= item_count + 1'b1;
                    end
                end

                S_ENROLL_WAIT: begin
                    if (core_done) begin
                        item_count <= 10'd0;
                        tx_crc <= 16'hFFFF;
                        state <= fe_success ? S_ENROLL_SEND : S_FAIL_SEND;
                        if (!fe_success)
                            fail_code <= 8'h02; // enrollment FE failure
                    end
                end

                // STATUS_OK followed by the 76-byte versioned helper record.
                // CRC is advanced one byte per transmitted payload byte; the
                // two trailing CRC bytes are tx_crc[7:0] and tx_crc[15:8].
                S_ENROLL_SEND: begin
                    if (!tx_inflight) begin
                        if (item_count == 0)
                            tx_byte <= STATUS_OK;
                        else if (item_count <= HREC_OFF_CRC)
                            tx_byte <= enroll_byte_fn(item_count - 1);
                        else if (item_count == HREC_OFF_CRC + 1)
                            tx_byte <= tx_crc[7:0];
                        else
                            tx_byte <= tx_crc[15:8];
                        tx_dv <= 1'b1;
                        tx_inflight <= 1'b1;
                        if (item_count >= 1 && item_count <= HREC_OFF_CRC)
                            tx_crc <= hrec_crc16_step(tx_crc,
                                    enroll_byte_fn(item_count - 1));
                    end
                    if (tx_done_pulse) begin
                        if (item_count == HREC_BYTES)
                            state <= S_IDLE;
                        else
                            item_count <= item_count + 1'b1;
                    end
                end

                // 'H' requests a 76-byte helper record followed by a 4-byte
                // nonce.  The record is buffered and validated before the
                // core may start.
                S_HELPER_MARK: begin
                    if (!tx_inflight) begin
                        tx_byte <= 8'h48;
                        tx_dv <= 1'b1;
                        tx_inflight <= 1'b1;
                    end
                    if (tx_done_pulse) begin
                        item_count <= 10'd0;
                        record_raw <= {(8*HREC_BYTES){1'b0}};
                        rx_idle_count <= 32'd0;
                        rx_crc <= 16'hFFFF;
                        crc_lo_ok <= 1'b0;
                        if (legacy_mode)
                            state <= S_CONTEXT_RX;
                        else
                            state <= S_RECORD_RX;
                    end
                end

                S_RECORD_RX: begin
                    if (rx_dv) begin
                        rx_idle_count <= 32'd0;
                        if (item_count == HREC_BYTES - 1) begin
                            // rec_status reflects record_eval (this byte) and
                            // crc_ok_calc folds the byte-74 latched CRC low
                            // with the byte-75 high half.
                            record_status <= rec_status;
                            if (rec_status != HREC_OK) begin
                                core_command_ok <= 1'b0;
                                fail_code <= {4'h0, rec_status};
                                record_fail <= 1'b1;
                                item_count <= 10'd0;
                                state <= S_FAIL_SEND;
                            end else begin
                                // Atomic accepted-record commit.  None of
                                // these fields can change before core_start.
                                helper_in <= rec_helper;
                                core_helper_kcv <= rec_kcv;
                                core_kcv_ctx <= rec_ctx;
                                core_command_ok <= 1'b1;
                                nonce <= 32'd0;
                                item_count <= 10'd0;
                                state <= S_NONCE_RX;
                            end
                        end else begin
                            record_raw[8*item_count +: 8] <= rx_byte;
                            if (item_count < HREC_OFF_CRC)
                                rx_crc <= hrec_crc16_step(rx_crc, rx_byte);
                            else if (item_count == HREC_OFF_CRC)
                                crc_lo_ok <= (rx_byte == rx_crc[7:0]);
                            item_count <= item_count + 1'b1;
                        end
                    end else if (rx_idle_count >= RX_TIMEOUT) begin
                        core_command_ok <= 1'b0;
                        fail_code <= FAIL_TIMEOUT;
                        item_count <= 10'd0;
                        state <= S_FAIL_SEND;
                    end else begin
                        rx_idle_count <= rx_idle_count + 1'b1;
                    end
                end

                // Four nonce bytes, then launch the core with the validated
                // record.  A trailing byte after the nonce aborts fail-closed.
                S_NONCE_RX: begin
                    if (rx_dv) begin
                        rx_idle_count <= 32'd0;
                        nonce[8*item_count +: 8] <= rx_byte;
                        if (item_count == 10'd3) begin
                            state <= S_POST_RECORD;
                        end else begin
                            item_count <= item_count + 1'b1;
                        end
                    end else if (rx_idle_count >= RX_TIMEOUT) begin
                        core_command_ok <= 1'b0;
                        fail_code <= FAIL_TIMEOUT;
                        item_count <= 10'd0;
                        state <= S_FAIL_SEND;
                    end else begin
                        rx_idle_count <= rx_idle_count + 1'b1;
                    end
                end

                // Wait until the line is idle for a full byte time before
                // launching the core.  A byte arriving in this window is a
                // framing error (extra/trailing byte) and aborts fail-closed.
                S_POST_RECORD: begin
                    if (rx_dv) begin
                        core_command_ok <= 1'b0;
                        fail_code <= FAIL_TRAILING;
                        item_count <= 10'd0;
                        state <= S_FAIL_SEND;
                    end else if (core_busy) begin
                        core_command_ok <= 1'b0;
                        fail_code <= 8'h04;
                        item_count <= 10'd0;
                        state <= S_FAIL_SEND;
                    end else if (rx_idle_count >= CLKS_PER_BIT * 11 &&
                                 core_command_ok) begin
                        core_start <= 1'b1;
                        state <= S_WAIT_PK;
                    end else begin
                        rx_idle_count <= rx_idle_count + 1'b1;
                    end
                end

                S_CONTEXT_RX: begin
                    if (rx_dv) begin
                        if (item_count < 33)
                            helper_in[8*item_count +: 8] <= rx_byte;
                        else
                            nonce[8*(item_count-33) +: 8] <= rx_byte;
                        if (item_count == 10'd36) begin
                            core_start <= 1'b1;
                            state <= S_WAIT_PK;
                        end else begin
                            item_count <= item_count + 1'b1;
                        end
                    end
                end

                S_WAIT_PK: begin
                    if (ready_pk) begin
                        item_count <= 10'd0;
                        state <= S_PK_MARK;
                    end else if (core_done) begin
                        if (DIAGNOSTIC_FAILURE_CODES) begin
                            if (core_mapped_error)
                                fail_code <= (core_mapped_error_reason == 4'h0)
                                           ? 8'h31
                                           : {4'h4, core_mapped_error_reason};
                            else if (!fe_success) begin
                                fail_code <= 8'h32; // BCH reconstruction
                                fail_extra <= core_bch_corr;
                            end
                            else if (core_kcv_fail)
                                fail_code <= 8'h33; // trusted KCV gate
                            else if (core_early_reject)
                                fail_code <= 8'h34; // lifecycle gate
                            else
                                fail_code <= 8'h35; // downstream before PK
                        end else begin
                            fail_code <= 8'h03; // generic fail-closed release
                            fail_extra <= 8'h00;
                        end
                        item_count <= 10'd0;
                        state <= S_FAIL_SEND;
                    end
                end

                S_PK_MARK: begin
                    if (!tx_inflight) begin
                        tx_byte <= 8'h50;
                        tx_dv <= 1'b1;
                        tx_inflight <= 1'b1;
                    end
                    if (tx_done_pulse)
                        state <= S_PK_REQ;
                end

                S_PK_REQ: begin
                    peer_req_pk <= 1'b1;
                    state <= S_PK_WAIT;
                end

                S_PK_WAIT: begin
                    if (stream_out_valid) begin
                        word_shift <= stream_out_data;
                        byte_count <= 2'd0;
                        state <= S_PK_SEND;
                    end
                end

                S_PK_SEND: begin
                    if (!tx_inflight) begin
                        tx_byte <= select_word_byte(word_shift, byte_count);
                        tx_dv <= 1'b1;
                        tx_inflight <= 1'b1;
                    end
                    if (tx_done_pulse) begin
                        if (byte_count == 2'd3) begin
                            if (item_count == PK_WORDS-1)
                                state <= S_CT_MARK;
                            else begin
                                item_count <= item_count + 1'b1;
                                state <= S_PK_REQ;
                            end
                        end else begin
                            byte_count <= byte_count + 1'b1;
                        end
                    end
                end

                S_CT_MARK: begin
                    if (!tx_inflight) begin
                        tx_byte <= 8'h43;
                        tx_dv <= 1'b1;
                        tx_inflight <= 1'b1;
                    end
                    if (tx_done_pulse) begin
                        item_count <= 10'd0;
                        byte_count <= 2'd0;
                        ct_buffer_ready <= 1'b0;
                        state <= S_CT_RX;
                    end
                end

                S_CT_RX: begin
                    if (rx_dv) begin
                        word_shift[8*byte_count +: 8] <= rx_byte;
                        if (byte_count == 2'd3) begin
                            ct_buffer[item_count] <= {rx_byte, word_shift[23:0]};
                            byte_count <= 2'd0;
                            if (item_count == CT_WORDS-1) begin
                                item_count <= 10'd0;
                                ct_buffer_ready <= 1'b1;
                                state <= S_CT_DELIVER;
                            end else begin
                                item_count <= item_count + 1'b1;
                            end
                        end else begin
                            byte_count <= byte_count + 1'b1;
                        end
                    end
                end

                S_CT_DELIVER: begin
                    if (req_c && ct_buffer_ready) begin
                        stream_in_data <= ct_buffer[item_count];
                        stream_in_valid <= 1'b1;
                        if (item_count == CT_WORDS-1) begin
                            state <= S_SECRET_WAIT;
                        end else begin
                            item_count <= item_count + 1'b1;
                        end
                    end
                end

                S_SECRET_WAIT: begin
                    if ((EXTERNAL_RESULT_TAG && external_result_valid) ||
                        (!EXTERNAL_RESULT_TAG && secret_valid)) begin
                        // Kyber_Server continues to use ready_c after the last
                        // ciphertext word while its NTT enters the CCA path.
                        // Match Kyber_Client: retire ready_c only when the
                        // shared secret is complete.
                        ct_buffer_ready <= 1'b0;
                        if (EXTERNAL_RESULT_TAG)
                            result_tag <= external_result_tag;
                        else
                            result_tag <= nonce ^ shared_secret[31:0] ^
                                shared_secret[63:32] ^ shared_secret[95:64] ^
                                shared_secret[127:96] ^ shared_secret[159:128] ^
                                shared_secret[191:160] ^ shared_secret[223:192] ^
                                shared_secret[255:224];
                        item_count <= 10'd0;
                        state <= S_RESULT_SEND;
                    end
                end

                // STATUS_OK plus a deliberately non-cryptographic 32-bit tag.
                S_RESULT_SEND: begin
                    if (!tx_inflight) begin
                        tx_byte <= item_count == 0 ? STATUS_OK :
                                   select_word_byte(result_tag, item_count[1:0]-1'b1);
                        tx_dv <= 1'b1;
                        tx_inflight <= 1'b1;
                    end
                    if (tx_done_pulse) begin
                        if (item_count == 10'd4)
                            state <= S_ZEROIZE;
                        else
                            item_count <= item_count + 1'b1;
                    end
                end

                // R6.1 private qualification frame readout (qual images
                // only; unreachable in final: S_IDLE never enters here when
                // QUAL_TELEMETRY_ENABLE=0).  Streams 'Q' + 10-byte header +
                // 2016 x 11-byte entries {c0,c1,a,b,flags} + CRC16.  Never
                // touches the release SESSION path; returns to S_IDLE without
                // zeroize so the frame survives for re-read.
                S_QUAL_MARK: begin
                    if (!tx_inflight) begin
                        tx_byte <= QUAL_MARK;
                        tx_dv <= 1'b1;
                        tx_inflight <= 1'b1;
                    end
                    if (tx_done_pulse) begin
                        item_count <= 10'd0;
                        state <= S_QUAL_HDR;
                    end
                end

                S_QUAL_HDR: begin
                    if (!tx_inflight) begin
                        tx_byte <= qual_hdr_byte(item_count);
                        tx_dv <= 1'b1;
                        tx_inflight <= 1'b1;
                        qual_crc <= hrec_crc16_step(qual_crc,
                            qual_hdr_byte(item_count));
                    end
                    if (tx_done_pulse) begin
                        if (item_count == 10'd9) begin
                            item_count <= 10'd0;
                            qual_addr <= 12'd0;
                            state <= S_QUAL_RD;
                        end else begin
                            item_count <= item_count + 1'b1;
                        end
                    end
                end

                S_QUAL_RD: begin
                    qual_rd_en <= 1'b1;
                    qual_rd_addr <= qual_addr[10:0];
                    state <= S_QUAL_WAIT;
                end

                S_QUAL_WAIT: begin
                    // Hold the read address; BRAM data lands in rd_q at the
                    // end of this cycle.  qual_byte=15 marks "word not yet
                    // loaded" for S_QUAL_SEND.
                    qual_rd_en <= 1'b1;
                    qual_rd_addr <= qual_addr[10:0];
                    qual_byte <= 4'd15;
                    state <= S_QUAL_SEND;
                end

                S_QUAL_SEND: begin
                    if (qual_byte == 4'd15) begin
                        qual_word <= {{2'b00, qual_rd_data[5], qual_rd_data[4],
                                       qual_rd_data[3], qual_rd_data[2],
                                       qual_rd_data[1], qual_rd_data[0]},
                                      {2'b00, qual_rd_data[11:6]},
                                      {2'b00, qual_rd_data[17:12]},
                                      qual_rd_data[49:18], qual_rd_data[81:50]};
                        qual_byte <= 4'd0;
                    end else begin
                        if (!tx_inflight) begin
                            tx_byte <= qual_word[8*qual_byte +: 8];
                            tx_dv <= 1'b1;
                            tx_inflight <= 1'b1;
                            qual_crc <= hrec_crc16_step(qual_crc,
                                qual_word[8*qual_byte +: 8]);
                        end
                        if (tx_done_pulse) begin
                            if (qual_byte == 4'd10) begin
                                if (qual_addr == 12'(QUAL_PAIRS - 1)) begin
                                    item_count <= 10'd0;
                                    state <= S_QUAL_CRC;
                                end else begin
                                    qual_addr <= qual_addr + 1'b1;
                                    state <= S_QUAL_RD;
                                end
                            end else begin
                                qual_byte <= qual_byte + 1'b1;
                            end
                        end
                    end
                end

                S_QUAL_CRC: begin
                    if (!tx_inflight) begin
                        tx_byte <= item_count == 0 ? qual_crc[7:0]
                                                   : qual_crc[15:8];
                        tx_dv <= 1'b1;
                        tx_inflight <= 1'b1;
                    end
                    if (tx_done_pulse) begin
                        if (item_count == 10'd0)
                            item_count <= 10'd1;
                        else
                            state <= S_IDLE;
                    end
                end

                S_ZEROIZE: begin
                    core_zeroize <= 1'b1;
                    zeroize_done <= 1'b1;
                    core_command_ok <= 1'b0;
                    helper_in <= 264'd0;
                    core_helper_kcv_valid <= 1'b0;
                    core_helper_kcv <= 224'd0;
                    core_kcv_ctx <= 56'd0;
                    nonce <= 32'd0;
                    result_tag <= 32'd0;
                    stream_in_data <= 32'd0;
                    word_shift <= 32'd0;
                    ct_buffer_ready <= 1'b0;
                    record_raw <= {(8*HREC_BYTES){1'b0}};
                    rx_idle_count <= 32'd0;
                    state <= S_IDLE;
                end

                // STATUS_FAIL plus a failure code byte (record validation
                // code, transport timeout, or command error). Diagnostic
                // images append the BCH correction count after a 0x32 so
                // the host can tell marginal noise from a systematic
                // shift; release images always send exactly 2 bytes.
                S_FAIL_SEND: begin
                    if (!tx_inflight) begin
                        tx_byte <= item_count == 0 ? STATUS_FAIL :
                                   item_count == 1 ? fail_code : fail_extra;
                        tx_dv <= 1'b1;
                        tx_inflight <= 1'b1;
                    end
                    if (tx_done_pulse) begin
                        if (DIAGNOSTIC_FAILURE_CODES && fail_code == 8'h32 &&
                            item_count == 10'd1)
                            item_count <= 10'd2;
                        else if (item_count == 10'd1 ||
                                 item_count == 10'd2)
                            state <= S_ZEROIZE;
                        else
                            item_count <= item_count + 1'b1;
                    end
                end

                default: state <= S_ZEROIZE;
            endcase
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (core_start && !core_enroll && !legacy_mode && !core_command_ok)
            $error("reconstruction core_start without an accepted v2 record");
    end
`endif
endmodule

`default_nettype wire
