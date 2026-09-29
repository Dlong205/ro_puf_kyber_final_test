#!/usr/bin/env python3
"""R3 identity gate for the macro-V2 characterization image.

Checks (all fail-closed):
- top uses BUILD_ID 3 (never 2), TOPOLOGY_ID 0xC0DE, IMAGE_MODE 0x01,
  PROTO 3.2, macro instance kp_puf64_macro_v2 named u_macro.
- MACRO_SHA256 / FP_SHA256 in the top equal the frozen R2 manifest
  (r2_freeze_manifest.tsv); no zero SHAs.
- project source list contains the V2 top/uart/stub and NO golden bench,
  counter, uart, or characterization top.
- golden characterization sources/bitstreams untouched (existence + hash
  stability is enforced by never writing those paths; this script asserts
  the V2 project references none of them).
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
TOP = ROOT / "rtl/top/Puf64_MacroV2_Characterization_Top.sv"
PROJ = ROOT / "scripts/create_puf64_macrov2_char_project.tcl"
MAN = ROOT / "build/puf64_macro_v2/r2_freeze_manifest.tsv"

ERRORS: list[str] = []


def fail(m: str) -> None:
    ERRORS.append(m)


def main() -> int:
    top = TOP.read_text(encoding="utf-8")
    for tok in ("module Puf64_MacroV2_Characterization_Top",
                "localparam integer BUILD_ID = 16'h0003;",
                ".TOPOLOGY_ID(16'hC0DE)", ".IMAGE_MODE(8'h01)",
                ".PROTO_MAJOR(3), .PROTO_MINOR(2)",
                "kp_puf64_macro_v2 u_macro (",
                "puf_allpairs_uart_v2 #("):
        if tok not in top:
            fail(f"top missing: {tok}")
    if "16'h0002" in top:
        fail("top references golden BUILD_ID 2")
    code = "\n".join(ln.split("//")[0] for ln in top.splitlines())
    if "puf64_ro_bench #(" in code or "Puf_AllPairs64_Characterization_Top" in code:
        fail("top references golden bench/top")
    # Black-box instances must not carry parameter overrides (Vivado binds
    # them against a generated parameter-less stub -> Synth 8-3438).
    if "kp_puf64_macro_v2 #(" in code:
        fail("macro instance must rely on frozen defaults (no #(...) overrides)")

    man = MAN.read_text(encoding="utf-8")
    mm = re.search(r"routed_dcp_sha256\s+([0-9a-f]{64})", man)
    mf = re.search(r"fingerprint_sha256\s+([0-9a-f]{64})", man)
    if not mm or not mf:
        fail("R2 freeze manifest SHAs unreadable")
        return 1
    for label, digest in (("MACRO_SHA256", mm.group(1)), ("FP_SHA256", mf.group(1))):
        if digest == "0" * 64:
            fail(f"manifest {label} is zero")
        if digest.lower() not in top.lower():
            fail(f"top {label} != frozen manifest")

    proj = PROJ.read_text(encoding="utf-8")
    for tok in ("Puf64_MacroV2_Characterization_Top.sv", "puf_allpairs_uart_v2.sv",
                "kp_puf64_macro_v2_bb.sv", "puf64_macrov2_char_zynq7020.xdc"):
        if tok not in proj:
            fail(f"project missing: {tok}")
    for bad in ("Puf_AllPairs64_Characterization_Top.sv", "puf_allpairs_uart.sv",
                "puf64_ro_bench.sv", "kp_ripple_counter.sv",
                "kp_puf64_macro_v2.sv", "puf64_ro_bench_v2.sv",
                "kp_ripple_counter_v2.sv"):
        # The real wrapper/bench/counter must never be synthesized into the
        # importing top (black box only); golden files never enter either.
        # Match decidiu: only flag source-list additions, not comments.
        for ln in proj.splitlines():
            if bad in ln and "file join" in ln:
                fail(f"project adds forbidden source: {bad}")
                break

    if ERRORS:
        print("R3_MACROV2_ID_GATE_FAIL", file=sys.stderr)
        for e in ERRORS:
            print(f"- {e}", file=sys.stderr)
        return 1
    print("R3_MACROV2_ID_GATE_PASS")
    print(f"build_id=3 topology=0xc0de macro={mm.group(1)[:12]}... fp={mf.group(1)[:12]}...")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
