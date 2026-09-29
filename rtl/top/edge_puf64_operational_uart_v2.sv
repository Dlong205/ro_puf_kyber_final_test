`timescale 1ns / 1ps
`default_nettype none

// Release operational UART boundary, macro-V2 edition (CONSTRUCTION shell,
// NON-RELEASE).  Identical to edge_puf64_operational_uart except the chain
// is edge_puf64_operational_chain_v2.  Enrollment, legacy helper parsing and
// diagnostic anchor provisioning are structurally absent/disabled here.
module edge_puf64_operational_uart_v2 #(
    parameter integer UART_CLKS_PER_BIT = 868,
    parameter integer PK_WORDS = 200,
    parameter integer CT_WORDS = 192,
    parameter integer RX_TIMEOUT = UART_CLKS_PER_BIT * 24,
    // Frozen helper-record identity (must match v2_mapping_frozen tag).
    // uart_v2 previously inherited the stale transport default (0xD501)
    // and rejected the qualified helper with record status 6 (0x06).
    parameter [15:0] HREC_MAPPING_TAG = 16'h81B5,
    parameter [7:0]  HREC_GENERATION = 8'h01,
    // R7: capture-timeout 2048 (was 1024). A placement-marginal pair near
    // sweep index 867 intermittently exceeds 1024 units on the final path
    // (8/60 warm sweeps abort at exactly 867 with CRC-valid headers),
    // while the same macro never trips it on the qual path. The timeout
    // only sets the abort threshold, never the counts; raising it turns
    // silent aborts into visible data the selector can judge. Qual-path
    // images (separate uart) keep 1024.
    parameter integer CAPTURE_TIMEOUT = 2048,
    // Bench-only failure granularity. 0 = release (generic 0x03, no stage
    // oracle); 1 = diagnostic (0x31/0x32/0x33/0x34/0x35 + BCH count).
    // Release builds must keep 0; diagnostic images are bench-only and
    // never frozen.
    parameter bit DIAGNOSTIC_FAILURE_CODES = 1'b0,
    // R7 characterize-through-final: forwarded to the chain (sniffer
    // readout gate) and the transport (0x70 command + INFO marker).
    // Defaults = release; char builds override all three together.
    parameter bit     QUALIFICATION_NONRELEASE = 1'b0,
    parameter bit     QUAL_TELEMETRY_ENABLE = 1'b0,
    parameter [7:0]   QUAL_INFO_MARKER = 8'h0f,
    // R7: forwarded to the chain scheduler (char builds raise for collection;
    // release keeps 2).
    parameter integer TIE_BUDGET = 2
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         mmcm_locked,
    input  wire         uart_rx_i,
    output wire         uart_tx_o,
    output wire         tx_active,
    input  wire         trusted_kcv_valid,
    input  wire [223:0] trusted_kcv_ref,
    output wire         busy,
    output wire         done,
    output wire         kcv_fail,
    output wire         mapped_error,
    output wire         early_reject
);
    wire         core_start;
    wire         core_zeroize;
    wire         core_enroll;
    wire         core_command_ok;
    wire [263:0] helper_in;
    wire         helper_kcv_valid;
    wire [223:0] helper_kcv_ref;
    wire [55:0]  kcv_ctx;
    wire [31:0]  result_nonce;
    wire         fe_success;
    wire         ready_pk;
    wire         req_c;
    wire         stream_out_valid;
    wire [31:0]  stream_out_data;
    wire         peer_req_pk;
    wire         peer_ready_c;
    wire         stream_in_valid;
    wire [31:0]  stream_in_data;
    wire         result_valid;
    wire [31:0]  result_tag;
    // Chain status back to the transport for fail-closed reporting.
    // Release mode only emits generic 0x03, but the wires must still be
    // driven (previously floating -> Synth 8-7071, hidden stage info).
    wire [3:0]   chain_mapped_reason;
    wire [7:0]   chain_bch_corr;
    // R7 qual readout tap (transport-owned FSM, sniffer BRAM). In release
    // builds the sniffer zeroes the data; the 0x70 command is gated off.
    wire         qual_rd_en;
    wire [10:0]  qual_rd_addr;
    wire [81:0]  qual_rd_data;
    wire [31:0]  qual_frame_seq;
    wire [11:0]  qual_entry_count;
    wire [7:0]   qual_hdr_bch_corr;
    wire [7:0]   qual_hdr_status;
    wire         qual_frame_valid;

    edge_uart_transport #(
        .CLKS_PER_BIT(UART_CLKS_PER_BIT), .PK_WORDS(PK_WORDS),
        .CT_WORDS(CT_WORDS), .RX_TIMEOUT(RX_TIMEOUT),
        .LEGACY_HELPER_ENABLE(1'b0), .ALLOW_ENROLL(1'b0),
        .HREC_MAPPING_TAG(HREC_MAPPING_TAG),
        .HREC_GENERATION(HREC_GENERATION),
        .DIAGNOSTIC_FAILURE_CODES(DIAGNOSTIC_FAILURE_CODES),
        .EXTERNAL_RESULT_TAG(1'b1),
        .QUAL_TELEMETRY_ENABLE(QUAL_TELEMETRY_ENABLE),
        .QUAL_INFO_MARKER(QUAL_INFO_MARKER)
    ) u_transport (
        .clk(clk), .rst_n(rst_n), .uart_rx_i(uart_rx_i),
        .uart_tx_o(uart_tx_o), .tx_active(tx_active),
        .core_start(core_start), .core_zeroize(core_zeroize),
        .core_enroll(core_enroll), .core_command_ok(core_command_ok),
        .helper_in(helper_in), .helper_out(264'd0), .core_fe_kcv(224'd0),
        .core_helper_kcv_valid(helper_kcv_valid),
        .core_helper_kcv(helper_kcv_ref), .core_kcv_ctx(kcv_ctx),
        .core_enroll_ctx(), .core_nonce(result_nonce),
        .record_status(), .record_fail(), .zeroize_done(),
        .fe_success(fe_success), .core_done(done), .core_busy(busy),
        .core_mapped_error(mapped_error),
        .core_mapped_error_reason(chain_mapped_reason),
        .core_bch_corr(chain_bch_corr),
        .core_kcv_fail(kcv_fail),
        .core_early_reject(early_reject),
        .ready_pk(ready_pk), .req_c(req_c),
        .stream_out_valid(stream_out_valid),
        .stream_out_data(stream_out_data), .peer_req_pk(peer_req_pk),
        .peer_ready_c(peer_ready_c), .stream_in_valid(stream_in_valid),
        .stream_in_data(stream_in_data), .secret_valid(1'b0),
        .shared_secret(256'd0), .external_result_valid(result_valid),
        .external_result_tag(result_tag),
        .qual_rd_data(qual_rd_data),
        .qual_frame_seq(qual_frame_seq),
        .qual_entry_count(qual_entry_count),
        .qual_hdr_bch_corr(qual_hdr_bch_corr),
        .qual_hdr_status(qual_hdr_status),
        .qual_frame_valid(qual_frame_valid),
        .qual_rd_en(qual_rd_en),
        .qual_rd_addr(qual_rd_addr)
    );

    (* KEEP_HIERARCHY = "yes" *) edge_puf64_operational_chain_v2 #(
        .QUALIFICATION_NONRELEASE(QUALIFICATION_NONRELEASE),
        .CAPTURE_TIMEOUT(CAPTURE_TIMEOUT),
        .TIE_BUDGET(TIE_BUDGET)
    ) u_chain (
        .clk(clk), .rst_n(rst_n), .zeroize(core_zeroize),
        .start(core_start), .command_ok(core_command_ok),
        .helper_in(helper_in), .mmcm_locked(mmcm_locked),
        .trusted_kcv_valid(trusted_kcv_valid),
        .trusted_kcv_ref(trusted_kcv_ref),
        .helper_kcv_ref(helper_kcv_ref),
        .helper_kcv_valid(helper_kcv_valid), .kcv_ctx(kcv_ctx),
        .result_nonce(result_nonce), .stream_in_valid(stream_in_valid),
        .peer_ready_c(peer_ready_c), .peer_req_pk(peer_req_pk),
        .stream_in_data(stream_in_data), .ready_pk(ready_pk), .req_c(req_c),
        .stream_out_valid(stream_out_valid),
        .stream_out_data(stream_out_data), .busy(busy), .done(done),
        .fe_success(fe_success), .kcv_pass(), .kcv_fail(kcv_fail),
        .mapped_error(mapped_error),
        .mapped_error_reason(chain_mapped_reason),
        .early_reject(early_reject),
        .bch_corr_bits(chain_bch_corr),
        .selected_count(), .result_valid(result_valid),
        .result_tag(result_tag), .scrub_done(), .protocol_start(),
        .qual_rd_en(qual_rd_en), .qual_rd_addr(qual_rd_addr),
        .qual_rd_data(qual_rd_data),
        .qual_frame_seq(qual_frame_seq),
        .qual_entry_count(qual_entry_count),
        .qual_hdr_bch_corr(qual_hdr_bch_corr),
        .qual_hdr_status(qual_hdr_status),
        .qual_frame_valid(qual_frame_valid)
    );

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (core_enroll)
            $error("enrollment asserted in the operational UART boundary");
        if (core_start && !core_command_ok)
            $error("core_start asserted without atomic parser acceptance");
    end
`endif
endmodule

`default_nettype wire
