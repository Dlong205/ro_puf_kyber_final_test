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
import math
from pathlib import Path
import sys


RO_COUNT = 32
PAIR_COUNT = 496
DEFAULT_SELECT_COUNT = 264
UNSPECIFIED = {"", "UNSPECIFIED", "unknown", "UNKNOWN"}


def canonical_pairs(ro_count=RO_COUNT):
    return [(a, b) for a in range(ro_count) for b in range(a + 1, ro_count)]


EXPECTED_PAIRS = canonical_pairs()


def pair_count_of(ro_count):
    return ro_count * (ro_count - 1) // 2


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


def load_campaign(path, expected_ro=None):
    path = Path(path).resolve()
    try:
        report = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"cannot read campaign {path}: {error}") from error

    ro_count = int(report.get("ro_count", RO_COUNT))
    pair_count = int(report.get("pair_count", pair_count_of(ro_count)))
    if ro_count < 4:
        raise ValueError(f"{path}: invalid NUM_RO {ro_count}")
    if pair_count != pair_count_of(ro_count):
        raise ValueError(f"{path}: pair_count {pair_count} contradicts NUM_RO {ro_count}")
    if expected_ro is not None and ro_count != expected_ro:
        raise ValueError(
            f"{path}: mixed pool sizes: expected {expected_ro}-RO report, got "
            f"{ro_count}-RO ({ro_count}/{pair_count} pairs)"
        )
    pairs = canonical_pairs(ro_count)
    entries = report.get("per_pair")
    if not isinstance(entries, list) or len(entries) != pair_count:
        raise ValueError(f"{path}: per_pair must contain {pair_count} entries")
    for index, expected_pair in enumerate(pairs):
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
    boot_index = campaign.get("boot_index")
    if boot_index is not None:
        try:
            boot_index = int(boot_index)
        except (TypeError, ValueError) as error:
            raise ValueError(f"{path}: non-integer boot_index") from error
    bitstream_hash = str(campaign.get("local_bitstream_sha256", ""))
    if len(bitstream_hash) != 64:
        raise ValueError(f"{path}: missing/invalid local_bitstream_sha256")
    return {
        "path": path,
        "report_sha256": sha256_file(path),
        "board_id": board_id,
        "condition_id": condition_id,
        "boot_index": boot_index,
        "bitstream_sha256": bitstream_hash,
        "sample_count": int(report.get("sample_count", 0)),
        "ro_count": ro_count,
        "pair_count": pair_count,
        "entries": entries,
        "assessment": report.get("assessment"),
    }


def validate_campaign_sets(training, holdout, session_split=False):
    if not training:
        raise ValueError("at least one training campaign is required")
    all_campaigns = training + holdout
    pool_sizes = {campaign["ro_count"] for campaign in all_campaigns}
    if len(pool_sizes) != 1:
        raise ValueError("training and holdout must not mix PUF32 and PUF64 reports")
    hashes = {campaign["bitstream_sha256"] for campaign in all_campaigns}
    if len(hashes) != 1:
        raise ValueError("all campaigns must use the same characterization bitstream")
    paths = [campaign["path"] for campaign in all_campaigns]
    if len(paths) != len(set(paths)):
        raise ValueError("a campaign file cannot appear in both training and holdout")
    train_boards = {campaign["board_id"] for campaign in training}
    holdout_boards = {campaign["board_id"] for campaign in holdout}
    train_sessions = {
        (campaign["board_id"], campaign["boot_index"])
        for campaign in training
    }
    holdout_sessions = {
        (campaign["board_id"], campaign["boot_index"])
        for campaign in holdout
    }
    if session_split:
        # Same board is acceptable, but an independent power-cycle is the
        # atomic measurement unit: no (board, boot_index) session may be
        # shared between training and holdout, and every session must be
        # explicitly numbered.
        for campaign in all_campaigns:
            if campaign["boot_index"] is None or campaign["boot_index"] <= 0:
                raise ValueError(
                    f"{campaign['path']}: session-split requires a positive boot_index"
                )
            if str(campaign["board_id"]) in UNSPECIFIED:
                raise ValueError(
                    f"{campaign['path']}: session-split requires an identified board_id"
                )
        session_overlap = train_sessions & holdout_sessions
        if session_overlap:
            raise ValueError(
                "training and holdout must use disjoint power-cycle sessions: "
                + ", ".join(sorted(f"{b}:{s}" for b, s in session_overlap))
            )
        return train_boards, holdout_boards, session_overlap, hashes.pop()
    overlap = train_boards & holdout_boards
    if overlap:
        raise ValueError(
            "training and holdout board IDs must be disjoint: "
            + ", ".join(sorted(overlap))
        )
    return train_boards, holdout_boards, set(), hashes.pop()


