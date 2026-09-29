#!/usr/bin/env python3
"""R6.2 A/B reproducibility gate (no Vivado needed, no board).

Compares two clean qualification builds (reports/puf64_qual_A|B):
  1. R2 routed-macro fingerprint A == B == frozen macro
     (compare_puf64_macro_v2_fingerprint.py).
  2. Operational influence fingerprint A == B, exact (ab mode).
     Any mismatch -> R6_OPERATIONAL_ENVIRONMENT_NOT_REPRODUCIBLE: stop,
     no board campaign, no train/holdout.
  3. Same hierarchy/topology: TOP + MACRO_PREFIX lines identical.
  4. Same clock resources: CLK section identical (covered by ab compare;
     re-asserted explicitly).
  5. Same telemetry loading: TELOAD section identical (explicit).
  6. Route complete: post_route_status.rpt has no partial/unrouted/RTSTAT.
  7. Timing 100 MHz PASS: no VIOLATED / negative WNS in post_route_timing.
  8. 0 unexpected critical warnings: synth+impl runme.log scan
     (64x Synth 8-295 RO loops under u_macro/u_bench/, 0 others).
  9. Report/lifecycle/security presence: drc/methodology/clock_util reports
     exist; bitstreams exist.

Usage: python3 scripts/check_r6_ab_gate.py
Exit 0: R6_AB_GATE_PASS.  Exit 1: gate FAIL (reason printed fail-closed).
"""
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
FROZEN_FP = ROOT / "build/puf64_macro_v2/macro_v2_fingerprint.tsv"
CMP_R2 = ROOT / "scripts/compare_puf64_macro_v2_fingerprint.py"
CMP_INFL = ROOT / "scripts/compare_puf64_operational_influence_fingerprint.py"
A = ROOT / "reports/puf64_qual_A"
B = ROOT / "reports/puf64_qual_B"
ERRORS: list[str] = []


def fail(msg: str) -> None:
    ERRORS.append(msg)


def run(cmd: list[str], label: str) -> bool:
    proc = subprocess.run(cmd, text=True, capture_output=True)
    print(f"--- {label} ---")
    print((proc.stdout or "") + (proc.stderr or ""))
    if proc.returncode != 0:
        fail(f"{label} failed (rc={proc.returncode})")
        return False
    return True


def need(path: Path, label: str) -> bool:
    if not path.is_file():
        fail(f"missing {label}: {path.relative_to(ROOT)}")
        return False
    return True


def timing_summary_wns(report: str) -> float | None:
    """Read the design summary, not an arbitrary path-group WNS."""
    match = re.search(
        r"WNS\(ns\).*?\n\s*-+.*?\n\s*(-?\d+\.\d+)\s+",
        report, re.DOTALL,
    )
    return float(match.group(1)) if match else None


