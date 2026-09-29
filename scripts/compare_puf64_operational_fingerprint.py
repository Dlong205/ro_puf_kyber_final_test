#!/usr/bin/env python3
"""I4.2.4 / I5.1 fail-closed fingerprint comparator.

Only the hierarchy prefix is stripped (exporters already emit relative
ro[...]/... paths).  Any difference in REF_NAME, INIT, LOC, BEL, LOCK_PINS,
pin-map or internal routes is I4_PHYSICAL_FINGERPRINT_MISMATCH: the candidate
must stop, must not be programmed, and KCV pass must never override it.

Usage:
    python3 scripts/compare_puf64_operational_fingerprint.py <golden.tsv> <candidate.tsv>
"""
from pathlib import Path
import sys

HEADER = "I4_EXPANDED_FINGERPRINT_V1"


def load(path: Path) -> list[str]:
    lines = path.read_text(encoding="utf-8").splitlines()
    lines = [ln.rstrip("\n") for ln in lines if ln.strip() != ""]
    if not lines or lines[0] != HEADER:
        print(f"I4_PHYSICAL_FINGERPRINT_MISMATCH\nreason: bad header in {path}",
              file=sys.stderr)
        raise SystemExit(2)
    # Line 2 is the DCP SHA (GOLDEN_ or CANDIDATE_); line 3 is SUMMARY.
    # Both are informational; the comparison covers lines 3..end so a SHA
    # rotation alone cannot mask a physical change, while identical physical
    # content with different SHA labels still compares on physics.
    body = []
    for ln in lines[2:]:
        body.append(ln)
    return sorted(body)


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: compare_puf64_operational_fingerprint.py <golden.tsv> <candidate.tsv>",
              file=sys.stderr)
        return 2
    golden_p, cand_p = Path(sys.argv[1]), Path(sys.argv[2])
    if not golden_p.is_file() or not cand_p.is_file():
        print("I4_PHYSICAL_FINGERPRINT_MISMATCH\nreason: missing fingerprint file",
              file=sys.stderr)
        return 1
    golden = load(golden_p)
    cand = load(cand_p)
    if golden == cand:
        print("I4_PHYSICAL_FINGERPRINT_MATCH")
        print(f"lines={len(golden)}")
        return 0
    gs, cs = set(golden), set(cand)
    print("I4_PHYSICAL_FINGERPRINT_MISMATCH", file=sys.stderr)
    print(f"golden_lines={len(golden)} candidate_lines={len(cand)}", file=sys.stderr)
    print(f"only_in_golden={len(gs - cs)} only_in_candidate={len(cs - gs)}", file=sys.stderr)
    for ln in sorted(gs - cs)[:10]:
        print(f"GOLDEN_ONLY: {ln}", file=sys.stderr)
    for ln in sorted(cs - gs)[:10]:
        print(f"CANDIDATE_ONLY: {ln}", file=sys.stderr)
    print("action: STOP — do not program board; do not claim mapping qualified;",
          file=sys.stderr)
    print("action: KCV pass must not override this mismatch.", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
