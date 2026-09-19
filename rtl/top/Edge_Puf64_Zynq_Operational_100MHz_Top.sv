`timescale 1ns / 1ps
`default_nettype none

// I4 preservation/bridge shell for the Zynq-7020 board.  This is not a final
// operational release image: its public build token is not a device-trusted
// KCV anchor and the separate provisioning phase must replace it.
module Edge_Puf64_Zynq_Operational_100MHz_Top #(
    parameter integer UART_CLKS_PER_BIT = 868,
    parameter integer RX_TIMEOUT_BITS = 1024
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
    // Public, deliberately non-device-specific build token.  Keeping VALID=1
    // prevents synthesis from proving the complete PUF path unreachable.  The
    // image remains a non-programmable preservation harness until I5 replaces
    // this token with the provisioned device KCV.
    localparam [223:0] PRESERVATION_ANCHOR =
        224'h49345f505245534552564154494f4e5f4841524e4553535f4f4e4c59;

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

    // I4 placeholder: operational and non-diagnostic, but not a trusted device
    // anchor. I5 replaces only these ROM constants after preservation passes.
    edge_kcv_anchor #(
        .DIAGNOSTIC(DIAGNOSTIC_ANCHOR),
        .ROM_REF(PRESERVATION_ANCHOR),
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

    (* KEEP_HIERARCHY = "yes" *) edge_puf64_operational_uart #(
        .UART_CLKS_PER_BIT(UART_CLKS_PER_BIT),
        .RX_TIMEOUT(RX_TIMEOUT_BITS * UART_CLKS_PER_BIT)
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
            $fatal(1, "I4 operational lifecycle controls are not locked off");
    end
`endif
endmodule

`default_nettype wire
