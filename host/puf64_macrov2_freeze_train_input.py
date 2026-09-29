#!/usr/bin/env python3
"""Freeze and verify the private macro-V2 train input set before selection.

Reads exactly the requested train boots, enforces the frozen V2 context tuple, per-boot
frame count, dataset/raw integrity, then writes a private input manifest with
per-file SHA-256 and an aggregate train-input hash.  The selector consumes this
manifest so selection cannot drift onto a different set of sessions.

Raw responses, datasets and the manifest stay private/git-ignored.  Only the
aggregate hash and its schema/identity are safe to commit.
"""

import argparse
import hashlib
import json
from pathlib import Path
import sys

SCHEMA = "puf64-macrov2-train-input-v1"


def canonical_json(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as source:
        for block in iter(lambda: source.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def session_path(root, campaign, board_id, boot_index):
    return Path(root) / f"{campaign}_{board_id}_{boot_index}.session.json"


def dataset_and_raw(session_file, manifest):
    dataset = Path(manifest["dataset_path"])
    raw = dataset.with_name(dataset.name.replace(".dataset.json", ".raw.json"))
    return dataset, raw


def aggregate_hash(entries):
    return hashlib.sha256(canonical_json(entries)).hexdigest()


def check_device_tuple(device_info, context):
    # Device self-report key -> context manifest key.
    expected_keys = {
        "protocol": "protocol",
        "build_id": "build_id",
        "topology_id": "topology_id",
        "record_bytes": "record_bytes",
        "width": "width",
        "ref_cycles": "ref_cycles",
        "num_ro": "num_ro",
        "pair_count": "pair_count",
        "system_clock_hz": "system_clock_hz",
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


def gather_entries(root, campaign, board_id, build_id, start_boot, end_boot,
                   frames, context):
    entries = []
    errors = []
    for boot in range(start_boot, end_boot + 1):
        path = session_path(root, campaign, board_id, boot)
        if not path.is_file():
            errors.append(f"boot {boot}: session missing")
            continue
        manifest = json.loads(path.read_text())
        if manifest.get("status") != "VALID":
            errors.append(f"boot {boot}: status {manifest.get('status')}")
            continue
        if manifest.get("campaign") != campaign or \
                manifest.get("board_id") != board_id:
            errors.append(f"boot {boot}: campaign/board mismatch")
            continue
        if manifest.get("local_bitstream_sha256") != context["bitstream_sha256"]:
            errors.append(f"boot {boot}: bitstream SHA != context")
            continue
        if manifest.get("frames_received") != frames:
            errors.append(
                f"boot {boot}: frames_received={manifest.get('frames_received')} "
                f"!= {frames}")
            continue
        errors.extend(
            f"boot {boot}: tuple {problem}"
            for problem in check_device_tuple(manifest.get("device_info", {}),
                                              context))
        dataset, raw = dataset_and_raw(path, manifest)
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


def freeze(root, campaign, board_id, build_id, start_boot, end_boot, frames,
           context_path, out_path):
    context = json.loads(Path(context_path).read_text())
    guards = []
    if context.get("board_id") != board_id:
        guards.append(f"context board {context.get('board_id')} != {board_id}")
    if context.get("build_id") != build_id:
        guards.append(f"context build_id {context.get('build_id')} != {build_id}")
    if context.get("protocol") != "3.2":
        guards.append(f"unexpected protocol {context.get('protocol')}")
    if not context.get("train_eligible"):
        guards.append("context manifest train_eligible is not true")
    if context.get("holdout_eligible"):
        guards.append("holdout_eligible must stay false before selection")
    if guards:
        print("BLOCKER: train input preflight failed:")
        for guard in guards:
            print(f"  - {guard}")
        return 2

    entries, errors = gather_entries(
        root, campaign, board_id, build_id, start_boot, end_boot, frames, context)
    boot_indices = [entry["boot_index"] for entry in entries]
    if len(boot_indices) != len(set(boot_indices)):
        errors.append("duplicate boot_index in train input")
    expected = list(range(start_boot, end_boot + 1))
    if boot_indices != expected:
        errors.append(
            f"boot set mismatch: got {boot_indices} expected {expected}")
    if any(b in range(401, 411) for b in boot_indices):
        errors.append("holdout boot leaked into train input")
    if any(b in range(101, 121) or b in range(201, 211) for b in boot_indices):
        errors.append("golden-campaign boot leaked into V2 train input")
    if errors:
        print("BLOCKER: train input preflight failed:")
        for error in errors:
            print(f"  - {error}")
        return 2

    manifest = {
        "schema": SCHEMA,
        "campaign": campaign,
        "board_id": board_id,
        "build_id": build_id,
        "protocol": context.get("protocol"),
        "image_mode_code": context.get("image_mode_code"),
        "topology_id": context.get("topology_id"),
        "num_ro": context.get("num_ro"),
        "pair_count": context.get("pair_count"),
        "width": context.get("width"),
        "ref_cycles": context.get("ref_cycles"),
        "clock_system_hz": context.get("system_clock_hz"),
        "clock_input_hz": context.get("input_clock_hz"),
        "bitstream_sha256": context.get("bitstream_sha256"),
        "macro_dcp_sha256": context.get("macro_dcp_sha256"),
        "fingerprint_sha256": context.get("fingerprint_sha256"),
        "char_dcp_sha256": context.get("char_dcp_sha256"),
        "context_manifest_sha256": sha256_file(context_path),
        "frames_per_boot": frames,
        "boots": entries,
        "aggregate_sha256": aggregate_hash(entries),
    }
    out = Path(out_path)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(json.dumps({
        "status": "FROZEN",
        "output": str(out),
        "boots": len(entries),
        "aggregate_sha256": manifest["aggregate_sha256"],
    }, indent=2))
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--campaign-dir", required=True)
    parser.add_argument("--campaign", default="train")
    parser.add_argument("--board-id", required=True)
    parser.add_argument("--build-id", type=int, required=True)
    parser.add_argument("--start-boot", type=int, default=301)
    parser.add_argument("--end-boot", type=int, default=320)
    parser.add_argument("--frames", type=int, default=50)
    parser.add_argument("--context-manifest", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args(argv)
    return freeze(args.campaign_dir, args.campaign, args.board_id,
                  args.build_id, args.start_boot, args.end_boot, args.frames,
                  args.context_manifest, args.out)


if __name__ == "__main__":
    sys.exit(main())
