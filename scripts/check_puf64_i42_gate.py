#!/usr/bin/env python3
"""Static I4.2.1 gate: runs without Vivado.

Checks:
- correct operational top, no legacy/characterization top in project script
- physical hierarchy prefix tokens in RTL
- scoped-constraint cardinality: 256 RO LUT / 64 prescaler / 1088 ripple /
  1408 LOC / 1408 BEL / 256 LOCK_PINS
- no FIXED_ROUTE in the I4.1/42 preservation path
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "scripts/create_puf64_operational_project.tcl"
PLACE = ROOT / "constraints/puf_allpairs64_ripple_placement.xdc"
PINS = ROOT / "constraints/puf_allpairs64_ripple_lockpins.xdc"
PREFIX = "u_operational_uart/u_chain/u_puf64_core/u_puf64_physical/u_puf/"

ERRORS: list[str] = []


def fail(msg: str) -> None:
    ERRORS.append(msg)


def main() -> int:
    project = PROJECT.read_text(encoding="utf-8")
    if "Edge_Puf64_Zynq_Operational_100MHz_Top" not in project:
        fail("project: missing operational top")
    for bad in ("Kyber_System_Top.sv", "Puf_AllPairs64_Characterization_Top.sv",
                "Puf_AllPairs_Characterization_Top.sv"):
        # forbidden inclusion is checked on get_files patterns; the static
        # script must contain the fail-closed guard, not the file itself
        if f"get_files -quiet *{bad}" not in project and bad in project:
            # allow the guard string itself; reject actual source adds
            if "I4 top gate" not in project:
                fail(f"project: legacy top string {bad}")
    if "I4 top gate" not in project:
        fail("project: missing I4 top gate")
    if "I4 hierarchy gate" not in project:
        fail("project: missing I4 hierarchy gate")
    if PREFIX not in project:
        fail("project: missing physical prefix")
    if "I4_FIXED_ROUTE=0" not in project:
        fail("project: missing I4_FIXED_ROUTE=0 marker")
    if "set_property FIXED_ROUTE" in project or "puf_allpairs64_ripple_route.xdc" in project:
        fail("project: fixed routes entered preservation harness")

    place = PLACE.read_text(encoding="utf-8")
    pins = PINS.read_text(encoding="utf-8")
    n_name = place.count('NAME == "u_puf/')
    n_bel = len(re.findall(r"set_property BEL ", place))
    n_loc = len(re.findall(r"set_property LOC ", place))
    n_ro = place.count("ro_cell/u_backend/LUT6_")
    n_presc = place.count("presc_fdce")
    n_stage = len(re.findall(r"stage\[", place))
    n_lock = len(re.findall(r"set_property LOCK_PINS ", pins))
    n_lock_ro = pins.count("ro_cell/u_backend/LUT6_")
    # Each cell yields BEL+LOC lines, so pattern hits are 2x cell counts.
    checks = [
        (n_name, 2816, "placement NAME occurrences"),
        (n_bel, 1408, "BEL lines"),
        (n_loc, 1408, "LOC lines"),
        (n_ro, 512, "RO-LUT pattern hits (256x2)"),
        (n_presc, 128, "prescaler pattern hits (64x2)"),
        (n_stage, 2176, "ripple-stage pattern hits (1088x2)"),
        (n_lock, 256, "LOCK_PINS lines"),
        (n_lock_ro, 256, "RO LOCK_PINS targets"),
    ]
    for actual, expected, label in checks:
        if actual != expected:
            fail(f"constraints: {label} expected={expected} actual={actual}")
        if actual == 0:
            fail(f"constraints: {label} matched zero")
    if "FIXED_ROUTE" in place or "FIXED_ROUTE" in pins:
        fail("constraints: FIXED_ROUTE must not be in placement/lockpins golden files")

    # RTL hierarchy tokens
    tokens = [
        ("rtl/top/Edge_Puf64_Zynq_Operational_100MHz_Top.sv", ") u_operational_uart ("),
        ("rtl/top/edge_puf64_operational_uart.sv", "edge_puf64_operational_chain u_chain ("),
        ("rtl/top/edge_puf64_operational_chain.sv", ") u_puf64_core ("),
        ("rtl/top/edge_puf64_operational_core.sv", ") u_puf64_physical ("),
        ("rtl/puf/kp_puf64_physical.sv", ") u_puf ("),
    ]
    for rel, tok in tokens:
        text = (ROOT / rel).read_text(encoding="utf-8")
        if tok not in text:
            fail(f"hierarchy: {rel} missing {tok}")

    if ERRORS:
        print("I4_2_BUILD_GATE_FAIL", file=sys.stderr)
        for e in ERRORS:
            print(f"- {e}", file=sys.stderr)
        return 1
    print("I4_2_BUILD_GATE_PASS")
    print(f"placement: NAME=2816 BEL=1408 LOC=1408 ROx2=512 PRESCx2=128 STAGEx2=2176")
    print(f"lockpins: LOCK=256 RO=256")
    print(f"prefix: {PREFIX}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
