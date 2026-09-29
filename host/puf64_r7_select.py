#!/usr/bin/env python3
"""R7 selector: final-path train data -> deterministic 264-pair mapping.

Methodology mirrors puf64_train_select v1 (per-boot consensus weighting,
strict eligibility, greedy degree-balanced selection), but reads the R7
frozen input (final-path frames) instead of the V2 campaign format.
No holdout data is touched. A second run must reproduce the selection SHA.
"""
import argparse
import hashlib
import json
import statistics
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CAMPAIGN = ROOT / "reports/puf64_finalchar_campaign"
FREEZE = CAMPAIGN / "r7_train_input_703_723.frozen.json"

SELECT_COUNT = 264
DEGREE_LOW = 8
DEGREE_HIGH = 9
MAPPING_TAG = 0x81B7  # R7 final-path mapping (gen1 family, new environment)


def canonical_json(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def load_boot_frames(boot_dir: Path):
    out = []
    for fp in sorted(boot_dir.glob("frame_*.json")):
        out.append(json.loads(fp.read_text()))
    return out


def boot_aggregate(frames):
    """Per-pair consensus/minority/ties/margins within one boot."""
    per_pair = {}
    for pair_idx in range(2016):
        a = frames[0]["pairs"][pair_idx]["a"]
        b = frames[0]["pairs"][pair_idx]["b"]
        winners = [f["pairs"][pair_idx]["winner"] for f in frames]
        margins = [abs(f["pairs"][pair_idx]["c0"] - f["pairs"][pair_idx]["c1"])
                   for f in frames]
        ties = sum(1 for f in frames if f["pairs"][pair_idx]["tie"])
        ones = sum(winners)
        n = len(frames)
        ref = 1 if ones * 2 > n else (0 if ones * 2 < n else None)
        minority = (min(ones, n - ones) / n) if ref is not None else 0.5
        margins_sorted = sorted(margins)
        per_pair[pair_idx] = {
            "pair": [a, b], "boot_winner": ref, "minority": minority,
            "ties": ties, "min_margin": margins_sorted[0],
            "median_margin": statistics.median(margins_sorted),
        }
    return per_pair


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--min-margin", type=float, default=9.0)
    ap.add_argument("--mapping-out", type=Path,
                    default=CAMPAIGN / "r7_mapping_candidate.json")
    ap.add_argument("--reference-out", type=Path,
                    default=CAMPAIGN / "r7_reference_private.json")
    ap.add_argument("--report-out", type=Path,
                    default=CAMPAIGN / "r7_selection_report.json")
    args = ap.parse_args()

    freeze = json.loads(FREEZE.read_text())
    boot_aggs = []
    for boot in freeze["boots"]:
        frames = load_boot_frames(CAMPAIGN / boot["dir"])
        boot_aggs.append(boot_aggregate(frames))
    n_boots = len(boot_aggs)

    metrics = []
    for pair_idx in range(2016):
        votes = [agg[pair_idx]["boot_winner"] for agg in boot_aggs]
        if any(v is None for v in votes):
            continue
        ones = sum(votes)
        ref = 1 if ones > n_boots / 2 else 0
        changed = sum(1 for v in votes if v != ref)
        minorities = [agg[pair_idx]["minority"] for agg in boot_aggs]
        margins = [agg[pair_idx]["min_margin"] for agg in boot_aggs]
        medians = [agg[pair_idx]["median_margin"] for agg in boot_aggs]
        ties = sum(agg[pair_idx]["ties"] for agg in boot_aggs)
        a, b = boot_aggs[0][pair_idx]["pair"]
        metrics.append({
            "pair": [a, b], "reference_bit": ref,
            "changed_boot_count": changed,
            "worst_minority_rate": max(minorities),
            "tie_events": ties,
            "min_margin": min(margins),
            "median_margin": statistics.median(medians),
        })

    eligible = [m for m in metrics
                if m["changed_boot_count"] == 0
                and m["worst_minority_rate"] == 0.0
                and m["tie_events"] == 0
                and m["min_margin"] >= args.min_margin]
    print(f"R7 eligible: {len(eligible)}/2016 at min_margin>={args.min_margin}")
    if len(eligible) < SELECT_COUNT:
        print(f"R7_SELECT_BLOCKER: only {len(eligible)} eligible", file=sys.stderr)
        return 2

    eligible.sort(key=lambda m: (-m["min_margin"], m["pair"][0], m["pair"][1]))
    degree = [0] * 64
    selected, remaining = [], list(eligible)
    while remaining and len(selected) < SELECT_COUNT:
        feasible = [m for m in remaining
                    if degree[m["pair"][0]] < DEGREE_HIGH
                    and degree[m["pair"][1]] < DEGREE_HIGH]
        if not feasible:
            break
        best = min(feasible, key=lambda m: (
            max(degree[m["pair"][0]], degree[m["pair"][1]]),
            degree[m["pair"][0]] + degree[m["pair"][1]],
            -m["min_margin"], m["pair"][0], m["pair"][1]))
        remaining.remove(best)
        selected.append(best)
        degree[best["pair"][0]] += 1
        degree[best["pair"][1]] += 1
    if len(selected) < SELECT_COUNT:
        print(f"R7_SELECT_BLOCKER: {len(selected)}/{SELECT_COUNT}", file=sys.stderr)
        return 2
    if min(degree) < DEGREE_LOW or max(degree) > DEGREE_HIGH:
        print(f"R7_SELECT_BLOCKER: degree min={min(degree)} max={max(degree)}",
              file=sys.stderr)
        return 2

    ordered_pairs = [m["pair"] for m in selected]
    reference_bits = [m["reference_bit"] for m in selected]
    selection_sha = hashlib.sha256(canonical_json({
        "freeze": freeze["aggregate_sha256"],
        "tag": MAPPING_TAG,
        "pairs": ordered_pairs,
        "min_margin": args.min_margin})).hexdigest()
    mapping = {"schema": "r7-mapping-candidate-v1",
               "mapping_tag": f"0x{MAPPING_TAG:04X}",
               "mapping_tag_int": MAPPING_TAG,
               "pairs": ordered_pairs,
               "selection_sha256": selection_sha,
               "train_freeze_sha256": freeze["aggregate_sha256"],
               "degree": degree,
               "min_margin_threshold": args.min_margin,
               "status": "CANDIDATE_NOT_FROZEN"}
    reference = {"schema": "r7-reference-private-v1",
                 "mapping_tag": f"0x{MAPPING_TAG:04X}",
                 "reference_bits": reference_bits,
                 "selection_sha256": selection_sha,
                 "note": "PRIVATE device-response material, git-ignored"}
    report = {"schema": "r7-selection-report-v1",
              "eligible_count": len(eligible),
              "selected_count": len(selected),
              "degree": degree,
              "min_selected_margin": min(m["min_margin"] for m in selected),
              "selection_sha256": selection_sha}
    for path, payload in ((args.mapping_out, mapping),
                          (args.reference_out, reference),
                          (args.report_out, report)):
        if path.exists():
            current = json.loads(path.read_text())
            key = "selection_sha256"
            if current.get(key) != selection_sha:
                print(f"R7_SELECT_MISMATCH: {path} differs", file=sys.stderr)
                return 1
        else:
            path.write_text(json.dumps(payload, indent=1, sort_keys=True) + "\n")
    print(f"R7_SELECTION_PASS sel={selection_sha[:12]}... "
          f"minmargin={min(m['min_margin'] for m in selected):.1f} "
          f"degree={min(degree)}-{max(degree)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
