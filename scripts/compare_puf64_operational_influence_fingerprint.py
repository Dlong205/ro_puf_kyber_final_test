#!/usr/bin/env python3
"""R6.1/R6.2 OPERATIONAL_INFLUENCE_FINGERPRINT_V1 comparator (fail-closed).

Modes:
  ab      exact match on every compared line (R6.2 A/B reproducibility).
          Identity line 2 (IDS dcp_sha=...) is informational and skipped.
  bridge  TIER-0 sections must match exactly
          (MCELL/MNET/BOUND/CLK/TELOAD/SRC + headers);
          TIER-1 sections (SCHED/SNIFF/NEIGH) and GEN are reported as diff
          statistics only (expected: readout trim + placement freedom across
          different generic sets; the final confirmation campaign is binding).

No hierarchy stripping is performed: full hierarchical names compare exactly.
A single leading top token may be rewritten with --top-alias OLD=NEW (used
only when the two images genuinely have different tops; qual and final share
one top so A/B and qual/final-bridge normally need no alias).

Exit 0: gate PASS.  Exit 1: mismatch (ab: R6_OPERATIONAL_ENVIRONMENT_... ;
in ab mode any mismatch means NOT_REPRODUCIBLE -> stop, no board campaign).
Exit 2: usage/file error.
"""
from pathlib import Path
import argparse
import sys

HEADER = "OPERATIONAL_INFLUENCE_FINGERPRINT_V1"
TIER0_PREFIXES = ("MCELL\t", "MNET\t", "MNET_COUNT\t", "BOUND\t",
                  "BOUND_RESPONSE_UNCONNECTED_PINS\t", "BOUND_COUNT\t",
                  "CLK\t", "TELOAD\t", "SRC\t", "TOP\t", "MACRO_PREFIX\t",
                  "NEIGH_BOX\t")
TIER1_PREFIXES = ("SCHED\t", "SCHED_COUNT\t", "SNIFF\t", "SNIFF_COUNT\t",
                  "NEIGH\t", "NEIGH_COUNT\t", "GEN\t")


def load(path: Path):
    lines = [ln.rstrip("\n") for ln in path.read_text(encoding="utf-8").splitlines()
             if ln.strip() != ""]
    if not lines or lines[0] != HEADER:
        print(f"R6_INFLUENCE_FINGERPRINT_MISMATCH\nreason: bad header in {path}",
              file=sys.stderr)
        raise SystemExit(2)
    # Line 2 (IDS dcp_sha) is identity-only: timestamps make DCP SHAs differ
    # between logically identical builds; everything else compares.
    body = [ln for ln in lines[1:] if not ln.startswith("IDS\t")]
    # Drop the exporter trailer (informational, not compared).
    body = [ln for ln in body if ln != "R6_INFLUENCE_EXPORT_DONE"]
    return body


def apply_alias(lines: list[str], alias: str | None) -> list[str]:
    if not alias:
        return lines
    old, _, new = alias.partition("=")
    if not old or not new:
        print("R6_INFLUENCE_FINGERPRINT_MISMATCH\nreason: bad --top-alias",
              file=sys.stderr)
        raise SystemExit(2)
    out = []
    for ln in lines:
        # Rewrite only a single leading top token (old/ -> new/), never
        # internal relative paths: hierarchy deltas must stay visible.
        parts = ln.split("\t")
        changed = False
        for i, p in enumerate(parts):
            for tok in p.split(","):
                if tok == old or tok.startswith(old + "/"):
                    p = p.replace(old + "/", new + "/", 1) if tok.startswith(old + "/") \
                        else (new if tok == old else p)
                    changed = True
            parts[i] = p
        out.append("\t".join(parts) if changed else ln)
    return out


def section_of(line: str) -> str:
    for prefix in TIER0_PREFIXES:
        if line.startswith(prefix):
            return "TIER0"
    for prefix in TIER1_PREFIXES:
        if line.startswith(prefix):
            return "TIER1"
    return "OTHER"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("golden")
    ap.add_argument("candidate")
    ap.add_argument("--mode", choices=("ab", "bridge"), default="ab")
    ap.add_argument("--top-alias", default=None)
    args = ap.parse_args()
    gp, cp = Path(args.golden), Path(args.candidate)
    if not gp.is_file() or not cp.is_file():
        print("R6_INFLUENCE_FINGERPRINT_MISMATCH\nreason: missing file",
              file=sys.stderr)
        return 2
    g = sorted(apply_alias(load(gp), args.top_alias))
    c = sorted(apply_alias(load(cp), args.top_alias))
    if args.mode == "ab":
        if g == c:
            print("R6_OPERATIONAL_INFLUENCE_MATCH")
            print(f"lines={len(g)}")
            return 0
        gs, cs = set(g), set(c)
        print("R6_OPERATIONAL_ENVIRONMENT_NOT_REPRODUCIBLE", file=sys.stderr)
        print(f"golden_lines={len(g)} candidate_lines={len(c)}", file=sys.stderr)
        print(f"only_in_golden={len(gs - cs)} only_in_candidate={len(cs - gs)}",
              file=sys.stderr)
        for ln in sorted(gs - cs)[:15]:
            print(f"GOLDEN_ONLY: {ln}", file=sys.stderr)
        for ln in sorted(cs - gs)[:15]:
            print(f"CANDIDATE_ONLY: {ln}", file=sys.stderr)
        print("action: STOP - no board campaign; no train/holdout.",
              file=sys.stderr)
        return 1
    # bridge mode
    g0 = sorted(ln for ln in g if section_of(ln) == "TIER0")
    c0 = sorted(ln for ln in c if section_of(ln) == "TIER0")
    g1 = sorted(ln for ln in g if section_of(ln) == "TIER1")
    c1 = sorted(ln for ln in c if section_of(ln) == "TIER1")
    ok = (g0 == c0)
    gs0, cs0 = set(g0), set(c0)
    gs1, cs1 = set(g1), set(c1)
    print(f"TIER0 lines={len(g0)} match={ok} "
          f"only_in_golden={len(gs0 - cs0)} only_in_candidate={len(cs0 - gs0)}")
    print(f"TIER1 lines golden={len(g1)} candidate={len(c1)} "
          f"only_in_golden={len(gs1 - cs1)} only_in_candidate={len(cs1 - gs1)} "
          f"(reported, not gating)")
    if not ok:
        print("R6_INFLUENCE_BRIDGE_TIER0_MISMATCH", file=sys.stderr)
        for ln in sorted(gs0 - cs0)[:15]:
            print(f"TIER0_GOLDEN_ONLY: {ln}", file=sys.stderr)
        for ln in sorted(cs0 - gs0)[:15]:
            print(f"TIER0_CANDIDATE_ONLY: {ln}", file=sys.stderr)
        return 1
    print("R6_INFLUENCE_BRIDGE_TIER0_MATCH")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