def aggregate_training(training, ro_count=None):
    if ro_count is None:
        ro_count = training[0]["ro_count"]
    pairs = canonical_pairs(ro_count)
    board_ids = sorted({campaign["board_id"] for campaign in training})
    aggregated = []
    for index, pair in enumerate(pairs):
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
                 max_ro_degree, ro_count=RO_COUNT):
    candidates = [
        entry for entry in entries
        if entry["margin_p01_min"] >= margin_threshold
        and entry["minority_rate_max"] <= max_minority_rate
        and entry["tie_count_total"] == 0
    ]
    degree = [0] * ro_count
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
                   min_holdout_boards=2, session_split=False,
                   min_training_sessions=15, min_holdout_sessions=8):
    train_boards, holdout_boards, session_overlap, bitstream_hash = \
        validate_campaign_sets(training, holdout, session_split)
    ro_count = training[0]["ro_count"]
    pair_count = training[0]["pair_count"]
    train_sessions = {
        (campaign["board_id"], campaign["boot_index"])
        for campaign in training
    }
    holdout_sessions = {
        (campaign["board_id"], campaign["boot_index"])
        for campaign in holdout
    }
    aggregated = aggregate_training(training, ro_count=ro_count)
    selected, degree, candidate_count = select_pairs(
        aggregated, select_count, margin_threshold,
        max_minority_rate, max_ro_degree, ro_count=ro_count
    )
    holdout_failures = validate_holdout(
        selected, holdout, margin_threshold, max_minority_rate
    ) if len(selected) == select_count else []
    identified = not any(
        value in UNSPECIFIED for value in train_boards | holdout_boards
    )
    if session_split:
        split_ok = all((
            len(train_sessions) >= min_training_sessions,
            len(holdout_sessions) >= min_holdout_sessions,
            not session_overlap,
        ))
    else:
        split_ok = all((
            len(train_boards) >= min_training_boards,
            len(holdout_boards) >= min_holdout_boards,
        ))
    reliability_qualified = all((
        len(selected) == select_count,
        split_ok,
        identified,
        not holdout_failures,
    ))
    split_policy = "session" if session_split else "board"
    assessments = [
        campaign["assessment"] for campaign in training + holdout
        if campaign["assessment"] is not None
    ]
    order_screened = len(assessments) == len(training) + len(holdout)
    order_cycle_max = None
    entropy_ceiling = None
    if assessments:
        order_cycle_max = max(
            float(a.get("order_cycle_rate_percent", {}).get("mean", 0.0))
            for a in assessments
        )
        entropy_ceiling = float(assessments[0]["entropy_ceiling_bits"])
    entropy_screened = (
        order_screened and order_cycle_max is not None
        and entropy_ceiling is not None
    )
    criteria = {
        "margin_p01_min": margin_threshold,
        "minority_rate_percent_max": max_minority_rate,
        "tie_count": 0,
        "max_ro_degree": max_ro_degree,
    }
    if session_split:
        criteria["min_training_sessions"] = min_training_sessions
        criteria["min_holdout_sessions"] = min_holdout_sessions
    else:
        criteria["min_training_boards"] = min_training_boards
        criteria["min_holdout_boards"] = min_holdout_boards
    ceiling = math.log2(math.factorial(ro_count))
    entropy_limitation = (
        f"All responses compare the same {ro_count} RO frequencies: ordering entropy "
        f"ceiling log2({ro_count}!) = {round(ceiling, 1)} bit, below the 128-bit "
        f"ML-KEM-512 target before bias/selection loss; 264 is the FE codeword "
        f"length, not an entropy claim."
    )
    if ceiling >= 128.0:
        entropy_limitation = (
            f"All responses compare the same {ro_count} RO frequencies: ordering "
            f"entropy ceiling log2({ro_count}!) = {round(ceiling, 1)} bit exceeds "
            f"the 128-bit target as a count upper bound only; per-device entropy, "
            f"bias-compensation and helper-data loss still need a device ensemble "
            f"analysis; 264 is the FE codeword length, not an entropy claim."
        )
    payload = {
        "schema": "ro-puf-pair-mapping-v1",
        "version": version,
        "split_policy": split_policy,
        "status": (
            "reliability-qualified-candidate"
            if reliability_qualified else "provisional"
        ),
        "reliability_qualified": reliability_qualified,
        # Reliability qualification alone never authorizes a PUF freeze.
        "puf_freeze_eligible": False,
        "ro_count": ro_count,
        "pair_count": pair_count,
        "selected_count": len(selected),
        "pairs": [entry["pair"] for entry in selected],
        "source_pair_indices": [entry["index"] for entry in selected],
        "ro_degree": degree,
        "criteria": criteria,
        "evidence": {
            "training_campaign_count": len(training),
            "training_board_count": len(train_boards),
            "training_session_count": len(train_sessions),
            "holdout_campaign_count": len(holdout),
            "holdout_board_count": len(holdout_boards),
            "holdout_session_count": len(holdout_sessions),
            "characterization_bitstream_sha256": bitstream_hash,
            "input_report_sha256": sorted(
                campaign["report_sha256"] for campaign in training + holdout
            ),
            "eligible_training_pair_count": candidate_count,
            "holdout_failure_campaign_count": len(holdout_failures),
            "correlation_screened": False,
            "order_structure_screened": order_screened,
            "order_cycle_rate_mean_max_percent": (
                round(order_cycle_max, 4) if order_cycle_max is not None else None
            ),
            "entropy_ceiling_bits": (
                round(entropy_ceiling, 3) if entropy_ceiling is not None else None
            ),
            "entropy_screened": entropy_screened,
        },
        "limitations": [
            "Pair selection improves reliability; it does not create 264 independent entropy bits.",
            entropy_limitation,
            "Conditional entropy given public helper data and the frozen mapping requires a separate device-ensemble and helper analysis.",
            "Correlation screening requires per-sample response sequences and remains open.",
            "Helper/KCV binding and integrated PUF-to-BCH validation remain separate gates.",
        ],
    }
    if session_split:
        payload["limitations"].append(
            "Single-device session split: holdout covers power-cycle/day "
            "variation on the same board only; inter-device generality, "
            "uniqueness and bit-alias across devices are NOT established."
        )
    payload["manifest_sha256"] = sha256_bytes(canonical_json(payload))
    private_audit = {
        "training_board_ids": sorted(train_boards),
        "holdout_board_ids": sorted(holdout_boards),
        "identifier_campaigns": sorted(
            f"{b}:{s}" for b, s in train_sessions | holdout_sessions
        ),
        "shared_sessions": sorted(
            f"{b}:{s}" for b, s in session_overlap
        ),
        "split_policy": split_policy,
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
    parser.add_argument(
        "--session-split", action="store_true",
        help="Allow the same board_id in both training and holdout as long as "
             "every campaign carries a unique (board_id, boot_index) session; "
             "a positive integer boot_index is then required."
    )
    parser.add_argument("--min-training-boards", type=int, default=3)
    parser.add_argument("--min-holdout-boards", type=int, default=2)
    parser.add_argument("--min-training-sessions", type=int, default=15)
    parser.add_argument("--min-holdout-sessions", type=int, default=8)
    parser.add_argument(
        "--require-reliability-qualified", action="store_true",
        help="fail instead of writing a provisional reliability manifest"
    )
    args = parser.parse_args()
    if not 1 <= args.select_count:
        parser.error("--select-count must be at least 1")
    if args.margin_threshold < 0:
        parser.error("--margin-threshold must be non-negative")
    if not 0 <= args.max_minority_rate <= 50:
        parser.error("--max-minority-rate must be between 0 and 50")
    if not 1 <= args.max_ro_degree <= 63:
        parser.error("--max-ro-degree must be between 1 and 63")
    if args.min_training_boards < 1 or args.min_holdout_boards < 1:
        parser.error("minimum board counts must be positive")
    if args.min_training_sessions < 1 or args.min_holdout_sessions < 1:
        parser.error("minimum session counts must be positive")
    if args.session_split and (args.min_training_boards > 1 or args.min_holdout_boards > 1):
        parser.error("--session-split overrides board gates; use --min-training-sessions/--min-holdout-sessions")
    try:
        training = [load_campaign(path) for path in args.training]
        holdout = [load_campaign(path, expected_ro=training[0]["ro_count"])
                   for path in args.holdout]
        ro_count = training[0]["ro_count"]
        pair_count = training[0]["pair_count"]
        if args.select_count > pair_count:
            raise ValueError(
                f"--select-count {args.select_count} exceeds pool size "
                f"C({ro_count},2) = {pair_count}"
            )
        if args.max_ro_degree > ro_count - 1:
            raise ValueError(
                f"--max-ro-degree {args.max_ro_degree} must not exceed NUM_RO-1 "
                f"= {ro_count - 1} for this pool"
            )
        manifest, audit = build_manifest(
            training, holdout, args.version, args.select_count,
            args.margin_threshold, args.max_minority_rate,
            args.max_ro_degree, args.min_training_boards,
            args.min_holdout_boards, args.session_split,
            args.min_training_sessions, args.min_holdout_sessions,
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
        f"split_policy={manifest['split_policy']} "
        f"training_boards={manifest['evidence']['training_board_count']} "
        f"training_sessions={manifest['evidence']['training_session_count']} "
        f"holdout_boards={manifest['evidence']['holdout_board_count']} "
        f"holdout_sessions={manifest['evidence']['holdout_session_count']} "
        f"status={manifest['status']} hash={manifest['manifest_sha256']}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
