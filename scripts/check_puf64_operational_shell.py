#!/usr/bin/env python3
"""Static fail-closed audit for the I4.1 operational preservation shell."""

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
TOP = ROOT / "rtl/top/Edge_Puf64_Zynq_Operational_100MHz_Top.sv"
PROJECT = ROOT / "scripts/create_puf64_operational_project.tcl"
CHAR_TOP = ROOT / "rtl/top/Puf_AllPairs64_Characterization_Top.sv"
LEGACY_TOP = ROOT / "rtl/top/Kyber_System_Top.sv"


def require(text: str, tokens: list[str], label: str, errors: list[str]) -> None:
    for token in tokens:
        if token not in text:
            errors.append(f"{label}: missing {token}")


def main() -> int:
    errors: list[str] = []
    top = TOP.read_text(encoding="utf-8")
    project = PROJECT.read_text(encoding="utf-8")
    require(top, [
        "module Edge_Puf64_Zynq_Operational_100MHz_Top",
        "localparam bit ALLOW_ENROLL         = 1'b0;",
        "localparam bit LEGACY_HELPER_ENABLE = 1'b0;",
        "localparam bit DIAGNOSTIC_ANCHOR    = 1'b0;",
        ".DIAGNOSTIC(DIAGNOSTIC_ANCHOR)",
        ".ROM_REF(PRESERVATION_ANCHOR)",
        ".ROM_VALID(1'b1)",
        "224'h49345f505245534552564154494f4e5f4841524e4553535f4f4e4c59",
        ".provision(1'b0)",
        "edge_puf64_operational_uart",
        ") u_operational_uart (",
        "always @(posedge clk_100)",
    ], "top", errors)
    require(project, [
        "build puf64_operational_preservation",
        "Edge_Puf64_Zynq_Operational_100MHz_Top",
        "puf_allpairs64_ripple_placement.xdc",
        "puf_allpairs64_ripple_lockpins.xdc",
        "I4_FIXED_ROUTE=0",
    ], "project", errors)
    if "puf_allpairs64_ripple_route.xdc" in project or "set_property FIXED_ROUTE" in project:
        errors.append("project: fixed routes entered I4.1 harness")
    if "Kyber_System_Top.sv" in project:
        errors.append("project: legacy top entered isolated source list")
    if "Puf_AllPairs64_Characterization_Top.sv" in project:
        errors.append("project: characterization top entered isolated source list")
    if not CHAR_TOP.is_file() or not LEGACY_TOP.is_file():
        errors.append("protected legacy/characterization top is missing")

    if errors:
        print("I4_1_OPERATIONAL_SHELL_AUDIT_FAIL", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    print("I4_1_OPERATIONAL_SHELL_AUDIT_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
