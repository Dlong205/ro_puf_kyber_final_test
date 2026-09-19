#!/usr/bin/env python3
"""PUF64 train selector: unbiased per-boot weighting, frozen eligibility, and a
deterministic degree-balanced 264-pair mapping.

Uses only reliability/margin/topology. Never uses response sign as a selection
criterion, never touches holdout, never reads pilot data.
"""

import argparse
import hashlib
import json
import math
from pathlib import Path
import statistics
import sys

ALGORITHM_VERSION = "puf64-train-select-v1"
DEGREE_TARGET_LOW = 8
DEGREE_TARGET_HIGH = 9
SELECT_COUNT = 264


def canonical_json(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as source:
        for block in iter(lambda: source.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def load_train_sessions(campaign_dir, campaign="train"):
    sessions = []
    for path in sorted(Path(campaign_dir).glob(f"{campaign}_*.session.json")):
        manifest = json.loads(path.read_text())
        if manifest.get("status") != "VALID":
            continue
        dataset_path = Path(manifest["dataset_path"])
        if not dataset_path.is_file():
            continue
        sessions.append({"manifest": manifest, "dataset": json.loads(dataset_path.read_text())})
    return sessions


TRAIN_INPUT_SCHEMA = "puf64-train-input-v1"


def load_frozen_sessions(manifest_path, golden, golden_path):
    """Load sessions from the frozen private train-input manifest.

    Verifies the schema/identity, the golden-manifest hash, the aggregate
    train-input hash and every per-file SHA.  Any drift is a hard error; the
    selector must never fall back to a glob when a frozen input is given.
    """
    data = json.loads(Path(manifest_path).read_text())
    problems = []
    if data.get("schema") != TRAIN_INPUT_SCHEMA:
        problems.append(f"unexpected schema {data.get('schema')!r}")
    for key in ("board_id", "build_id", "protocol", "num_ro", "pair_count",
                "width", "ref_cycles", "bitstream_sha256"):
        if data.get(key) != golden.get(key):
            problems.append(
                f"{key}: frozen={data.get(key)} golden={golden.get(key)}")
    if data.get("golden_manifest_sha256") != sha256_file(golden_path):
        problems.append("golden manifest SHA mismatch")
    entries = data.get("boots", [])
    if data.get("aggregate_sha256") != sha256_bytes(canonical_json(entries)):
        problems.append("aggregate train-input hash mismatch")
    indices = [entry.get("boot_index") for entry in entries]
    if len(indices) != len(set(indices)):
        problems.append("duplicate boot_index in frozen input")
    if problems:
        raise ValueError("frozen train input rejected: " + "; ".join(problems))

    sessions = []
    for entry in entries:
        try:
            session_file = Path(entry["session_path"])
            dataset_file = Path(entry["dataset_path"])
            raw_file = Path(entry["raw_path"])
        except KeyError as error:
            raise ValueError(f"frozen entry missing {error}") from error
        if sha256_file(session_file) != entry["session_sha256"]:
            raise ValueError(
                f"boot {entry['boot_index']}: session SHA changed")
        if sha256_file(dataset_file) != entry["dataset_sha256"]:
            raise ValueError(
                f"boot {entry['boot_index']}: dataset SHA changed")
        if sha256_file(raw_file) != entry["raw_sha256"]:
            raise ValueError(
                f"boot {entry['boot_index']}: raw SHA changed")
        manifest = json.loads(session_file.read_text())
        if manifest.get("status") != "VALID":
            raise ValueError(
                f"boot {entry['boot_index']}: session not VALID")
        sessions.append({
            "manifest": manifest,
            "dataset": json.loads(dataset_file.read_text()),
        })
    return sessions, data["aggregate_sha256"]


def build_pair_metrics(sessions, ro_count, pair_count):
    n = len(sessions)
    pairs = [(a, b) for a in range(ro_count) for b in range(a + 1, ro_count)]
    metrics = []
    for index in range(pair_count):
        winners = []
        minorities = []
        ties = []
        margins_p01 = []
        margins_p05 = []
        margins_med = []
        for session in sessions:
            entry = session["dataset"]["per_pair"][index]
            winners.append(int(entry["consensus_winner"]))
            minorities.append(float(entry["minority_rate_percent"]))
            ties.append(int(entry["tie_count"]))
            margins_p01.append(float(entry["margin"]["p01"]))
            margins_p05.append(float(entry["margin"]["p05"]))
            margins_med.append(float(entry["margin"]["p50"]))
        ones = sum(winners)
        indeterminate = (ones * 2 == n)
        reference = None if indeterminate else int(ones * 2 > n)
        changed = sum(1 for w in winners if reference is not None and w != reference)
        metrics.append({
            "index": index,
            "pair": list(pairs[index]),
            "boot_winners": winners,
            "reference_bit": reference,
            "changed_boot_count": changed,
            "boot_count": n,
            "worst_minority_rate": max(minorities),
            "mean_minority_rate": statistics.fmean(minorities),
            "tie_events": sum(ties),
            "min_margin_p01": min(margins_p01),
            "median_margin_p01": statistics.median(margins_p01),
            "min_margin_p05": min(margins_p05),
            "median_margin": statistics.median(margins_med),
            "indeterminate": indeterminate,
        })
    return metrics


def eligibility(metric, min_boots, max_minority, min_margin):
    reasons = []
    if metric["boot_count"] < min_boots:
        reasons.append("insufficient_boots")
    if metric["indeterminate"]:
        reasons.append("indeterminate_reference")
    if metric["tie_events"] != 0:
        reasons.append("tie_event")
    if metric["changed_boot_count"] != 0:
        reasons.append("majority_changed")
    if metric["worst_minority_rate"] > max_minority:
        reasons.append("minority_rate")
    if metric["min_margin_p01"] < min_margin:
        reasons.append("margin")
    return reasons


def select_balanced(candidates, ro_count, select_count, degree_high):
    degree = [0] * ro_count
    selected = []
    remaining = list(candidates)
    while remaining and len(selected) < select_count:
        feasible = [
            m for m in remaining
            if degree[m["pair"][0]] < degree_high and degree[m["pair"][1]] < degree_high
        ]
        if not feasible:
            break
        best = min(feasible, key=lambda m: (
            max(degree[m["pair"][0]], degree[m["pair"][1]]),
            degree[m["pair"][0]] + degree[m["pair"][1]],
            -m["min_margin_p01"],
            m["worst_minority_rate"],
            -m["median_margin_p01"],
            m["pair"][0], m["pair"][1],
        ))
        remaining.remove(best)
        selected.append(best)
        degree[best["pair"][0]] += 1
        degree[best["pair"][1]] += 1
    return selected, degree


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--campaign-dir", required=True)
    parser.add_argument("--golden-manifest", required=True)
    parser.add_argument("--mapping-out", required=True)
    parser.add_argument("--reference-out", required=True)
    parser.add_argument("--train-input-manifest", default=None,
                        help="frozen private train-input manifest; selection "
                             "is bound to this exact session set")
    parser.add_argument("--report-out", default=None,
                        help="write the detailed private selection report")
    parser.add_argument("--min-boots", type=int, default=20)
    parser.add_argument("--max-minority-rate", type=float, default=10.0)
    parser.add_argument("--min-margin-p01", type=float, default=4.0)
    parser.add_argument("--select-count", type=int, default=SELECT_COUNT)
    parser.add_argument("--degree-high", type=int, default=DEGREE_TARGET_HIGH)
    args = parser.parse_args()

    golden = json.loads(Path(args.golden_manifest).read_text())
    if not golden.get("train_eligible"):
        print("BLOCKER: golden manifest train_eligible is not true")
        return 2
    train_input_sha = None
    if args.train_input_manifest:
        try:
            sessions, train_input_sha = load_frozen_sessions(
                args.train_input_manifest, golden, args.golden_manifest)
        except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
            print(f"BLOCKER: {error}")
            return 2
    else:
        sessions = load_train_sessions(args.campaign_dir)
    if len(sessions) < args.min_boots:
        print(f"BLOCKER: only {len(sessions)} valid train sessions, need {args.min_boots}")
        return 2

    metrics = build_pair_metrics(sessions, golden["num_ro"], golden["pair_count"])
    eligible = []
    ineligible_reasons = {}
    for metric in metrics:
        reasons = eligibility(metric, args.min_boots, args.max_minority_rate,
                              args.min_margin_p01)
        if reasons:
            if reasons != ["insufficient_boots"]:
                ineligible_reasons[metric["index"]] = reasons
        else:
            eligible.append(metric)

    if len(eligible) < args.select_count:
        print(f"BLOCKER: {len(eligible)} eligible pairs, need {args.select_count}")
        return 2

    eligible.sort(key=lambda m: (
        -m["min_margin_p01"], m["worst_minority_rate"],
        -m["median_margin_p01"], m["pair"][0], m["pair"][1],
    ))
    selected, degree = select_balanced(
        eligible, golden["num_ro"], args.select_count, args.degree_high
    )
    if len(selected) < args.select_count:
        print(f"BLOCKER: degree-balanced selection produced {len(selected)}/{args.select_count}")
        return 2
    if min(degree) < DEGREE_TARGET_LOW or max(degree) > args.degree_high:
        print(f"BLOCKER: degree target 8-9 unmet: min={min(degree)} max={max(degree)}")
        return 2

    ordered_pairs = [m["pair"] for m in selected]
    train_boots = [s["manifest"]["boot_index"] for s in sessions]
    dataset_hashes = sorted(
        s["manifest"]["parsed_dataset_sha256"] for s in sessions
    )
    selection_payload = {
        "algorithm": ALGORITHM_VERSION,
        "golden": {k: golden.get(k) for k in (
            "protocol", "image_mode", "topology_id", "build_id", "num_ro",
            "width", "ref_cycles", "bitstream_sha256", "route_fingerprint_sha256")},
        "train_input_sha256": train_input_sha,
        "train_boots": train_boots,
        "pairs": ordered_pairs,
        "config": {
            "min_boots": args.min_boots,
            "max_minority_rate": args.max_minority_rate,
            "min_margin_p01": args.min_margin_p01,
            "select_count": args.select_count,
            "degree_high": args.degree_high,
        },
    }
    selection_hash = sha256_bytes(canonical_json(selection_payload))

    mapping = dict(selection_payload)
    mapping.update({
        "schema": "ro-puf-train-mapping-v1",
        "status": "TRAIN_SELECTED_NOT_HOLDOUT_QUALIFIED",
        "mapping_tag": 0,
        "ro_degree": degree,
        "degree_distribution": {
            "8": sum(1 for d in degree if d == 8),
            "9": sum(1 for d in degree if d == 9),
        },
        "selected_metrics": [
            {"index": m["index"], "pair": m["pair"],
             "min_margin_p01": m["min_margin_p01"],
             "worst_minority_rate": m["worst_minority_rate"],
             "median_margin_p01": m["median_margin_p01"]}
            for m in selected
        ],
        "source_pair_indices": [m["index"] for m in selected],
        "dataset_sha256": dataset_hashes,
        "selection_sha256": selection_hash,
        "limitations": [
            "Single device ZYNQ-A01; inter-device uniqueness not established.",
            "264 is the FE codeword length, not an entropy measurement.",
            "log2(64!) ~= 296 bit is an order-model structural ceiling only.",
            "mapping_tag stays 0 until holdout PASS.",
        ],
    })
    Path(args.mapping_out).parent.mkdir(parents=True, exist_ok=True)
    Path(args.mapping_out).write_text(json.dumps(mapping, indent=2, sort_keys=True) + "\n")

    reference = {
        "selection_sha256": selection_hash,
        "train_input_sha256": train_input_sha,
        "reference_bit": {str(m["index"]): m["reference_bit"] for m in selected},
        "ineligible_pair_count": len(ineligible_reasons),
        "eligible_pair_count": len(eligible),
    }
    Path(args.reference_out).parent.mkdir(parents=True, exist_ok=True)
    Path(args.reference_out).write_text(json.dumps(reference, indent=2, sort_keys=True) + "\n")

    rejection_counts = {}
    for reasons in ineligible_reasons.values():
        for reason in reasons:
            rejection_counts[reason] = rejection_counts.get(reason, 0) + 1
    reference_ones = sum(1 for m in selected if m["reference_bit"] == 1)
    degree_histogram = {}
    for value in degree:
        degree_histogram[str(value)] = degree_histogram.get(str(value), 0) + 1
    report = {
        "schema": "ro-puf-train-selection-report-v1",
        "algorithm": ALGORITHM_VERSION,
        "status": mapping["status"],
        "mapping_tag": mapping["mapping_tag"],
        "total_pairs": golden.get("pair_count"),
        "eligible_pairs": len(eligible),
        "ineligible_pairs": len(ineligible_reasons),
        "rejection_counts": rejection_counts,
        "invalid_or_missing_pairs": 0,
        "selected_pairs": len(selected),
        "degree_min": min(degree),
        "degree_max": max(degree),
        "degree_histogram": degree_histogram,
        "degree_distribution": mapping["degree_distribution"],
        "selected_min_margin_p01": min(m["min_margin_p01"] for m in selected),
        "selected_median_margin_p01": statistics.median(
            m["min_margin_p01"] for m in selected),
        "selected_worst_minority_rate": max(
            m["worst_minority_rate"] for m in selected),
        "selected_changed_majority_count": sum(
            1 for m in selected if m["changed_boot_count"] != 0),
        "response_balance": {"ones": reference_ones,
                             "zeros": len(selected) - reference_ones,
                             "selection_criterion": False},
        "train_boots": train_boots,
        "train_input_sha256": train_input_sha,
        "selection_sha256": selection_hash,
    }
    if args.report_out:
        Path(args.report_out).parent.mkdir(parents=True, exist_ok=True)
        Path(args.report_out).write_text(
            json.dumps(report, indent=2, sort_keys=True) + "\n")

    print(json.dumps({
        "status": mapping["status"], "mapping": args.mapping_out,
        "selected": len(selected), "eligible": len(eligible),
        "degree_min": min(degree), "degree_max": max(degree),
        "degree_distribution": mapping["degree_distribution"],
        "selection_sha256": selection_hash,
        "train_input_sha256": train_input_sha,
        "response_balance": report["response_balance"],
    }, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
