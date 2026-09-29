#!/usr/bin/env python3
"""R2 macro-V2 fail-closed fingerprint comparator.

Same semantics as the I4 comparator (prefix-strip only, any physical delta
is a mismatch), for R2_MACRO_FINGERPRINT_V1 files covering CELL (incl. 1152
LUT1) / TAP / RIPPLE / qroute / pin-map / clock class.

Usage:
    python3 scripts/compare_puf64_macro_v2_fingerprint.py <ref.tsv> <cand.tsv>
"""
from pathlib import Path
import sys

HEADER = "R2_MACRO_FINGERPRINT_V1"


def load(path: Path) -> list[str]:
    lines = path.read_text(encoding="utf-8").splitlines()
    lines = [ln.rstrip("\n") for ln in lines if ln.strip() != ""]
    if not lines or lines[0] != HEADER:
        print(f"R2_MACRO_FINGERPRINT_MISMATCH\nreason: bad header in {path}",
              file=sys.stderr)
        raise SystemExit(2)
    return sorted(lines[2:])


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: compare_puf64_macro_v2_fingerprint.py <ref.tsv> <cand.tsv>",
              file=sys.stderr)
        return 2
    ref_p, cand_p = Path(sys.argv[1]), Path(sys.argv[2])
    if not ref_p.is_file() or not cand_p.is_file():
        print("R2_MACRO_FINGERPRINT_MISMATCH\nreason: missing fingerprint file",
              file=sys.stderr)
        return 1
    ref = load(ref_p)
    cand = load(cand_p)
    if ref == cand:
        print("R2_MACRO_FINGERPRINT_MATCH")
        print(f"lines={len(ref)}")
        return 0
    gs, cs = set(ref), set(cand)
    print("R2_MACRO_FINGERPRINT_MISMATCH", file=sys.stderr)
    print(f"ref_lines={len(ref)} candidate_lines={len(cand)}", file=sys.stderr)
    print(f"only_in_ref={len(gs - cs)} only_in_candidate={len(cs - gs)}", file=sys.stderr)
    for ln in sorted(gs - cs)[:10]:
        print(f"REF_ONLY: {ln}", file=sys.stderr)
    for ln in sorted(cs - gs)[:10]:
        print(f"CANDIDATE_ONLY: {ln}", file=sys.stderr)
    print("action: STOP -- do not program board; do not claim mapping qualified.",
          file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
