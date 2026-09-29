#!/usr/bin/env python3
"""Predeclare R6 holdout criteria using only frozen pilot/train evidence."""

import hashlib
import json
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "host"))
from puf64_mapping_v2_generated import ORDERED_PAIRS  # noqa: E402
from puf64_qual_freeze_train import BASE, OUTPUT as FREEZE, digest, require  # noqa: E402

OUTPUT = BASE / "holdout_authorization_601_610.json"
FRAMES_PER_BOOT = 50
BOOTS = tuple(range(601, 611))


def frame_paths(directory, count):
    return [directory / f"frame_{n:03d}.json" for n in range(1, count + 1)]


def selected(frame):
    lookup = {(p["a"], p["b"]): p for p in frame["pairs"]}
    require(len(lookup) == 2016, "incomplete pair lookup")
    return [lookup[pair] for pair in ORDERED_PAIRS]


def main():
    freeze = json.loads(FREEZE.read_text())
    require(freeze["status"] == "TRAIN_INPUT_FROZEN_HOLDOUT_BLOCKED"
            and freeze["train_boot_count"] == 20
            and freeze["train_frame_count"] == 100,
            "train input not frozen")
    require(len(ORDERED_PAIRS) == 264 and len(set(ORDERED_PAIRS)) == 264,
            "unexpected selected mapping")
    pilot_dir = BASE / "pilot_ZYNQ-A01_502"
    require(digest(pilot_dir / "session.json") == freeze["pilot_session_sha256"],
            "pilot changed")
    pilot = json.loads((pilot_dir / "session.json").read_text())
    pilot_votes = [[] for _ in ORDERED_PAIRS]
    for path, entry in zip(frame_paths(pilot_dir, 50), pilot["frames"]):
        require(digest(path) == entry["sha256"], "pilot frame changed")
        for i, pair in enumerate(selected(json.loads(path.read_text()))):
            require(not pair["tie"] and pair["valid"] == 1,
                    f"pilot selected tie/invalid {i}")
            pilot_votes[i].append(pair["winner"])
    reference = []
    for i, votes in enumerate(pilot_votes):
        require(len(votes) == 50 and len(set(votes)) == 1,
                f"pilot selected drift {i}")
        reference.append(votes[0])
    min_margin = None
    below_4 = set()
    for row in freeze["train_boots"]:
        boot = row["boot_index"]
        directory = BASE / f"train_ZYNQ-A01_{boot}"
        require(digest(directory / "session.json") == row["session_sha256"],
                f"train session changed {boot}")
        for path, expected in zip(frame_paths(directory, 5), row["frame_sha256"]):
            require(digest(path) == expected, f"train frame changed {path}")
            for i, pair in enumerate(selected(json.loads(path.read_text()))):
                require(not pair["tie"] and pair["valid"] == 1
                        and pair["winner"] == reference[i],
                        f"selected mismatch {path}/{i}")
                margin = pair["margin"]
                min_margin = margin if min_margin is None else min(min_margin, margin)
                if margin < 4:
                    below_4.add(i)
    require(min_margin == 2 and len(below_4) == 3,
            "train margin observation changed")
    # Reference bits are private device-response material; never put this file
    # in source control.  The public protocol document records only thresholds.
    payload = {
        "schema": "r6-operational-holdout-authorization-v1",
        "status": "HOLDOUT_AUTHORIZED_QUAL_IMAGE_ONLY",
        "train_freeze_sha256": digest(FREEZE),
        "bitstream_sha256": freeze["identity"]["bitstream_sha256"],
        "board_id": freeze["identity"]["board_id"],
        "mapping_tag": "0x81b5",
        "mapping_ordered_pairs_sha256": hashlib.sha256(
            json.dumps(ORDERED_PAIRS, separators=(",", ":")).encode()
        ).hexdigest(),
        "reference_bits": reference,
        "train_selected_min_margin": min_margin,
        "train_selected_pairs_ever_below_margin_4": len(below_4),
        "holdout_boot_indices": BOOTS,
        "frames_per_boot": FRAMES_PER_BOOT,
        "acceptance": {
            "valid_cold_boots": 10,
            "valid_frames": 500,
            "max_selected_bit_errors_per_frame": 8,
            "max_selected_bit_errors_per_boot_majority": 8,
            "p95_selected_bit_errors": 4,
            "max_bch_corrections": 8,
            "fe_kcv_failures": 0,
            "public_key_mismatches": 0,
            "selected_ties": 0,
            "invalid_timeout_overflow_countzero": 0,
            "qualification_info": "4541010171",
        },
        "note": "Authorization is for independent holdout collection, not final release.",
    }
    content = json.dumps(payload, indent=2, sort_keys=True) + "\n"
    if OUTPUT.exists():
        require(OUTPUT.read_text() == content, "holdout authorization differs")
        print(f"R6_HOLDOUT_AUTHORIZATION_RECHECK_PASS {digest(OUTPUT)}")
    else:
        with OUTPUT.open("x") as handle:
            handle.write(content)
        print(f"R6_HOLDOUT_AUTHORIZED {digest(OUTPUT)}")
    print(f"boots={len(BOOTS)} frames={len(BOOTS)*FRAMES_PER_BOOT} "
          f"train_min_margin={min_margin} train_pairs_below4={len(below_4)}")


if __name__ == "__main__":
    main()
