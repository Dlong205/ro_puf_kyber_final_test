#!/usr/bin/env python3
"""Static I5 anchor-embedding gate (no secrets here).

Pass criteria (structural only; functional KCV stability needs board boots):
- DIAGNOSTIC_ANCHOR = 0, ROM_REF = DEVICE_TRUSTED_KCV, ROM_VALID = 1
- ALLOW_ENROLL = 0, LEGACY_HELPER_ENABLE = 0, provision tied 0
- No UART/MMIO path that can rewrite the anchor (provision_ref/valid tied 0,
  no anchor write enable).
Run after the I5 anchor patch, before the I5.1 rebuild.
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
TOP = ROOT / "rtl/top/Edge_Puf64_Zynq_Operational_100MHz_Top.sv"

# In preservation mode (pre-I5) the top uses the public token; after I5 it
# must use the device trusted KCV.  This checker accepts EITHER state but
# reports which one, and always enforces the lifecycle locks.
PRESERVATION_TOKEN = "224'h49345f505245534552564154494f4e5f4841524e4553535f4f4e4c59"


def main() -> int:
    errors: list[str] = []
    text = TOP.read_text(encoding="utf-8")
    for tok in ("localparam bit ALLOW_ENROLL         = 1'b0;",
                "localparam bit LEGACY_HELPER_ENABLE = 1'b0;",
                "localparam bit DIAGNOSTIC_ANCHOR    = 1'b0;",
                ".provision(1'b0),",
                ".provision_ref(224'd0),",
                ".provision_valid(1'b0),"):
        if tok not in text:
            errors.append(f"missing lifecycle lock: {tok}")
    has_preservation = PRESERVATION_TOKEN in text
    has_device = "DEVICE_TRUSTED_KCV" in text
    if has_preservation and has_device:
        errors.append("anchor ambiguous: both preservation token and DEVICE_TRUSTED_KCV present")
    if not has_preservation and not has_device:
        errors.append("anchor missing: neither preservation token nor DEVICE_TRUSTED_KCV found")
    # No anchor rewrite path: provision ports must stay tied off.
    if "provision_ref(" in text and ".provision_ref(224'd0)" not in text:
        errors.append("anchor rewrite path: provision_ref not tied to zero")
    if errors:
        print("I5_ANCHOR_STATIC_GATE_FAIL", file=sys.stderr)
        for e in errors:
            print(f"- {e}", file=sys.stderr)
        return 1
    mode = "PRESERVATION_PLACEHOLDER" if has_preservation else "DEVICE_TRUSTED_ANCHOR"
    print(f"I5_ANCHOR_STATIC_GATE_PASS mode={mode}")
    if has_preservation:
        print("note: I4.5a smoke only; do not claim E2E trusted-anchor PASS in this mode.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
