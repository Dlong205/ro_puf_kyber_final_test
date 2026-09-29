#!/usr/bin/env python3
"""Freeze the private macro-V2 holdout input set before evaluation.

Reads exactly the holdout boots 201..210, enforces the context tuple, per-boot
frame count and dataset/raw integrity, binds the frozen holdout candidate
(mapping/selection/train-input/reference hashes), then writes an immutable
private manifest with per-file SHA-256 and an aggregate holdout-input hash.

The evaluator must consume this manifest; there is no glob fallback.  Any drift
is a hard blocker and the artifact is never overwritten.
"""

import argparse
import hashlib
import json
from pathlib import Path
import stat
import sys

SCHEMA = "puf64-macrov2-holdout-input-v1"


def canonical_json(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as source:
        for block in iter(lambda: source.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def session_path(root, board_id, boot_index):
    return Path(root) / f"holdout_{board_id}_{boot_index}.session.json"


def check_device_tuple(device_info, context):
    expected_keys = {
        "protocol": "protocol", "build_id": "build_id",
        "topology_id": "topology_id", "record_bytes": "record_bytes",
        "width": "width", "ref_cycles": "ref_cycles", "num_ro": "num_ro",
        "pair_count": "pair_count", "system_clock_hz": "system_clock_hz",
        "input_clock_hz": "input_clock_hz",
        "macro_dcp_sha256": "macro_dcp_sha256",
        "fingerprint_sha256": "fingerprint_sha256",
    }
    problems = []
    for device_key, context_key in expected_keys.items():
        if device_info.get(device_key) != context.get(context_key):
            problems.append(
                f"{device_key}: device={device_info.get(device_key)} "
                f"context={context.get(context_key)}")
    if device_info.get("mmcm_locked") != 1:
        problems.append("MMCM not locked")
    if device_info.get("image_mode_code", device_info.get("image_mode")) != \
            context.get("image_mode_code"):
        problems.append("image_mode mismatch")
    return problems


def gather_entries(root, board_id, start_boot, end_boot, frames, context):
    entries = []
    errors = []
    for boot in range(start_boot, end_boot + 1):
        path = session_path(root, board_id, boot)
        if not path.is_file():
            errors.append(f"boot {boot}: session missing")
            continue
        manifest = json.loads(path.read_text())
        if manifest.get("status") != "VALID":
            errors.append(f"boot {boot}: status {manifest.get('status')}")
            continue
        if manifest.get("campaign") != "holdout" or \
                manifest.get("board_id") != board_id:
            errors.append(f"boot {boot}: campaign/board mismatch")
            continue
        if manifest.get("build_id") != context.get("build_id"):
            errors.append(f"boot {boot}: build_id mismatch")
            continue
        if manifest.get("local_bitstream_sha256") != context.get("bitstream_sha256"):
            errors.append(f"boot {boot}: bitstream SHA != context")
            continue
        if manifest.get("frames_received") != frames:
            errors.append(
                f"boot {boot}: frames_received={manifest.get('frames_received')} "
                f"!= {frames}")
            continue
        if manifest.get("duplicate_frame_count") not in (0, None):
            errors.append(f"boot {boot}: duplicate frames present")
            continue
        errors.extend(
            f"boot {boot}: tuple {problem}"
            for problem in check_device_tuple(manifest.get("device_info", {}),
                                              context))
        dataset = Path(manifest["dataset_path"])
        raw = dataset.with_name(dataset.name.replace(".dataset.json", ".raw.json"))
        if not dataset.is_file():
            errors.append(f"boot {boot}: dataset missing {dataset}")
            continue
        if not raw.is_file():
            errors.append(f"boot {boot}: raw missing {raw}")
            continue
        dataset_sha = sha256_file(dataset)
        if dataset_sha != manifest.get("parsed_dataset_sha256"):
            errors.append(f"boot {boot}: dataset SHA mismatch")
            continue
        dataset_json = json.loads(dataset.read_text())
        if len(dataset_json.get("per_pair", [])) != context["pair_count"]:
            errors.append(f"boot {boot}: dataset pair_count mismatch")
            continue
        entries.append({
            "boot_index": boot,
            "session_uuid": manifest.get("session_uuid"),
            "session_path": str(path.resolve()),
            "dataset_path": str(dataset.resolve()),
            "raw_path": str(raw.resolve()),
            "session_sha256": sha256_file(path),
            "dataset_sha256": dataset_sha,
            "raw_sha256": sha256_file(raw),
        })
    return entries, errors


def build_manifest(root, board_id, start_boot, end_boot, frames, context_path,
                   candidate_path, mapping_path, reference_path, train_input_path):
    context = json.loads(Path(context_path).read_text())
    candidate = json.loads(Path(candidate_path).read_text())
    train_input = json.loads(Path(train_input_path).read_text())

    problems = []
    if not context.get("holdout_eligible"):
        problems.append("context holdout_eligible is not true")
    if context.get("protocol") != "3.2":
        problems.append(f"unexpected protocol {context.get('protocol')}")
    if candidate.get("schema") != "puf64-macrov2-holdout-candidate-v1":
        problems.append("candidate schema mismatch")
    if candidate.get("mapping_file_sha256") != sha256_file(mapping_path):
        problems.append("candidate mapping file SHA mismatch")
    if candidate.get("reference_file_sha256") != sha256_file(reference_path):
        problems.append("candidate reference file SHA mismatch")
    if candidate.get("train_input_aggregate_sha256") != \
            train_input.get("aggregate_sha256"):
        problems.append("candidate train-input hash mismatch")
    if context.get("build_id") != 3:
        problems.append("context is not macro-V2 build 3")

    entries, errors = gather_entries(
        root, board_id, start_boot, end_boot, frames, context)
    problems.extend(errors)
    expected = list(range(start_boot, end_boot + 1))
    if [entry["boot_index"] for entry in entries] != expected:
        problems.append("holdout boot set is incomplete or out of order")
    if problems:
        print("BLOCKER: holdout input preflight failed:")
        for problem in problems:
            print(f"  - {problem}")
        return None

    return {
        "schema": SCHEMA,
        "campaign": "holdout",
        "board_id": board_id,
        "protocol": context.get("protocol"),
        "build_id": context.get("build_id"),
        "image_mode_code": context.get("image_mode_code"),
        "topology_id": context.get("topology_id"),
        "record_bytes": context.get("record_bytes"),
        "width": context.get("width"),
        "ref_cycles": context.get("ref_cycles"),
        "num_ro": context.get("num_ro"),
        "pair_count": context.get("pair_count"),
        "bitstream_sha256": context.get("bitstream_sha256"),
        "macro_dcp_sha256": context.get("macro_dcp_sha256"),
        "fingerprint_sha256": context.get("fingerprint_sha256"),
        "char_dcp_sha256": context.get("char_dcp_sha256"),
        "context_manifest_sha256": sha256_file(context_path),
        "candidate_mapping_file_sha256": candidate.get("mapping_file_sha256"),
        "candidate_selection_sha256": candidate.get("selection_sha256"),
        "train_input_aggregate_sha256":
            candidate.get("train_input_aggregate_sha256"),
        "train_reference_file_sha256": candidate.get("reference_file_sha256"),
        "frames_per_boot": frames,
        "boots": entries,
        "aggregate_sha256": hashlib.sha256(canonical_json(entries)).hexdigest(),
    }


def write_private(path, text):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    path.chmod(stat.S_IRUSR | stat.S_IWUSR)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--campaign-dir", required=True)
    parser.add_argument("--board-id", required=True)
    parser.add_argument("--start-boot", type=int, default=401)
    parser.add_argument("--end-boot", type=int, default=410)
    parser.add_argument("--frames", type=int, default=50)
    parser.add_argument("--context-manifest", required=True)
    parser.add_argument("--holdout-candidate", required=True)
    parser.add_argument("--mapping", required=True)
    parser.add_argument("--reference", required=True)
    parser.add_argument("--train-input", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args(argv)

    manifest = build_manifest(
        args.campaign_dir, args.board_id, args.start_boot, args.end_boot,
        args.frames, args.context_manifest, args.holdout_candidate,
        args.mapping, args.reference, args.train_input)
    if manifest is None:
        return 2

    out = Path(args.out)
    if out.exists():
        existing = json.loads(out.read_text())
        if canonical_json(existing) != canonical_json(manifest):
            print("BLOCKER: existing holdout input differs; refusing to "
                  "overwrite an immutable artifact")
            return 2
        print(json.dumps({
            "status": "VERIFY_PASS", "output": str(out),
            "aggregate_sha256": manifest["aggregate_sha256"],
        }, indent=2))
        return 0
    write_private(out, json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(json.dumps({
        "status": "FROZEN", "output": str(out),
        "boots": len(manifest["boots"]),
        "aggregate_sha256": manifest["aggregate_sha256"],
    }, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
