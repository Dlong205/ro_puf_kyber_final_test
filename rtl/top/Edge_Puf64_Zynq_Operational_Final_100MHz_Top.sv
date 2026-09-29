`timescale 1ns / 1ps
`default_nettype none

// Operational FINAL, macro-V2 edition (release-candidate, single-clock).
// Mapping: rtl/puf/v2_mapping_frozen tag 0x81b5 (holdout-qualified, build 3).
// Anchor: device trusted KCV provisioned from the qualified physical image
// (board ZYNQ-A01, char bitstream cfc72674.., macro bd0cd620.., fp 7d12e3a9..).
// Single-clock shell: only clk_sys_100mhz (+ MMCM feedback) drives logic;
// the stale OOC macro_clk primary is removed post-import in the final build
// script (shell constraint only, macro placement/routing untouched).
module Edge_Puf64_Zynq_Operational_Final_100MHz_Top #(
    parameter integer UART_CLKS_PER_BIT = 868,
    parameter integer RX_TIMEOUT_BITS = 1024,
    // R7 characterize-through-final: 1 = characterization build (private
    // telemetry readout enabled, NONRELEASE image, INFO marker 0x71);
    // 0 = release (readout forced to zero, INFO marker 0x0f). Capture
    // hardware is identical in both; only the readout mux differs.
    // Release builds must keep all three at default; char images are
    // bench-only and never frozen.
    parameter bit     QUALIFICATION_NONRELEASE = 1'b0,
    parameter bit     QUAL_TELEMETRY_ENABLE = 1'b0,
    parameter [7:0]   QUAL_INFO_MARKER = 8'h0f,
    // R7: matches uart_v2/chain (see note there). Release and char share it.
    parameter integer CAPTURE_TIMEOUT = 2048,
    // R7: scheduler tie budget (release keeps 2; char builds override to 8
    // via project generics to collect data through marginal pairs).
    parameter integer TIE_BUDGET = 2,
    // R8 cutover: helper-record identity (default gen1 0x81B5; R7 builds
    // override to 0x81B7 via project generics — never by editing RTL).
    parameter [15:0] HREC_MAPPING_TAG = 16'h81B5,
    parameter [7:0]  HREC_GENERATION = 8'h01
) (
    input  wire       CLK50MHZ,
    input  wire       UART_RXD,
    output wire       UART_TXD,
    output wire [1:0] LED
);
    // Security/lifecycle configuration is deliberately not overridable from
    // the project or module parameter list.
    localparam bit ALLOW_ENROLL         = 1'b0;
    localparam bit LEGACY_HELPER_ENABLE = 1'b0;
    localparam bit DIAGNOSTIC_ANCHOR    = 1'b0;
    // Device trusted KCV (224-bit public verifier) provisioned by
    // scripts/embed_final_anchor.py from the qualified anchor manifest.
    // The all-zero value below means UNPROVISIONED and the static gate
    // refuses to build; the embed step replaces exactly these 56 hex digits.
    // FINAL_ANCHOR_PROVISIONED_FROM_QUALIFIED_MANIFEST
    localparam [223:0] DEVICE_TRUSTED_KCV =
        224'h7b13b8b5841f8633700aba17314a4ead389a4d568c58889a49ee4a29;

    wire clk_feedback;
    wire clk_feedback_raw;
    wire clk_100_raw;
    wire clk_100;
    wire mmcm_locked;

    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKFBOUT_MULT_F(20.0),
        .CLKFBOUT_PHASE(0.0),
        .CLKIN1_PERIOD(20.0),
        .CLKOUT0_DIVIDE_F(10.0),
        .CLKOUT0_DUTY_CYCLE(0.5),
        .CLKOUT0_PHASE(0.0),
        .DIVCLK_DIVIDE(1),
        .REF_JITTER1(0.0),
        .STARTUP_WAIT("FALSE")
    ) mmcm_i (
        .CLKOUT0(clk_100_raw),
        .CLKFBOUT(clk_feedback_raw),
        .CLKFBIN(clk_feedback),
        .CLKIN1(CLK50MHZ),
        .PWRDWN(1'b0),
        .RST(1'b0),
        .LOCKED(mmcm_locked)
    );

    BUFG bufg_feedback (
        .I(clk_feedback_raw),
        .O(clk_feedback)
    );

    BUFG bufg_sys (
        .I(clk_100_raw),
        .O(clk_100)
    );

    // Synchronize LOCKED and generate both assertion and deassertion of the
    // core reset on clk_100 edges.  No asynchronous reset enters the portable
    // operational hierarchy.
    (* ASYNC_REG = "TRUE" *) reg [1:0] locked_sync = 2'b00;
    reg [15:0] reset_count = 16'd0;
    reg reset_n = 1'b0;
    always @(posedge clk_100) begin
        locked_sync <= {locked_sync[0], mmcm_locked};
        if (!locked_sync[1]) begin
            reset_count <= 16'd0;
            reset_n <= 1'b0;
        end else if (!reset_n) begin
            reset_count <= reset_count + 1'b1;
            if (&reset_count)
                reset_n <= 1'b1;
        end
    end

    wire [223:0] trusted_kcv_ref;
    wire trusted_kcv_valid;
    wire anchor_diagnostic;
    wire tx_active;
    wire busy;
    wire done;
    wire kcv_fail;
    wire mapped_error;
    wire early_reject;

    // Final: operational and device-anchored. Provisioning path is
    // structurally absent (DIAGNOSTIC=0 ignores provision; ports tied off).
    // KEEP_HIERARCHY+DONT_TOUCH: with DIAGNOSTIC=0 all outputs reduce to
    // build-time ROM constants, so without this the anchor cell would be
    // constant-folded and the lifecycle audit could not prove the trusted
    // anchor from the netlist.
    (* KEEP_HIERARCHY = "yes" *) (* DONT_TOUCH = "yes" *) edge_kcv_anchor #(
        .DIAGNOSTIC(DIAGNOSTIC_ANCHOR),
        .ROM_REF(DEVICE_TRUSTED_KCV),
        .ROM_VALID(1'b1)
    ) u_kcv_anchor (
        .clk(clk_100),
        .rst_n(reset_n),
        .zeroize(1'b0),
        .provision(1'b0),
        .provision_ref(224'd0),
        .provision_valid(1'b0),
        .trusted_kcv_ref(trusted_kcv_ref),
        .trusted_kcv_valid(trusted_kcv_valid),
        .anchor_locked(),
        .anchor_diagnostic(anchor_diagnostic)
    );

    (* KEEP_HIERARCHY = "yes" *) edge_puf64_operational_uart_v2 #(
        .UART_CLKS_PER_BIT(UART_CLKS_PER_BIT),
        .RX_TIMEOUT(RX_TIMEOUT_BITS * UART_CLKS_PER_BIT),
        .QUALIFICATION_NONRELEASE(QUALIFICATION_NONRELEASE),
        .QUAL_TELEMETRY_ENABLE(QUAL_TELEMETRY_ENABLE),
        .QUAL_INFO_MARKER(QUAL_INFO_MARKER),
        .CAPTURE_TIMEOUT(CAPTURE_TIMEOUT),
        .TIE_BUDGET(TIE_BUDGET),
        .HREC_MAPPING_TAG(HREC_MAPPING_TAG),
        .HREC_GENERATION(HREC_GENERATION)
    ) u_operational_uart (
        .clk(clk_100),
        .rst_n(reset_n),
        .mmcm_locked(locked_sync[1]),
        .uart_rx_i(UART_RXD),
        .uart_tx_o(UART_TXD),
        .tx_active(tx_active),
        .trusted_kcv_valid(trusted_kcv_valid),
        .trusted_kcv_ref(trusted_kcv_ref),
        .busy(busy),
        .done(done),
        .kcv_fail(kcv_fail),
        .mapped_error(mapped_error),
        .early_reject(early_reject)
    );

    assign LED[0] = tx_active;
    assign LED[1] = locked_sync[1] && (busy || kcv_fail || mapped_error || early_reject);

    wire unused_status = done ^ anchor_diagnostic ^ ALLOW_ENROLL ^
                         LEGACY_HELPER_ENABLE;

`ifndef SYNTHESIS
    initial begin
        if (ALLOW_ENROLL || LEGACY_HELPER_ENABLE || DIAGNOSTIC_ANCHOR)
            $fatal(1, "final operational lifecycle controls are not locked off");
        if (DEVICE_TRUSTED_KCV == 224'd0)
            $fatal(1, "final anchor unprovisioned");
    end
`endif
endmodule

`default_nettype wire
