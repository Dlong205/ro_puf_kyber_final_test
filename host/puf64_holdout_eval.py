#!/usr/bin/env python3
"""PUF64 holdout evaluator.

Given the frozen train mapping, the private train reference and 10 holdout
sessions, computes errors-per-vector statistics plus selected-pair/RO drift
metrics and applies the acceptance gate from the frozen protocol.

Fail-closed: the mapping file, private reference and train-input aggregate must
match the frozen holdout candidate (and the golden manifest mirror) or the
evaluation refuses to run.  Never re-selects pairs, never lowers a threshold,
never reuses holdout as train.  A nonzero mapping_tag is NOT created here:
canonicalization is a separate post-review step.
"""

import argparse
import hashlib
import json
import math
from pathlib import Path
import statistics
import sys

BCH_T = 8
P95_GATE = 4
HOLDOUT_FIRST = 201
HOLDOUT_LAST = 210
CANDIDATE_SCHEMA = "puf64-holdout-candidate-v1"


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


def canonical_pairs(ro_count):
    return [(a, b) for a in range(ro_count) for b in range(a + 1, ro_count)]


def load_holdout(campaign_dir, golden, first=HOLDOUT_FIRST,
                 last=HOLDOUT_LAST):
    """Load exactly the expected holdout boots; report every deviation."""
    sessions = []
    problems = []
    expected_names = set()
    for boot in range(first, last + 1):
        name = f"holdout_{golden['board_id']}_{boot}.session.json"
        expected_names.add(name)
        path = Path(campaign_dir) / name
        if not path.is_file():
            problems.append(f"boot {boot}: session missing")
            continue
        manifest = json.loads(path.read_text())
        if manifest.get("status") != "VALID":
            problems.append(f"boot {boot}: status {manifest.get('status')}")
            continue
        if manifest.get("campaign") != "holdout":
            problems.append(f"boot {boot}: campaign mismatch")
            continue
        if manifest.get("build_id") != golden.get("build_id"):
            problems.append(f"boot {boot}: build_id mismatch")
            continue
        if manifest.get("local_bitstream_sha256") != golden.get("bitstream_sha256"):
            problems.append(f"boot {boot}: bitstream SHA mismatch")
            continue
        dataset = Path(manifest["dataset_path"])
        raw = dataset.with_name(dataset.name.replace(".dataset.json", ".raw.json"))
        if not dataset.is_file() or not raw.is_file():
            problems.append(f"boot {boot}: dataset/raw missing")
            continue
        sessions.append((manifest, json.loads(dataset.read_text()),
                         json.loads(raw.read_text())))
    for path in sorted(Path(campaign_dir).glob("holdout_*.session.json")):
        if path.name not in expected_names:
            problems.append(f"unexpected holdout session {path.name}")
    return sessions, problems


def verify_candidate_binding(mapping, reference, candidate, golden, mapping_path,
                             reference_path):
    """Return a list of fail-closed mismatch problems."""
    problems = []
    selection = mapping.get("selection_sha256")
    if golden.get("holdout_candidate_selection_sha256") != selection:
        problems.append("golden selection hash != mapping selection hash")
    if golden.get("holdout_candidate_mapping_file_sha256") != \
            sha256_file(mapping_path):
        problems.append("golden mapping file SHA != mapping file")
    if reference.get("selection_sha256") != selection:
        problems.append("reference selection hash != mapping selection hash")
    if candidate is not None:
        if candidate.get("schema") != CANDIDATE_SCHEMA:
            problems.append("candidate schema mismatch")
        if candidate.get("status") != "TRAIN_SELECTED_NOT_HOLDOUT_QUALIFIED" or \
                candidate.get("mapping_tag") != 0:
            problems.append("candidate is not a frozen train candidate")
        if candidate.get("selection_sha256") != selection:
            problems.append("candidate selection hash mismatch")
        if candidate.get("mapping_file_sha256") != sha256_file(mapping_path):
            problems.append("candidate mapping file SHA mismatch")
        if candidate.get("reference_file_sha256") != sha256_file(reference_path):
            problems.append("candidate reference file SHA mismatch")
        if candidate.get("train_input_aggregate_sha256") != \
                mapping.get("train_input_sha256"):
            problems.append("candidate train-input hash mismatch")
        if candidate.get("ordered_pairs") != mapping.get("pairs"):
            problems.append("candidate pair order mismatch")
        if candidate.get("ro_degree") != mapping.get("ro_degree"):
            problems.append("candidate degree vector mismatch")
        for key in ("board_id", "protocol", "build_id", "topology_id",
                    "record_bytes", "width", "ref_cycles", "num_ro",
                    "pair_count", "bitstream_sha256"):
            if candidate.get(key) != golden.get(key):
                problems.append(f"candidate {key} != golden")
    return problems


