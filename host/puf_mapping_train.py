#!/usr/bin/env python3
"""Select and validate a reliability-aware 264-pair RO-PUF mapping.

Selection uses training reports only.  Holdout reports are evaluated after the
mapping is fixed and never influence pair choice.  Board-count, identity and
holdout gates can qualify reliability, but never authorize a PUF freeze by
themselves.
Detailed input reports remain private device-characterization data; the output
manifest contains only the fixed pair schedule and reproducibility metadata.
"""

import argparse
import hashlib
import json
from pathlib import Path
import sys


RO_COUNT = 32
PAIR_COUNT = 496
DEFAULT_SELECT_COUNT = 264
UNSPECIFIED = {"", "UNSPECIFIED", "unknown", "UNKNOWN"}


def canonical_pairs():
    return [(a, b) for a in range(RO_COUNT) for b in range(a + 1, RO_COUNT)]


EXPECTED_PAIRS = canonical_pairs()


def canonical_json(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def sha256_bytes(value):
    return hashlib.sha256(value).hexdigest()


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_campaign(path):
    path = Path(path).resolve()
    try:
        report = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"cannot read campaign {path}: {error}") from error

    if report.get("ro_count") != RO_COUNT or report.get("pair_count") != PAIR_COUNT:
        raise ValueError(f"{path}: expected a {RO_COUNT}-RO/{PAIR_COUNT}-pair report")
    entries = report.get("per_pair")
    if not isinstance(entries, list) or len(entries) != PAIR_COUNT:
        raise ValueError(f"{path}: per_pair must contain {PAIR_COUNT} entries")
    for index, expected_pair in enumerate(EXPECTED_PAIRS):
        entry = entries[index]
        if entry.get("index") != index or tuple(entry.get("pair", ())) != expected_pair:
            raise ValueError(f"{path}: non-canonical pair entry at index {index}")
        try:
            float(entry["margin"]["p01"])
            float(entry["margin"]["p05"])
            float(entry["minority_rate_percent"])
            int(entry["tie_count"])
            winner = int(entry["consensus_winner"])
        except (KeyError, TypeError, ValueError) as error:
            raise ValueError(f"{path}: incomplete metrics at pair {index}") from error
        if winner not in (0, 1):
            raise ValueError(f"{path}: invalid consensus winner at pair {index}")

    campaign = report.get("campaign", {})
    board_id = str(campaign.get("board_id", "UNSPECIFIED"))
    condition_id = str(campaign.get("condition_id", "UNSPECIFIED"))
    bitstream_hash = str(campaign.get("local_bitstream_sha256", ""))
    if len(bitstream_hash) != 64:
        raise ValueError(f"{path}: missing/invalid local_bitstream_sha256")
    return {
        "path": path,
        "report_sha256": sha256_file(path),
        "board_id": board_id,
        "condition_id": condition_id,
        "bitstream_sha256": bitstream_hash,
        "sample_count": int(report.get("sample_count", 0)),
        "entries": entries,
    }


def validate_campaign_sets(training, holdout):
    if not training:
        raise ValueError("at least one training campaign is required")
    all_campaigns = training + holdout
    hashes = {campaign["bitstream_sha256"] for campaign in all_campaigns}
    if len(hashes) != 1:
        raise ValueError("all campaigns must use the same characterization bitstream")
    paths = [campaign["path"] for campaign in all_campaigns]
    if len(paths) != len(set(paths)):
        raise ValueError("a campaign file cannot appear in both training and holdout")
    train_boards = {campaign["board_id"] for campaign in training}
    holdout_boards = {campaign["board_id"] for campaign in holdout}
    overlap = train_boards & holdout_boards
    if overlap:
        raise ValueError(
            "training and holdout board IDs must be disjoint: "
            + ", ".join(sorted(overlap))
        )
    return train_boards, holdout_boards, hashes.pop()


