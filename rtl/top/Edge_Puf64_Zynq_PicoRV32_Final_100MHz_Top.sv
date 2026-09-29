`timescale 1ns / 1ps
`default_nettype none

// Operational FINAL with PicoRV32 as a mandatory, non-secret control plane.
// Mapping generation (tag/generation/anchor) is a build parameter defaulting
// to frozen gen1 (tag 0x81b5); the routed macro-V2 checkpoint is unchanged.
module Edge_Puf64_Zynq_PicoRV32_Final_100MHz_Top #(
    parameter integer UART_CLKS_PER_BIT = 868,
    parameter integer RX_TIMEOUT_BITS = 1024,
    parameter bit DIAGNOSTIC_FAILURE_CODES = 1'b0,
    parameter [15:0] HREC_MAPPING_TAG = 16'h81B5,
    parameter [7:0]  HREC_GENERATION = 8'h01,
    parameter [223:0] DEVICE_TRUSTED_KCV =
        224'h7b13b8b5841f8633700aba17314a4ead389a4d568c58889a49ee4a29,
    // R6.1 operational-qualification superset (defaults = final behavior).
    // Qualification builds override these via the single set_property generic
    // call (same pattern as DIAGNOSTIC_FAILURE_CODES): readout enabled,
    // INFO marked 0x71.  Capture hardware runs unconditionally in both, so
    // telemetry loads are identical; only the private readout mux is gated.
    parameter bit QUALIFICATION_NONRELEASE = 1'b0,
    parameter [7:0] QUAL_INFO_MARKER = 8'h0f
) (
    input  wire       CLK50MHZ,
    input  wire       UART_RXD,
    output wire       UART_TXD,
    output wire [1:0] LED
);
    localparam bit ALLOW_ENROLL         = 1'b0;
    localparam bit LEGACY_HELPER_ENABLE = 1'b0;
    localparam bit DIAGNOSTIC_ANCHOR    = 1'b0;

    wire clk_feedback;
    wire clk_feedback_raw;
    wire clk_100_raw;
    wire clk_100;
    wire mmcm_locked;

    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"), .CLKFBOUT_MULT_F(20.0),
        .CLKFBOUT_PHASE(0.0), .CLKIN1_PERIOD(20.0),
        .CLKOUT0_DIVIDE_F(10.0), .CLKOUT0_DUTY_CYCLE(0.5),
        .CLKOUT0_PHASE(0.0), .DIVCLK_DIVIDE(1),
        .REF_JITTER1(0.0), .STARTUP_WAIT("FALSE")
    ) mmcm_i (
        .CLKOUT0(clk_100_raw), .CLKFBOUT(clk_feedback_raw),
        .CLKFBIN(clk_feedback), .CLKIN1(CLK50MHZ),
        .PWRDWN(1'b0), .RST(1'b0), .LOCKED(mmcm_locked)
    );

    BUFG bufg_feedback (.I(clk_feedback_raw), .O(clk_feedback));
    BUFG bufg_sys (.I(clk_100_raw), .O(clk_100));

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
    wire cpu_ready;
    wire cpu_trap;

    (* KEEP_HIERARCHY = "yes" *) (* DONT_TOUCH = "yes" *) edge_kcv_anchor #(
        .DIAGNOSTIC(DIAGNOSTIC_ANCHOR),
        .ROM_REF(DEVICE_TRUSTED_KCV), .ROM_VALID(1'b1)
    ) u_kcv_anchor (
        .clk(clk_100), .rst_n(reset_n), .zeroize(1'b0),
        .provision(1'b0), .provision_ref(224'd0),
        .provision_valid(1'b0), .trusted_kcv_ref(trusted_kcv_ref),
        .trusted_kcv_valid(trusted_kcv_valid), .anchor_locked(),
        .anchor_diagnostic(anchor_diagnostic)
    );

    (* KEEP_HIERARCHY = "yes" *) edge_puf64_operational_uart_picorv32 #(
        .UART_CLKS_PER_BIT(UART_CLKS_PER_BIT),
        .RX_TIMEOUT(RX_TIMEOUT_BITS * UART_CLKS_PER_BIT),
        .DIAGNOSTIC_FAILURE_CODES(DIAGNOSTIC_FAILURE_CODES),
        .HREC_MAPPING_TAG(HREC_MAPPING_TAG),
        .HREC_GENERATION(HREC_GENERATION),
        .QUALIFICATION_NONRELEASE(QUALIFICATION_NONRELEASE),
        .QUAL_TELEMETRY_ENABLE(QUALIFICATION_NONRELEASE),
        .QUAL_INFO_MARKER(QUAL_INFO_MARKER)
    ) u_operational_uart (
        .clk(clk_100), .rst_n(reset_n), .mmcm_locked(locked_sync[1]),
        .uart_rx_i(UART_RXD), .uart_tx_o(UART_TXD),
        .tx_active(tx_active), .trusted_kcv_valid(trusted_kcv_valid),
        .trusted_kcv_ref(trusted_kcv_ref), .busy(busy), .done(done),
        .kcv_fail(kcv_fail), .mapped_error(mapped_error),
        .early_reject(early_reject), .cpu_ready(cpu_ready),
        .cpu_trap(cpu_trap)
    );

    assign LED[0] = tx_active;
    assign LED[1] = !cpu_ready || cpu_trap || busy || kcv_fail ||
                    mapped_error || early_reject;

    wire unused_status = done ^ anchor_diagnostic ^ ALLOW_ENROLL ^
                         LEGACY_HELPER_ENABLE ^ QUALIFICATION_NONRELEASE;

`ifndef SYNTHESIS
    initial begin
        if (ALLOW_ENROLL || LEGACY_HELPER_ENABLE || DIAGNOSTIC_ANCHOR)
            $fatal(1, "PicoRV32 final lifecycle controls are not locked off");
        if (DEVICE_TRUSTED_KCV == 224'd0)
            $fatal(1, "PicoRV32 final anchor unprovisioned");
        // R6.1: a release/final configuration must never enable the private
        // telemetry readout or the qualification INFO marker.  Qualification
        // builds set both explicitly and are NONRELEASE by construction.
        if (!QUALIFICATION_NONRELEASE && QUAL_INFO_MARKER != 8'h0f)
            $fatal(1, "final INFO marker must be 0x0f");
        if (QUALIFICATION_NONRELEASE && QUAL_INFO_MARKER != 8'h71)
            $fatal(1, "qualification INFO marker must be 0x71");
    end
`endif
endmodule

`default_nettype wire