def load_frozen_holdout_sessions(manifest_path, golden, mapping, reference,
                                 mapping_path, reference_path):
    """Load exactly the frozen holdout boots and verify every bound hash.

    No glob fallback: the evaluator only accepts the frozen private manifest.
    """
    data = json.loads(Path(manifest_path).read_text())
    problems = []
    if data.get("schema") != "puf64-holdout-input-v1":
        problems.append(f"unexpected schema {data.get('schema')!r}")
    for key in ("board_id", "protocol", "build_id", "topology_id",
                "record_bytes", "width", "ref_cycles", "num_ro", "pair_count",
                "bitstream_sha256"):
        if data.get(key) != golden.get(key):
            problems.append(
                f"{key}: frozen={data.get(key)} golden={golden.get(key)}")
    if data.get("golden_manifest_sha256") is None:
        problems.append("missing golden_manifest_sha256")
    if data.get("candidate_mapping_file_sha256") != sha256_file(mapping_path):
        problems.append("frozen mapping file SHA mismatch")
    if data.get("candidate_selection_sha256") != mapping.get("selection_sha256"):
        problems.append("frozen selection hash mismatch")
    if data.get("train_input_aggregate_sha256") != \
            mapping.get("train_input_sha256"):
        problems.append("frozen train-input hash mismatch")
    if data.get("train_reference_file_sha256") != sha256_file(reference_path):
        problems.append("frozen reference file SHA mismatch")
    entries = data.get("boots", [])
    if data.get("aggregate_sha256") != sha256_bytes(canonical_json(entries)):
        problems.append("aggregate holdout-input hash mismatch")
    indices = [entry.get("boot_index") for entry in entries]
    if len(indices) != len(set(indices)):
        problems.append("duplicate boot_index in frozen holdout input")
    if problems:
        raise ValueError("frozen holdout input rejected: " + "; ".join(problems))

    sessions = []
    for entry in entries:
        session_file = Path(entry["session_path"])
        dataset_file = Path(entry["dataset_path"])
        raw_file = Path(entry["raw_path"])
        if sha256_file(session_file) != entry["session_sha256"]:
            raise ValueError(f"boot {entry['boot_index']}: session SHA changed")
        if sha256_file(dataset_file) != entry["dataset_sha256"]:
            raise ValueError(f"boot {entry['boot_index']}: dataset SHA changed")
        if sha256_file(raw_file) != entry["raw_sha256"]:
            raise ValueError(f"boot {entry['boot_index']}: raw SHA changed")
        sessions.append((json.loads(session_file.read_text()),
                         json.loads(dataset_file.read_text()),
                         json.loads(raw_file.read_text())))
    return sessions, data["aggregate_sha256"]