def aggregate_training(training):
    board_ids = sorted({campaign["board_id"] for campaign in training})
    aggregated = []
    for index, pair in enumerate(EXPECTED_PAIRS):
        entries = [campaign["entries"][index] for campaign in training]
        board_winners = []
        for board_id in board_ids:
            winners = [
                int(campaign["entries"][index]["consensus_winner"])
                for campaign in training if campaign["board_id"] == board_id
            ]
            board_winners.append(int(sum(winners) * 2 >= len(winners)))
        one_rate = 100.0 * sum(board_winners) / len(board_winners)
        aggregated.append({
            "index": index,
            "pair": list(pair),
            "margin_p01_min": min(float(entry["margin"]["p01"]) for entry in entries),
            "margin_p05_min": min(float(entry["margin"]["p05"]) for entry in entries),
            "minority_rate_max": max(
                float(entry["minority_rate_percent"]) for entry in entries
            ),
            "tie_count_total": sum(int(entry["tie_count"]) for entry in entries),
            "board_one_rate_percent": one_rate,
            "bit_alias_distance_percent": abs(one_rate - 50.0),
        })
    return aggregated


def select_pairs(entries, count, margin_threshold, max_minority_rate,
                 max_ro_degree):
    candidates = [
        entry for entry in entries
        if entry["margin_p01_min"] >= margin_threshold
        and entry["minority_rate_max"] <= max_minority_rate
        and entry["tie_count_total"] == 0
    ]
    degree = [0] * RO_COUNT
    selected = []
    remaining = candidates[:]
    while remaining and len(selected) < count:
        feasible = [
            entry for entry in remaining
            if degree[entry["pair"][0]] < max_ro_degree
            and degree[entry["pair"][1]] < max_ro_degree
        ]
        if not feasible:
            break
        best = min(feasible, key=lambda entry: (
            max(degree[entry["pair"][0]], degree[entry["pair"][1]]),
            degree[entry["pair"][0]] + degree[entry["pair"][1]],
            -entry["margin_p01_min"],
            entry["minority_rate_max"],
            entry["bit_alias_distance_percent"],
            -entry["margin_p05_min"],
            entry["index"],
        ))
        remaining.remove(best)
        selected.append(best)
        degree[best["pair"][0]] += 1
        degree[best["pair"][1]] += 1
    return selected, degree, len(candidates)


def validate_holdout(selected, holdout, margin_threshold, max_minority_rate):
    failures = []
    for campaign in holdout:
        failed_pairs = []
        for selected_entry in selected:
            index = selected_entry["index"]
            entry = campaign["entries"][index]
            reasons = []
            if float(entry["margin"]["p01"]) < margin_threshold:
                reasons.append("margin")
            if float(entry["minority_rate_percent"]) > max_minority_rate:
                reasons.append("minority_rate")
            if int(entry["tie_count"]) != 0:
                reasons.append("tie")
            if reasons:
                failed_pairs.append({"index": index, "reasons": reasons})
        if failed_pairs:
            failures.append({
                "board_id": campaign["board_id"],
                "condition_id": campaign["condition_id"],
                "failed_pair_count": len(failed_pairs),
                "failed_pairs": failed_pairs,
            })
    return failures


