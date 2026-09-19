#!/usr/bin/env python3
"""Freeze the private holdout candidate before any holdout boot.

Binds the accepted train selection to a single immutable manifest: golden
bitstream/identity, train boots and aggregate train-input hash, mapping file
SHA-256, selection hash, selection-report SHA-256, private reference SHA-256,
ordered 264 pairs, degree vector, algorithm/config and status.

Re-running with the same inputs verifies the existing artifact is identical and
never overwrites it.  Any change is a hard blocker.

The manifest and all referenced artifacts stay private/git-ignored; only the
selection/mapping hashes are mirrored into the golden manifest closure.
"""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import stat
import sys

SCHEMA = "puf64-holdout-candidate-v1"


def canonical_json(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as source:
        for block in iter(lambda: source.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def build_payload(mapping_path, reference_path, report_path, train_input_path,
                  golden_path, require_closed=True):
    mapping = json.loads(Path(mapping_path).read_text())
    reference = json.loads(Path(reference_path).read_text())
    report = json.loads(Path(report_path).read_text())
    train_input = json.loads(Path(train_input_path).read_text())
    golden = json.loads(Path(golden_path).read_text())

    problems = []
    if not golden.get("train_eligible"):
        problems.append("golden train_eligible is not true")
    if require_closed and golden.get("holdout_eligible"):
        problems.append("holdout must still be closed while freezing")
    if golden.get("protocol") != "3.1":
        problems.append(f"unexpected protocol {golden.get('protocol')}")
    if mapping.get("status") != "TRAIN_SELECTED_NOT_HOLDOUT_QUALIFIED":
        problems.append("mapping status is not the frozen train candidate")
    if mapping.get("mapping_tag") != 0:
        problems.append("mapping_tag must be 0 at freeze")
    selection = mapping.get("selection_sha256")
    if not selection:
        problems.append("mapping has no selection_sha256")
    if reference.get("selection_sha256") != selection:
        problems.append("reference selection hash != mapping selection hash")
    if report.get("selection_sha256") != selection:
        problems.append("selection report hash != mapping selection hash")
    if train_input.get("aggregate_sha256") != mapping.get("train_input_sha256"):
        problems.append("train-input aggregate != mapping train_input_sha256")
    if train_input.get("bitstream_sha256") != golden.get("bitstream_sha256"):
        problems.append("train-input bitstream != golden bitstream")
    pairs = mapping.get("pairs", [])
    indices = mapping.get("source_pair_indices", [])
    degree = mapping.get("ro_degree", [])
    if len(pairs) != 264 or len(indices) != 264:
        problems.append(
            f"expected 264 selected pairs, got pairs={len(pairs)} "
            f"indices={len(indices)}")
    if len(degree) != golden.get("num_ro"):
        problems.append("degree vector size != num_ro")
    if len(set(indices)) != len(indices):
        problems.append("duplicate source_pair_indices")
    if problems:
        print("BLOCKER: holdout candidate freeze failed:")
        for problem in problems:
            print(f"  - {problem}")
        return None

    return {
        "schema": SCHEMA,
        "status": "TRAIN_SELECTED_NOT_HOLDOUT_QUALIFIED",
        "mapping_tag": 0,
        "board_id": golden.get("board_id"),
        "protocol": golden.get("protocol"),
        "build_id": golden.get("build_id"),
        "image_mode_code": golden.get("image_mode_code"),
        "topology_id": golden.get("topology_id"),
        "record_bytes": golden.get("record_bytes"),
        "width": golden.get("width"),
        "ref_cycles": golden.get("ref_cycles"),
        "num_ro": golden.get("num_ro"),
        "pair_count": golden.get("pair_count"),
        "bitstream_sha256": golden.get("bitstream_sha256"),
        "route_fingerprint_sha256": golden.get("route_fingerprint_sha256"),
        "train_boots": mapping.get("train_boots"),
        "train_input_aggregate_sha256": train_input.get("aggregate_sha256"),
        "mapping_file_sha256": sha256_file(mapping_path),
        "selection_sha256": selection,
        "selection_report_sha256": sha256_file(report_path),
        "reference_file_sha256": sha256_file(reference_path),
        "ordered_pairs": pairs,
        "source_pair_indices": indices,
        "ro_degree": degree,
        "algorithm": mapping.get("algorithm"),
        "config": mapping.get("config"),
        "limitations": mapping.get("limitations"),
    }


def write_private(path, text):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    path.chmod(stat.S_IRUSR | stat.S_IWUSR)


def backup(backup_dir, files):
    backup_dir = Path(backup_dir)
    backup_dir.mkdir(parents=True, exist_ok=True)
    backup_dir.chmod(stat.S_IRWXU)
    lines = []
    for label, path in files.items():
        target = backup_dir / Path(path).name
        shutil.copy2(path, target)
        target.chmod(stat.S_IRUSR | stat.S_IWUSR)
        lines.append(f"{sha256_file(target)}  {target.name}  ({label})")
    checksum = backup_dir / "SHA256SUMS"
    checksum.write_text("\n".join(lines) + "\n")
    checksum.chmod(stat.S_IRUSR | stat.S_IWUSR)
    return backup_dir


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mapping", required=True)
    parser.add_argument("--reference", required=True)
    parser.add_argument("--selection-report", required=True)
    parser.add_argument("--train-input", required=True)
    parser.add_argument("--golden-manifest", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--backup-dir", default=None)
    args = parser.parse_args(argv)

    out = Path(args.out)
    payload = build_payload(
        args.mapping, args.reference, args.selection_report, args.train_input,
        args.golden_manifest, require_closed=not out.exists())
    if payload is None:
        return 2
    if out.exists():
        existing = json.loads(out.read_text())
        if canonical_json(existing) != canonical_json(payload):
            print("BLOCKER: existing holdout candidate differs; refusing to "
                  "overwrite an immutable artifact")
            print(json.dumps({
                "existing": existing.get("selection_sha256"),
                "recomputed": payload.get("selection_sha256"),
                "existing_mapping_sha256": existing.get("mapping_file_sha256"),
                "recomputed_mapping_sha256": payload.get("mapping_file_sha256"),
            }, indent=2))
            return 2
        print(json.dumps({
            "status": "VERIFY_PASS",
            "output": str(out),
            "selection_sha256": payload["selection_sha256"],
            "mapping_file_sha256": payload["mapping_file_sha256"],
        }, indent=2))
    else:
        write_private(out, json.dumps(payload, indent=2, sort_keys=True) + "\n")
        print(json.dumps({
            "status": "FROZEN",
            "output": str(out),
            "selection_sha256": payload["selection_sha256"],
            "mapping_file_sha256": payload["mapping_file_sha256"],
            "train_input_aggregate_sha256":
                payload["train_input_aggregate_sha256"],
        }, indent=2))

    if args.backup_dir:
        files = {
            "holdout_candidate": args.out,
            "train_mapping_candidate": args.mapping,
            "train_reference_private": args.reference,
            "train_selection_report": args.selection_report,
            "train_input": args.train_input,
        }
        destination = backup(args.backup_dir, files)
        print(json.dumps({"backup": str(destination)}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
