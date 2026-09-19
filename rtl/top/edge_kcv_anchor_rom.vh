// Device KCV anchor ROM template (tracked default = fail-closed).
//
// The KCV is a public verifier, not a secret.  A per-device provisioning run
// (host/puf64_provision_kcv_anchor.py --emit) replaces this file locally with
// the 224-bit KCV captured from the diagnostic enrollment of the exact
// physical PUF implementation.  That generated file is device-specific; do not
// commit it to a public repository if the KCV is treated as a device
// identifier.
//
// Default: ROM_VALID=0 -> every reconstruction fails closed.
localparam [223:0] EDGE_KCV_ROM_REF   = 224'h0;
localparam         EDGE_KCV_ROM_VALID = 1'b0;
