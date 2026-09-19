#!/usr/bin/env python3
"""PUF64 train/holdout session acquisition with freshness and validation.

Collects one power-cycle session (fixed frame count) from the diagnosed golden
characterization image, enforces the full golden tuple, validates every frame,
and writes private session manifest + parsed dataset + raw per-frame winners.

No RTL/XDC/INFO/bitstream changes. Raw data stays in a private, git-ignored
directory.
"""

import argparse
import datetime
import hashlib
import json
from pathlib import Path
import sys
import time
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parent))
import puf_allpairs_characterize as PUF  # noqa: E402

FRAME_LIMIT_COUNT = 60000
GOLDEN_TUPLE_KEYS = (
    "protocol", "image_mode_code", "topology_id", "build_id",
    "ref_cycles", "system_clock_hz", "input_clock_hz", "width",
    "num_ro", "pair_count",
)


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as source:
        for block in iter(lambda: source.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def canonical_json(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def now_utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def verify_board_id(board_id, golden):
    if board_id != golden.get("board_id"):
        return [f"board_id {board_id} != golden {golden.get('board_id')}"]
    return []


def verify_device_info(info, golden):
    errors = []
    for key in GOLDEN_TUPLE_KEYS:
        expected = golden.get(key)
        if key == "image_mode_code":
            expected = golden.get("image_mode_code")
        if expected is None:
            continue
        actual = info.get(key)
        if actual != expected:
            errors.append(f"{key}: device={actual} golden={expected}")
    if info.get("mmcm_locked") != 1:
        errors.append("MMCM not locked")
    return errors


def frames_to_winners(measurements, pair_count):
    hexes = []
    for frame in measurements:
        value = 0
        for index, record in enumerate(frame):
            if record[2]:
                value |= (1 << index)
        hexes.append(value.to_bytes((pair_count + 7) // 8, "big").hex())
    return hexes


def raw_payload_sha(measurements):
    digest = hashlib.sha256()
    for frame in measurements:
        for record in frame:
            digest.update(canonical_json(list(record)))
    return digest.hexdigest()


def validate_measurements(measurements, frames_requested, golden):
    errors = []
    pair_count = golden["pair_count"]
    ro_count = golden["num_ro"]
    pairs = PUF.canonical_pairs(ro_count)
    if len(measurements) != frames_requested:
        errors.append(f"frames: requested {frames_requested}, got {len(measurements)}")
    for f_index, frame in enumerate(measurements):
        if len(frame) != pair_count:
            errors.append(f"frame {f_index}: {len(frame)} records, expected {pair_count}")
            continue
        seen = set()
        for index, record in enumerate(frame):
            a, b, winner, tie, count0, count1, margin = record
            if (a, b) in seen:
                errors.append(f"frame {f_index}: duplicate pair ({a},{b})")
                break
            seen.add((a, b))
            if (a, b) != pairs[index]:
                errors.append(f"frame {f_index} pair {index}: ({a},{b}) not canonical")
                break
            if a >= b or b >= ro_count:
                errors.append(f"frame {f_index} pair {index}: invalid endpoints")
                break
            if count0 == 0 or count1 == 0:
                errors.append(f"frame {f_index} pair {index}: zero count")
                break
            if count0 >= FRAME_LIMIT_COUNT or count1 >= FRAME_LIMIT_COUNT:
                errors.append(f"frame {f_index} pair {index}: count near wrap")
                break
            if margin != abs(count0 - count1):
                errors.append(f"frame {f_index} pair {index}: margin incoherent")
                break
            if tie != int(count0 == count1):
                errors.append(f"frame {f_index} pair {index}: tie flag incoherent")
                break
    if measurements and len(measurements[0]) == pair_count:
        if tuple(measurements[0][0][:2]) != pairs[0]:
            errors.append("first pair is not (0,1)")
        if tuple(measurements[0][-1][:2]) != pairs[-1]:
            errors.append(f"last pair is not {pairs[-1]}")
    return errors


def load_sessions(outdir):
    sessions = []
    for path in sorted(Path(outdir).glob("*.session.json")):
        try:
            sessions.append((path, json.loads(path.read_text())))
        except (OSError, json.JSONDecodeError):
            continue
    return sessions


def freshness_check(sessions, campaign, board_id, boot_index, session_id, raw_sha):
    errors = []
    warnings = []
    for path, manifest in sessions:
        key = (manifest.get("board_id"), manifest.get("campaign"),
               manifest.get("boot_index"))
        if key == (board_id, campaign, boot_index):
            errors.append(f"duplicate session key {key} already in {Path(path).name}")
        if manifest.get("session_uuid") == session_id:
            errors.append(f"duplicate session UUID in {Path(path).name}")
        if manifest.get("raw_payload_sha256") == raw_sha:
            warnings.append(
                f"raw payload hash equals {Path(path).name}; PUF can be very stable, "
                "verify transcript/timestamps"
            )
    return errors, warnings


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--campaign", required=True, choices=["train", "holdout"])
    parser.add_argument("--board-id", required=True)
    parser.add_argument("--boot-index", required=True, type=int)
    parser.add_argument("--port", required=True)
    parser.add_argument("--bitstream", required=True)
    parser.add_argument("--golden-manifest", required=True)
    parser.add_argument("--frames", type=int, default=50)
    parser.add_argument("--timeout", type=float, default=15.0)
    parser.add_argument("--condition-id", default="UNSPECIFIED")
    parser.add_argument("--outdir", required=True)
    parser.add_argument("--operator-power-cycle", action="store_true")
    parser.add_argument("--power-off-wait", type=float, default=15.0)
    parser.add_argument("--warmup", type=float, default=30.0)
    args = parser.parse_args()

    if args.boot_index <= 0:
        parser.error("boot index must be positive")
    if not args.operator_power_cycle:
        parser.error("--operator-power-cycle is required for a real cold boot")

    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    golden_path = Path(args.golden_manifest).resolve()
    golden = json.loads(golden_path.read_text())
    golden_sha = sha256_file(golden_path)

    bitstream_sha = sha256_file(args.bitstream)
    errors = verify_board_id(args.board_id, golden)
    if bitstream_sha != golden["bitstream_sha256"]:
        errors.append(
            f"local bitstream {bitstream_sha} != golden {golden['bitstream_sha256']}"
        )

    session_id = str(uuid.uuid4())
    started = now_utc()
    all_errors = list(errors)
    warnings = []
    device_info = {}
    measurements = []
    if not errors:
        try:
            measurements, elapsed, device_info = PUF.collect(
                args.port, args.frames, args.timeout, golden["num_ro"]
            )
        except Exception as error:  # noqa: BLE001
            all_errors.append(f"acquisition failed: {error}")
        else:
            tuple_errors = verify_device_info(device_info, golden)
            all_errors.extend(tuple_errors)
            all_errors.extend(validate_measurements(measurements, args.frames, golden))

    raw_sha = raw_payload_sha(measurements) if measurements else ""
    sessions = load_sessions(outdir)
    fresh_errors, fresh_warnings = freshness_check(
        sessions, args.campaign, args.board_id, args.boot_index, session_id, raw_sha
    )
    all_errors.extend(fresh_errors)
    warnings.extend(fresh_warnings)

    parsed = None
    dataset_path = None
    if measurements and not all_errors:
        parsed = PUF.analyze(
            measurements, [4], 1.0, ro_count=golden["num_ro"],
            pair_count=golden["pair_count"],
        )
        parsed["campaign"] = {
            "campaign": args.campaign, "board_id": args.board_id,
            "boot_index": args.boot_index, "condition_id": args.condition_id,
            "session_uuid": session_id, "device_info": device_info,
        }
        winners = frames_to_winners(measurements, golden["pair_count"])
        dataset_path = outdir / f"{args.campaign}_{args.board_id}_{args.boot_index}.dataset.json"
        dataset_path.write_text(json.dumps(parsed, indent=2, sort_keys=True) + "\n")
        raw_path = outdir / f"{args.campaign}_{args.board_id}_{args.boot_index}.raw.json"
        raw_path.write_text(json.dumps({
            "frames_winners_hex": winners,
            "frame_count": len(winners),
            "pair_count": golden["pair_count"],
        }, indent=2, sort_keys=True) + "\n")

    status = "VALID" if not all_errors else "INVALID"
    manifest = {
        "campaign": args.campaign, "board_id": args.board_id,
        "boot_index": args.boot_index, "session_uuid": session_id,
        "condition_id": args.condition_id,
        "host_start_utc": started, "host_end_utc": now_utc(),
        "operator_power_cycle_confirmed": bool(args.operator_power_cycle),
        "power_off_wait_s": args.power_off_wait, "warmup_s": args.warmup,
        "serial_device": args.port,
        "golden_manifest_path": str(golden_path),
        "golden_manifest_sha256": golden_sha,
        "local_bitstream_sha256": bitstream_sha,
        "device_info": device_info,
        "host_tooling_commit": PUF.git_commit_hash(),
        "frames_requested": args.frames,
        "frames_received": len(measurements),
        "raw_payload_sha256": raw_sha,
        "parsed_dataset_sha256": sha256_file(dataset_path) if dataset_path else "",
        "dataset_path": str(dataset_path) if dataset_path else "",
        "status": status, "errors": all_errors, "warnings": warnings,
    }
    manifest_path = outdir / f"{args.campaign}_{args.board_id}_{args.boot_index}.session.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")

    print(json.dumps({
        "status": status, "manifest": str(manifest_path),
        "frames": len(measurements), "errors": all_errors, "warnings": warnings,
    }, indent=2))
    return 0 if status == "VALID" else 1


if __name__ == "__main__":
    sys.exit(main())