def evaluate(mapping, reference, sessions, golden):
    indices = mapping["source_pair_indices"]
    ref_bits = [reference["reference_bit"][str(i)] for i in indices]
    pairs = canonical_pairs(golden["num_ro"])
    ordered_pairs = mapping.get("pairs") or [pairs[i] for i in indices]
    frame_errors = []
    boot_majority_errors = []
    failing_frames = 0
    failing_boots = 0
    valid_sessions = 0
    per_session = []
    pair_error_counts = [0] * len(indices)
    selected_pair_metrics = []
    ro_values = {ro: {} for ro in range(golden["num_ro"])}
    for j, index in enumerate(indices):
        a, b = ordered_pairs[j]
        selected_pair_metrics.append({
            "index": index, "pair": [a, b],
            "tie_events": 0, "worst_minority_rate": 0.0,
            "_margin_p01": [], "_margin_p50": [],
        })
    for manifest, dataset, raw in sessions:
        problems = []
        device = manifest.get("device_info", {})
        tuple_keys = {
            "protocol": "protocol", "build_id": "build_id",
            "topology_id": "topology_id", "record_bytes": "record_bytes",
            "width": "width", "ref_cycles": "ref_cycles",
            "num_ro": "num_ro", "pair_count": "pair_count",
            "system_clock_hz": "clock_system_hz",
            "input_clock_hz": "clock_input_hz",
            "image_mode_code": "image_mode_code",
        }
        for device_key, golden_key in tuple_keys.items():
            expected = golden.get(golden_key)
            if expected is not None and device.get(device_key) != expected:
                problems.append(f"{device_key} mismatch")
        if device.get("mmcm_locked") is not None and device.get("mmcm_locked") != 1:
            problems.append("MMCM not locked")
        frames = raw["frames_winners_hex"]
        if len(frames) != manifest.get("frames_requested"):
            problems.append("frame_count mismatch")
        if len(dataset.get("per_pair", [])) != golden["pair_count"]:
            problems.append("dataset pair_count mismatch")
        else:
            for entry_index in indices:
                entry = dataset["per_pair"][entry_index]
                if entry["count0"]["p50"] == 0 or entry["count1"]["p50"] == 0:
                    problems.append(f"pair {entry_index} zero count")
                    break
        if problems:
            per_session.append({"boot": manifest["boot_index"],
                                "valid": False, "problems": problems})
            continue
        valid_sessions += 1
        first_frame_index = len(frame_errors)
        boot_bits = [[0] * len(indices) for _ in range(len(frames))]
        for f, hex_value in enumerate(frames):
            value = int(hex_value, 16)
            boot_frame_errors = 0
            for j, index in enumerate(indices):
                bit = (value >> index) & 1
                boot_bits[f][j] = bit
                if bit != ref_bits[j]:
                    boot_frame_errors += 1
                    pair_error_counts[j] += 1
            frame_errors.append(boot_frame_errors)
            if boot_frame_errors > BCH_T:
                failing_frames += 1
        majority = []
        for j in range(len(indices)):
            ones = sum(boot_bits[f][j] for f in range(len(frames)))
            majority.append(1 if ones * 2 > len(frames) else 0)
        boot_errors = sum(1 for j in range(len(indices))
                          if majority[j] != ref_bits[j])
        boot_majority_errors.append(boot_errors)
        if boot_errors > BCH_T:
            failing_boots += 1
        session_frame_errors = frame_errors[first_frame_index:]
        majority_value = 0
        for j, bit in enumerate(majority):
            if bit:
                majority_value |= (1 << j)
        per_session.append({
            "boot": manifest["boot_index"], "valid": True,
            "frames": len(frames),
            "boot_majority_errors": boot_errors,
            "boot_majority_hex": majority_value.to_bytes(
                (len(indices) + 7) // 8, "big").hex(),
            "max_frame_errors": max(session_frame_errors, default=0),
        })
        boot = manifest["boot_index"]
        for j, index in enumerate(indices):
            entry = dataset["per_pair"][index]
            metrics = selected_pair_metrics[j]
            metrics["tie_events"] += int(entry["tie_count"])
            metrics["worst_minority_rate"] = max(
                metrics["worst_minority_rate"],
                float(entry["minority_rate_percent"]))
            metrics["_margin_p01"].append(float(entry["margin"]["p01"]))
            metrics["_margin_p50"].append(float(entry["margin"]["p50"]))
            a, b = ordered_pairs[j]
            ro_values[a].setdefault(boot, []).append(entry["count0"]["p50"])
            ro_values[b].setdefault(boot, []).append(entry["count1"]["p50"])
    for metrics in selected_pair_metrics:
        metrics["min_margin_p01"] = min(metrics["_margin_p01"]) \
            if metrics["_margin_p01"] else None
        metrics["median_margin_p01"] = statistics.median(metrics["_margin_p01"]) \
            if metrics["_margin_p01"] else None
        metrics["median_margin_p50"] = statistics.median(metrics["_margin_p50"]) \
            if metrics["_margin_p50"] else None
        del metrics["_margin_p01"]
        del metrics["_margin_p50"]
    per_ro_span = {}
    for ro, boots in ro_values.items():
        medians = [statistics.median(values) for values in boots.values()
                   if values]
        per_ro_span[str(ro)] = (max(medians) - min(medians)) if medians else None
    total_frames = len(frame_errors)
    pair_frequency = [
        (count / total_frames) if total_frames else 0.0
        for count in pair_error_counts]
    margins_p01 = [m["min_margin_p01"] for m in selected_pair_metrics
                   if m["min_margin_p01"] is not None]
    margins_p50 = [m["median_margin_p50"] for m in selected_pair_metrics
                   if m["median_margin_p50"] is not None]
    abnormal_ro = sorted(
        int(ro) for ro, span in per_ro_span.items()
        if span is not None and span > 4)
    no_data_ro = sorted(int(ro) for ro, span in per_ro_span.items()
                        if span is None)
    return {
        "valid_sessions": valid_sessions,
        "frame_errors": frame_errors,
        "frame_error_histogram": {
            "errors_0": sum(1 for e in frame_errors if e == 0),
            "errors_1_4": sum(1 for e in frame_errors if 1 <= e <= 4),
            "errors_5_8": sum(1 for e in frame_errors if 5 <= e <= 8),
            "errors_over_8": sum(1 for e in frame_errors if e > BCH_T),
        },
        "boot_majority_errors": boot_majority_errors,
        "failing_frames": failing_frames,
        "failing_boots": failing_boots,
        "per_session": per_session,
        "selected_pair_metrics": selected_pair_metrics,
        "selected_pair_error_frequency": {
            "max": max(pair_frequency, default=0.0),
            "median": statistics.median(pair_frequency) if pair_frequency else 0.0,
            "pairs_with_any_error": sum(1 for value in pair_frequency if value > 0),
            "per_pair": pair_frequency,
        },
        "selected_pairs_with_tie": sum(
            1 for m in selected_pair_metrics if m["tie_events"] > 0),
        "selected_pairs_with_minority": sum(
            1 for m in selected_pair_metrics if m["worst_minority_rate"] > 0),
        "selected_margin_p01": {
            "worst": min(margins_p01) if margins_p01 else None,
            "median": statistics.median(margins_p01) if margins_p01 else None,
        },
        "selected_margin_p50_median": statistics.median(margins_p50) \
            if margins_p50 else None,
        "selected_response_balance": {
            "ones": sum(ref_bits),
            "zeros": len(ref_bits) - sum(ref_bits),
            "selection_criterion": False,
        },
        "per_ro_count_p50_span": per_ro_span,
        "abnormal_ro_count_p50_span": abnormal_ro,
        "ro_without_data": no_data_ro,
    }


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--mapping", required=True)
    parser.add_argument("--reference", required=True)
    parser.add_argument("--holdout-dir", default=None,
                        help="deprecated; sessions come from the frozen "
                             "holdout-input manifest")
    parser.add_argument("--holdout-input-manifest", required=True,
                        help="frozen private holdout-input manifest")
    parser.add_argument("--golden-manifest", required=True)
    parser.add_argument("--holdout-candidate", required=True)
    parser.add_argument("--report-out", required=True)
    parser.add_argument("--frozen-out", default=None)
    parser.add_argument("--post-review-freeze", action="store_true",
                        help="only after explicit review: canonicalize the "
                             "mapping and derive mapping_tag != 0")
    parser.add_argument("--min-boots", type=int, default=10)
    args = parser.parse_args(argv)

    mapping = json.loads(Path(args.mapping).read_text())
    reference = json.loads(Path(args.reference).read_text())
    golden = json.loads(Path(args.golden_manifest).read_text())
    if not golden.get("holdout_eligible"):
        print("BLOCKER: golden manifest holdout_eligible is not true")
        return 2
    if mapping.get("status") != "TRAIN_SELECTED_NOT_HOLDOUT_QUALIFIED":
        print("BLOCKER: mapping is not a frozen train candidate")
        return 2
    if mapping.get("mapping_tag") not in (0, None):
        print("BLOCKER: mapping_tag already set; holdout already consumed")
        return 2
    candidate = json.loads(Path(args.holdout_candidate).read_text())
    problems = verify_candidate_binding(
        mapping, reference, candidate, golden, args.mapping, args.reference)
    if problems:
        print("BLOCKER: frozen candidate binding failed:")
        for problem in problems:
            print(f"  - {problem}")
        return 2

    try:
        sessions, holdout_input_sha = load_frozen_holdout_sessions(
            args.holdout_input_manifest, golden, mapping, reference,
            args.mapping, args.reference)
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(f"BLOCKER: {error}")
        return 2
    if len(sessions) != args.min_boots:
        print(f"BLOCKER: {len(sessions)} holdout sessions, need "
              f"{args.min_boots}")
        return 2

    result = evaluate(mapping, reference, sessions, golden)
    frame_errors = result["frame_errors"]
    total_frames = len(frame_errors)
    p50 = percentile(frame_errors, 0.50)
    p95 = percentile(frame_errors, 0.95)
    p99 = percentile(frame_errors, 0.99)
    max_err = max(frame_errors) if frame_errors else 0
    frr = result["failing_frames"] / total_frames if total_frames else 1.0
    invalid_sessions = [session for session in result["per_session"]
                        if not session.get("valid", True)]
    gate = {
        "holdout_boots_valid": result["valid_sessions"] >= args.min_boots,
        "no_selected_pair_invalid": not invalid_sessions,
        "no_frame_over_bch": result["failing_frames"] == 0,
        "no_boot_majority_over_bch": result["failing_boots"] == 0,
        "observed_frr_zero": frr == 0.0,
        "p95_le_4": p95 <= P95_GATE,
    }
    passed = all(gate.values())
    boot_errors = result["boot_majority_errors"]
    session_failure_rate = (
        result["failing_boots"] / result["valid_sessions"]
        if result["valid_sessions"] else 1.0)
    report = {
        "frames_observed": total_frames,
        "independent_boots": result["valid_sessions"],
        "p50": p50, "p95": p95, "p99": p99, "max": max_err,
        "frame_errors": result["frame_errors"],
        "frame_error_histogram": result["frame_error_histogram"],
        "frame_level_failure_rate": frr,
        "boot_majority_errors": boot_errors,
        "boot_majority_p50": percentile(boot_errors, 0.50),
        "boot_majority_p95": percentile(boot_errors, 0.95),
        "boot_majority_max": max(boot_errors) if boot_errors else 0,
        "frames_over_bch": result["failing_frames"],
        "boots_majority_over_bch": result["failing_boots"],
        "session_level_failure_rate": session_failure_rate,
        "observed_frr": frr,
        "per_session": result["per_session"],
        "selected_pair_metrics": result["selected_pair_metrics"],
        "selected_pair_error_frequency": result["selected_pair_error_frequency"],
        "selected_pairs_with_tie": result["selected_pairs_with_tie"],
        "selected_pairs_with_minority": result["selected_pairs_with_minority"],
        "selected_margin_p01": result["selected_margin_p01"],
        "selected_margin_p50_median": result["selected_margin_p50_median"],
        "selected_response_balance": result["selected_response_balance"],
        "per_ro_count_p50_span": result["per_ro_count_p50_span"],
        "abnormal_ro_count_p50_span": result["abnormal_ro_count_p50_span"],
        "ro_without_data": result["ro_without_data"],
        "holdout_input_sha256": holdout_input_sha,
        "frozen_candidate": {
            "selection_sha256": candidate.get("selection_sha256"),
            "mapping_file_sha256": candidate.get("mapping_file_sha256"),
            "train_input_aggregate_sha256":
                candidate.get("train_input_aggregate_sha256"),
            "reference_file_sha256": candidate.get("reference_file_sha256"),
        },
        "gate": gate, "passed": passed,
        "mapping_tag": 0,
        "note": "unqualified: canonicalization/mapping_tag is a separate "
                "post-review step",
    }
    Path(args.report_out).parent.mkdir(parents=True, exist_ok=True)
    Path(args.report_out).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")

    if args.post_review_freeze:
        print("NOTE: mapping canonicalization is owned by "
              "host/puf64_canonicalize_mapping.py (single source of truth for "
              "the full digest and the 16-bit on-wire tag); no tag written here.")

    print(json.dumps(report, indent=2, sort_keys=True))
    return 0 if passed else 1


def percentile(values, pct):
    ordered = sorted(values)
    if not ordered:
        return 0
    rank = max(1, math.ceil(pct * len(ordered)))
    return ordered[rank - 1]


if __name__ == "__main__":
    sys.exit(main())
