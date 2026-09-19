#!/usr/bin/env python3
"""PUF64 holdout evaluator and identity-bound mapping freeze.

Given a frozen train mapping + private train reference and holdout sessions,
computes errors-per-vector statistics and applies the acceptance gate.  Only on
PASS does it emit a nonzero mapping_tag bound to the golden identity.
"""

import argparse
import hashlib
import json
from pathlib import Path
import statistics
import sys

BCH_T = 8
P95_GATE = 4


def canonical_json(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def load_holdout(campaign_dir):
    sessions = []
    for path in sorted(Path(campaign_dir).glob("holdout_*.session.json")):
        manifest = json.loads(path.read_text())
        if manifest.get("status") != "VALID":
            continue
        dataset = json.loads(Path(manifest["dataset_path"]).read_text())
        raw = json.loads(
            Path(manifest["dataset_path"]).with_name(
                Path(manifest["dataset_path"]).name.replace(".dataset.json", ".raw.json")
            ).read_text()
        )
        sessions.append((manifest, dataset, raw))
    return sessions


def percentile(values, pct):
    ordered = sorted(values)
    if not ordered:
        return 0
    import math
    rank = max(1, math.ceil(pct * len(ordered)))
    return ordered[rank - 1]


def evaluate(mapping, reference, sessions, golden):
    indices = mapping["source_pair_indices"]
    ref_bits = [reference["reference_bit"][str(i)] for i in indices]
    errors = []
    frame_errors = []
    boot_majority_errors = []
    failing_frames = 0
    failing_boots = 0
    valid_sessions = 0
    per_session = []
    for manifest, dataset, raw in sessions:
        problems = []
        for key, expected in (("build_id", golden["build_id"]),
                              ("topology_id", golden["topology_id"]),
                              ("image_mode_code", golden["image_mode_code"])):
            if manifest["device_info"].get(key) != expected:
                problems.append(f"{key} mismatch")
        frames = raw["frames_winners_hex"]
        if len(frames) != manifest["frames_requested"]:
            problems.append("frame_count mismatch")
        for index in indices:
            entry = dataset["per_pair"][index]
            if entry["count0"]["p50"] == 0 or entry["count1"]["p50"] == 0:
                problems.append(f"pair {index} zero count")
                break
        if problems:
            errors.append({"boot": manifest["boot_index"], "problems": problems})
            continue
        valid_sessions += 1
        boot_bits = [[0] * len(indices) for _ in range(len(frames))]
        for f, hex_value in enumerate(frames):
            value = int(hex_value, 16)
            boot_frame_errors = 0
            for j, index in enumerate(indices):
                bit = (value >> index) & 1
                boot_bits[f][j] = bit
                if bit != ref_bits[j]:
                    boot_frame_errors += 1
            frame_errors.append(boot_frame_errors)
            if boot_frame_errors > BCH_T:
                failing_frames += 1
        majority = []
        for j in range(len(indices)):
            ones = sum(boot_bits[f][j] for f in range(len(frames)))
            majority.append(1 if ones * 2 > len(frames) else 0)
        boot_errors = sum(1 for j in range(len(indices)) if majority[j] != ref_bits[j])
        boot_majority_errors.append(boot_errors)
        if boot_errors > BCH_T:
            failing_boots += 1
        per_session.append({
            "boot": manifest["boot_index"], "frames": len(frames),
            "boot_majority_errors": boot_errors,
            "max_frame_errors": max(
                (frame_errors[f] for f in range(len(frame_errors) - len(frames),
                                               len(frame_errors))), default=0),
        })
    return {
        "valid_sessions": valid_sessions,
        "frame_errors": frame_errors,
        "boot_majority_errors": boot_majority_errors,
        "failing_frames": failing_frames,
        "failing_boots": failing_boots,
        "per_session": per_session,
        "errors": errors,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mapping", required=True)
    parser.add_argument("--reference", required=True)
    parser.add_argument("--holdout-dir", required=True)
    parser.add_argument("--golden-manifest", required=True)
    parser.add_argument("--report-out", required=True)
    parser.add_argument("--frozen-out", default=None)
    parser.add_argument("--min-boots", type=int, default=10)
    args = parser.parse_args()

    mapping = json.loads(Path(args.mapping).read_text())
    reference = json.loads(Path(args.reference).read_text())
    golden = json.loads(Path(args.golden_manifest).read_text())
    if mapping.get("status") != "TRAIN_SELECTED_NOT_HOLDOUT_QUALIFIED":
        print("BLOCKER: mapping is not a frozen train candidate")
        return 2
    if mapping.get("mapping_tag") not in (0, None):
        print("BLOCKER: mapping_tag already set; holdout already consumed")
        return 2

    sessions = load_holdout(args.holdout_dir)
    if len(sessions) < args.min_boots:
        print(f"BLOCKER: {len(sessions)} holdout sessions, need {args.min_boots}")
        return 2

    result = evaluate(mapping, reference, sessions, golden)
    frame_errors = result["frame_errors"]
    total_frames = len(frame_errors)
    p50 = percentile(frame_errors, 0.50)
    p95 = percentile(frame_errors, 0.95)
    p99 = percentile(frame_errors, 0.99)
    max_err = max(frame_errors) if frame_errors else 0
    frr = result["failing_frames"] / total_frames if total_frames else 1.0
    gate = {
        "holdout_boots_valid": result["valid_sessions"] >= args.min_boots,
        "no_selected_pair_invalid": not result["errors"],
        "no_frame_over_bch": result["failing_frames"] == 0,
        "no_boot_majority_over_bch": result["failing_boots"] == 0,
        "observed_frr_zero": frr == 0.0,
        "p95_le_4": p95 <= P95_GATE,
    }
    passed = all(gate.values())
    report = {
        "frames_observed": total_frames,
        "independent_boots": result["valid_sessions"],
        "p50": p50, "p95": p95, "p99": p99, "max": max_err,
        "frames_over_bch": result["failing_frames"],
        "boots_majority_over_bch": result["failing_boots"],
        "observed_frr": frr,
        "per_session": result["per_session"],
        "validation_errors": result["errors"],
        "gate": gate, "passed": passed,
    }
    Path(args.report_out).parent.mkdir(parents=True, exist_ok=True)
    Path(args.report_out).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")

    if passed and args.frozen_out:
        identity = {
            "protocol": golden.get("protocol"),
            "image_mode": golden.get("image_mode"),
            "topology_id": golden.get("topology_id"),
            "build_id": golden.get("build_id"),
            "num_ro": golden.get("num_ro"),
            "width": golden.get("width"),
            "ref_cycles": golden.get("ref_cycles"),
            "clock_input_hz": golden.get("clock_input_hz"),
            "clock_system_hz": golden.get("clock_system_hz"),
            "bitstream_sha256": golden.get("bitstream_sha256"),
            "route_fingerprint_sha256": golden.get("route_fingerprint_sha256"),
            "pairs": mapping["pairs"],
            "algorithm": mapping["algorithm"],
            "selection_sha256": mapping["selection_sha256"],
        }
        mapping_tag = "0x" + sha256_bytes(canonical_json(identity))[:16]
        frozen = dict(mapping)
        frozen["identity"] = identity
        frozen["mapping_tag"] = mapping_tag
        frozen["status"] = "RELIABILITY_QUALIFIED_ZYNQ_A01_GOLDEN_BITSTREAM"
        frozen["holdout_summary"] = {
            "frames": total_frames, "independent_boots": result["valid_sessions"],
            "p95": p95, "max": max_err, "frr": frr,
        }
        frozen["limitations"] = list(mapping.get("limitations", [])) + [
            "Holdout is power-cycle/time variation on the same ZYNQ-A01 only.",
        ]
        Path(args.frozen_out).write_text(json.dumps(frozen, indent=2, sort_keys=True) + "\n")
        report["mapping_tag"] = mapping_tag

    print(json.dumps(report, indent=2, sort_keys=True))
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