def build_manifest(training, holdout, version, select_count=DEFAULT_SELECT_COUNT,
                   margin_threshold=4, max_minority_rate=1.0,
                   max_ro_degree=17, min_training_boards=3,
                   min_holdout_boards=2):
    train_boards, holdout_boards, bitstream_hash = validate_campaign_sets(
        training, holdout
    )
    aggregated = aggregate_training(training)
    selected, degree, candidate_count = select_pairs(
        aggregated, select_count, margin_threshold,
        max_minority_rate, max_ro_degree
    )
    holdout_failures = validate_holdout(
        selected, holdout, margin_threshold, max_minority_rate
    ) if len(selected) == select_count else []
    identified = not any(
        value in UNSPECIFIED for value in train_boards | holdout_boards
    )
    reliability_qualified = all((
        len(selected) == select_count,
        len(train_boards) >= min_training_boards,
        len(holdout_boards) >= min_holdout_boards,
        identified,
        not holdout_failures,
    ))
    payload = {
        "schema": "ro-puf-pair-mapping-v1",
        "version": version,
        "status": (
            "reliability-qualified-candidate"
            if reliability_qualified else "provisional"
        ),
        "reliability_qualified": reliability_qualified,
        # Reliability qualification alone never authorizes a PUF freeze.
        "puf_freeze_eligible": False,
        "ro_count": RO_COUNT,
        "pair_count": PAIR_COUNT,
        "selected_count": len(selected),
        "pairs": [entry["pair"] for entry in selected],
        "source_pair_indices": [entry["index"] for entry in selected],
        "ro_degree": degree,
        "criteria": {
            "margin_p01_min": margin_threshold,
            "minority_rate_percent_max": max_minority_rate,
            "tie_count": 0,
            "max_ro_degree": max_ro_degree,
            "min_training_boards": min_training_boards,
            "min_holdout_boards": min_holdout_boards,
        },
        "evidence": {
            "training_campaign_count": len(training),
            "training_board_count": len(train_boards),
            "holdout_campaign_count": len(holdout),
            "holdout_board_count": len(holdout_boards),
            "characterization_bitstream_sha256": bitstream_hash,
            "input_report_sha256": sorted(
                campaign["report_sha256"] for campaign in training + holdout
            ),
            "eligible_training_pair_count": candidate_count,
            "holdout_failure_campaign_count": len(holdout_failures),
            "correlation_screened": False,
        },
        "limitations": [
            "Pair selection improves reliability; it does not create 264 independent entropy bits.",
            "Correlation screening requires per-sample response sequences and remains open.",
            "Helper/KCV binding and integrated PUF-to-BCH validation remain separate gates.",
        ],
    }
    payload["manifest_sha256"] = sha256_bytes(canonical_json(payload))
    private_audit = {
        "training_board_ids": sorted(train_boards),
        "holdout_board_ids": sorted(holdout_boards),
        "identified_campaigns": identified,
        "holdout_failures": holdout_failures,
        "selected_training_metrics": selected,
    }
    return payload, private_audit


def main():
    parser = argparse.ArgumentParser(
        description="Train and independently validate a 264-pair RO-PUF mapping"
    )
    parser.add_argument("--training", nargs="+", required=True)
    parser.add_argument("--holdout", nargs="*", default=[])
    parser.add_argument("--version", required=True)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--private-audit")
    parser.add_argument("--select-count", type=int, default=DEFAULT_SELECT_COUNT)
    parser.add_argument("--margin-threshold", type=float, default=4.0)
    parser.add_argument("--max-minority-rate", type=float, default=1.0)
    parser.add_argument("--max-ro-degree", type=int, default=17)
    parser.add_argument("--min-training-boards", type=int, default=3)
    parser.add_argument("--min-holdout-boards", type=int, default=2)
    parser.add_argument(
        "--require-reliability-qualified", action="store_true",
        help="fail instead of writing a provisional reliability manifest"
    )
    args = parser.parse_args()
    if not 1 <= args.select_count <= PAIR_COUNT:
        parser.error("--select-count must be between 1 and 496")
    if args.margin_threshold < 0:
        parser.error("--margin-threshold must be non-negative")
    if not 0 <= args.max_minority_rate <= 50:
        parser.error("--max-minority-rate must be between 0 and 50")
    if not 1 <= args.max_ro_degree <= 31:
        parser.error("--max-ro-degree must be between 1 and 31")
    if args.min_training_boards < 1 or args.min_holdout_boards < 1:
        parser.error("minimum board counts must be positive")
    try:
        training = [load_campaign(path) for path in args.training]
        holdout = [load_campaign(path) for path in args.holdout]
        manifest, audit = build_manifest(
            training, holdout, args.version, args.select_count,
            args.margin_threshold, args.max_minority_rate,
            args.max_ro_degree, args.min_training_boards,
            args.min_holdout_boards,
        )
    except ValueError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    if args.require_reliability_qualified and not manifest["reliability_qualified"]:
        print("ERROR: mapping failed reliability-qualification gates", file=sys.stderr)
        return 2
    output = Path(args.manifest)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    if args.private_audit:
        private_output = Path(args.private_audit)
        private_output.parent.mkdir(parents=True, exist_ok=True)
        private_output.write_text(json.dumps(audit, indent=2, sort_keys=True) + "\n")
    print(
        f"mapping={manifest['selected_count']}/{args.select_count} "
        f"training_boards={manifest['evidence']['training_board_count']} "
        f"holdout_boards={manifest['evidence']['holdout_board_count']} "
        f"status={manifest['status']} hash={manifest['manifest_sha256']}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
