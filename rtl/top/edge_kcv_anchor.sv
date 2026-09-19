`timescale 1ns / 1ps
`default_nettype none

// Trusted KCV reference anchor (docs/PUF64_KCV_TRUST_ANCHOR_AUDIT.md).
//
// The KCV is a public verifier, not a secret: this module only decides which
// public reference is trusted.  It has no UART/MMIO write path in operational
// mode:
//
//   DIAGNOSTIC=0 : trusted_kcv_ref/valid come from build-time ROM constants
//                  (device provisioning artifact).  Reset/zeroize cannot
//                  clear or bypass a ROM anchor, and provision is ignored.
//   DIAGNOSTIC=1 : one-shot provisioning latch for manufacturing/enrollment.
//                  It locks after the first provision and is cleared only by
//                  the power-on reset (rst_n), never by transaction zeroize,
//                  so a provisioned anchor survives the normal session scrub.
//                  Diagnostic images must never be shipped as operational.
//
// A missing/invalid anchor is fail-closed: consumers must treat
// trusted_kcv_valid=0 as "no same-root decision possible".
module edge_kcv_anchor #(
    parameter bit     DIAGNOSTIC = 1'b0,
    parameter [223:0] ROM_REF    = 224'd0,
    parameter bit     ROM_VALID  = 1'b0
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         zeroize,   // kept for interface parity; never clears
    // Diagnostic provisioning only; ignored when DIAGNOSTIC=0.
    input  wire         provision,
    input  wire [223:0] provision_ref,
    input  wire         provision_valid,
    output wire [223:0] trusted_kcv_ref,
    output wire         trusted_kcv_valid,
    output wire         anchor_locked,
    output wire         anchor_diagnostic
);
    reg [223:0] diag_ref;
    reg         diag_valid;
    reg         diag_locked;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            diag_ref    <= 224'd0;
            diag_valid  <= 1'b0;
            diag_locked <= 1'b0;
        end else if (DIAGNOSTIC && provision && provision_valid && !diag_locked) begin
            diag_ref    <= provision_ref;
            diag_valid  <= 1'b1;
            diag_locked <= 1'b1;
        end
    end

    assign trusted_kcv_ref   = DIAGNOSTIC ? diag_ref  : ROM_REF;
    assign trusted_kcv_valid = DIAGNOSTIC ? diag_valid : ROM_VALID;
    assign anchor_locked     = DIAGNOSTIC ? diag_locked : 1'b1;
    assign anchor_diagnostic = DIAGNOSTIC;

`ifndef SYNTHESIS
    initial begin
        if (!DIAGNOSTIC && ROM_VALID && ROM_REF == 224'd0)
            $error("edge_kcv_anchor: ROM_VALID=1 with a zero reference");
        if (!DIAGNOSTIC && provision_valid)
            $error("edge_kcv_anchor: operational anchor has a provision path");
    end
`endif
endmodule

`default_nettype wire
