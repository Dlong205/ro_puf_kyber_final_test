`timescale 1ns / 1ps
`default_nettype none

// Release operational UART boundary. Enrollment, legacy helper parsing and
// diagnostic anchor provisioning are structurally absent/disabled here.
module edge_puf64_operational_uart #(
    parameter integer UART_CLKS_PER_BIT = 868,
    parameter integer PK_WORDS = 200,
    parameter integer CT_WORDS = 192,
    parameter integer RX_TIMEOUT = UART_CLKS_PER_BIT * 24
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

    edge_uart_transport #(
        .CLKS_PER_BIT(UART_CLKS_PER_BIT), .PK_WORDS(PK_WORDS),
        .CT_WORDS(CT_WORDS), .RX_TIMEOUT(RX_TIMEOUT),
        .LEGACY_HELPER_ENABLE(1'b0), .ALLOW_ENROLL(1'b0),
        .EXTERNAL_RESULT_TAG(1'b1)
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
        .ready_pk(ready_pk), .req_c(req_c),
        .stream_out_valid(stream_out_valid),
        .stream_out_data(stream_out_data), .peer_req_pk(peer_req_pk),
        .peer_ready_c(peer_ready_c), .stream_in_valid(stream_in_valid),
        .stream_in_data(stream_in_data), .secret_valid(1'b0),
        .shared_secret(256'd0), .external_result_valid(result_valid),
        .external_result_tag(result_tag)
    );

    edge_puf64_operational_chain u_chain (
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
        .mapped_error(mapped_error), .early_reject(early_reject),
        .bch_corr_bits(), .selected_count(), .result_valid(result_valid),
        .result_tag(result_tag), .scrub_done(), .protocol_start()
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