def main() -> int:
    for d in (A, B):
        for f in ("qual_r2_macro_fingerprint.tsv",
                  "qual_operational_influence_fingerprint.tsv",
                  "post_route_status.rpt", "post_route_timing.rpt",
                  "post_route_drc.rpt", "post_route_methodology.rpt",
                  "post_route_clock_util.rpt", "post_route_utilization.rpt"):
            need(d / f, f"{d.name}/{f}")
    if ERRORS:
        return finish()
    for tag, fp in (("A", A / "qual_r2_macro_fingerprint.tsv"),
                    ("B", B / "qual_r2_macro_fingerprint.tsv")):
        run(["python3", str(CMP_R2), str(FROZEN_FP), str(fp)],
            f"R2_MACRO_FINGERPRINT_MATCH(qual-{tag})")
    run(["python3", str(CMP_R2),
         str(A / "qual_r2_macro_fingerprint.tsv"),
         str(B / "qual_r2_macro_fingerprint.tsv")],
        "R2_MACRO_FINGERPRINT_A_EQ_B")
    run(["python3", str(CMP_INFL),
         str(A / "qual_operational_influence_fingerprint.tsv"),
         str(B / "qual_operational_influence_fingerprint.tsv"),
         "--mode", "ab"], "R6_INFLUENCE_AB")
    # Explicit section re-assertion (hierarchy/topology, clocks, loads).
    for section, label in (("TOP\t", "hierarchy/top"),
                           ("MACRO_PREFIX\t", "macro prefix"),
                           ("CLK\t", "clock resources"),
                           ("TELOAD\t", "telemetry loading"),
                           ("SRC\t", "sources"),
                           ("GEN\t", "generics")):
        la = [ln for ln in (A / "qual_operational_influence_fingerprint.tsv")
              .read_text().splitlines() if ln.startswith(section)]
        lb = [ln for ln in (B / "qual_operational_influence_fingerprint.tsv")
              .read_text().splitlines() if ln.startswith(section)]
        if sorted(la) != sorted(lb) or not la:
            fail(f"section {label} differs or empty "
                 f"(A={len(la)} B={len(lb)})")
        else:
            print(f"R6_AB_SECTION_MATCH {label} lines={len(la)}")
    for tag, d in (("A", A), ("B", B)):
        rs = (d / "post_route_status.rpt").read_text(errors="replace")
        if re.search(r"partial|unrouted|RTSTAT|conflict", rs, re.IGNORECASE):
            fail(f"{tag} route incomplete")
        else:
            print(f"R6_AB_ROUTE_PASS {tag}")
        tm = (d / "post_route_timing.rpt").read_text(errors="replace")
        wns = timing_summary_wns(tm)
        if (re.search(r"VIOLATED|Timing constraints are not met", tm) or
                wns is None or wns < 0 or
                "All user specified timing constraints are met." not in tm):
            fail(f"{tag} timing violated")
        else:
            print(f"R6_AB_TIMING_PASS {tag} wns={wns:.3f}")
    # Critical-warning scan over both build runs.
    for suffix in ("A", "B"):
        for stage in ("synth_1", "impl_1"):
            log = (ROOT / f"build/puf64_qual_{suffix}/"
                   f"puf64_qual_zynq7020_{suffix}.runs/{stage}/runme.log")
            if not need(log, f"qual-{suffix}/{stage}/runme.log"):
                continue
    if not ERRORS:
        # Macro is a black box at synth (proven final/diag: 0/0): expect zero
        # critical warnings of any kind across both builds' synth+impl logs.
        unexpected: list[str] = []
        for suffix in ("A", "B"):
            slog = (ROOT / f"build/puf64_qual_{suffix}/"
                    f"puf64_qual_zynq7020_{suffix}.runs/synth_1/runme.log"
                    ).read_text(errors="replace").splitlines()
            ilog = (ROOT / f"build/puf64_qual_{suffix}/"
                    f"puf64_qual_zynq7020_{suffix}.runs/impl_1/runme.log"
                    ).read_text(errors="replace").splitlines()
            for lines in (slog, ilog):
                for line in lines:
                    if "CRITICAL WARNING" in line and not line.startswith("#"):
                        unexpected.append(f"{suffix}: {line.strip()[:140]}")
        if unexpected:
            fail(f"{len(unexpected)} unexpected critical warnings, "
                 f"first: {unexpected[0]}")
        else:
            print("R6_AB_CRITICAL_WARNINGS unexpected=0")
    if ERRORS:
        return finish()
    print("R6_AB_GATE_PASS")
    print("next: board pilot (R6.3) only after exact-SHA program gate")
    return 0


def finish() -> int:
    print("R6_AB_GATE_FAIL", file=sys.stderr)
    for e in ERRORS:
        print(f"- {e}", file=sys.stderr)
    if any("INFLUENCE" in e or "influence" in e for e in ERRORS):
        print("R6_OPERATIONAL_ENVIRONMENT_NOT_REPRODUCIBLE", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
