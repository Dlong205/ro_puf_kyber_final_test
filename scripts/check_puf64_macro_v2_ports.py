#!/usr/bin/env python3
"""R1 fail-closed gate: wrapper, black-box stub and bench V2 must agree.

Checks:
- kp_puf64_macro_v2.sv vs kp_puf64_macro_v2_bb.sv: identical parameter and
  port declaration lines (order-sensitive).
- puf64_ro_bench_v2.sv instantiates only kp_ripple_counter_v2 (never v1) and
  the same kp_ro_cell wrapper as v1.
- kp_ripple_counter_v2.sv contains exactly STAGES+1=18 explicit LUT1 per
  counter template (1 prescaler + STAGES stage inverters), INIT 2'h1,
  DONT_TOUCH, and no bare `~qq`/`~presc_q` assigns.
- No V2 file references the golden v1 bench/counter modules.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
WRAP = ROOT / "rtl/puf/kp_puf64_macro_v2.sv"
STUB = ROOT / "rtl/puf/kp_puf64_macro_v2_bb.sv"
BENCH = ROOT / "rtl/puf/puf64_ro_bench_v2.sv"
CTR = ROOT / "rtl/puf/kp_ripple_counter_v2.sv"
V1BENCH = ROOT / "rtl/debug/puf64_ro_bench.sv"

ERRORS: list[str] = []


def port_lines(path: Path) -> list[str]:
    lines = []
    for ln in path.read_text(encoding="utf-8").splitlines():
        s = ln.strip()
        if re.match(r"^(parameter\b|input\b|output\b|inout\b)", s):
            lines.append(re.sub(r"\s+", " ", s))
    return lines


def main() -> int:
    w, s = port_lines(WRAP), port_lines(STUB)
    if w != s:
        ERRORS.append(f"wrapper/stub port mismatch: {len(w)} vs {len(s)} lines")
        for a, b in zip(w, s):
            if a != b:
                ERRORS.append(f"  wrap: {a}")
                ERRORS.append(f"  stub: {b}")
                break
    if "(* black_box *)" not in STUB.read_text(encoding="utf-8"):
        ERRORS.append("stub missing (* black_box *)")
    if "u_bench" in STUB.read_text(encoding="utf-8"):
        ERRORS.append("stub must be empty (no instance)")

    bench = BENCH.read_text(encoding="utf-8")
    if "kp_ripple_counter_v2" not in bench:
        ERRORS.append("bench v2 does not instantiate kp_ripple_counter_v2")
    hits = re.findall(r"kp_ripple_counter(_v2)?\s*#\(", bench)
    if not hits or any(h != "_v2" for h in hits):
        ERRORS.append("bench v2 must instantiate only kp_ripple_counter_v2")
    if "kp_ro_cell #(" not in bench:
        ERRORS.append("bench v2 must use the same kp_ro_cell wrapper as v1")
    v1body = V1BENCH.read_text(encoding="utf-8").split("module puf64_ro_bench", 1)[1]
    v2body = bench.split("module puf64_ro_bench_v2", 1)[1]
    norm = lambda t: re.sub(r"\s+", " ", t).replace(
        "kp_ripple_counter_v2", "kp_ripple_counter")
    if norm(v1body) != norm(v2body):
        ERRORS.append("bench v2 body differs from v1 beyond the v2 rename")

    ctr = CTR.read_text(encoding="utf-8")
    lut1 = re.findall(r"LUT1\s*#\(\s*\.INIT\(2'h1\)\s*\)", ctr)
    if len(lut1) != 2:
        ERRORS.append(f"counter v2 must template exactly 2 LUT1 (presc+stage), found {len(lut1)}")
    if ctr.count("DONT_TOUCH") < 3:
        ERRORS.append("counter v2 must DONT_TOUCH presc FDCE + stage FDCE + LUT1s")
    if re.search(r"~\s*(presc_q|qq\[)", ctr):
        ERRORS.append("counter v2 must not use bare ~ assigns (must be explicit LUT1)")
    if "kp_ripple_counter " in ctr or "puf64_ro_bench " in ctr:
        ERRORS.append("counter v2 references golden modules")

    if ERRORS:
        print("R1_MACRO_V2_PORT_AUDIT_FAIL", file=sys.stderr)
        for e in ERRORS:
            print(f"- {e}", file=sys.stderr)
        return 1
    print("R1_MACRO_V2_PORT_AUDIT_PASS")
    print(f"ports={len(w)} lut1_templates=2")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
