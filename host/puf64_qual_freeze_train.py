#!/usr/bin/env python3
"""Freeze the R6 operational cold-train input without authorizing holdout."""

import hashlib
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "reports/puf64_operational_native_campaign"
OUTPUT = BASE / "train_input_503_522.frozen.json"
IDENTITY = (
    "board_id", "bitstream_sha256", "macro_dcp_sha256",
    "frozen_macro_fingerprint_sha256", "influence_fingerprint_sha256",
    "helper_record_sha256", "public_key_sha256", "qual_info",
)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def main():
    pilot_path = BASE / "pilot_ZYNQ-A01_502/session.json"
    pilot = json.loads(pilot_path.read_text())
    require(pilot["status"] == "VALID" and len(pilot["frames"]) == 50,
            "pilot 502 is not valid/complete")
    require(pilot["campaign"] == "pilot" and pilot["boot_index"] == 502,
            "wrong pilot identity")
    rows = []
    tags = set()
    total_ties = 0
    overrun = 0
    for boot in range(503, 523):
        directory = BASE / f"train_ZYNQ-A01_{boot}"
        session_path = directory / "session.json"
        session = json.loads(session_path.read_text())
        require(session["schema"] == "r6-operational-cold-boot-v1"
                and session["campaign"] == "train"
                and session["boot_index"] == boot
                and session["status"] == "VALID"
                and session["frames_requested"] == 5
                and len(session["frames"]) == 5,
                f"invalid train session {boot}")
        require(all(session[key] == pilot[key] for key in IDENTITY),
                f"pilot identity mismatch {boot}")
        frame_hashes = []
        for ordinal, entry in enumerate(session["frames"], 1):
            path = directory / f"frame_{ordinal:03d}.json"
            require(digest(path) == entry["sha256"],
                    f"frame SHA mismatch {boot}/{ordinal}")
            frame = json.loads(path.read_text())
            require(entry["ordinal"] == ordinal
                    and entry["frame_seq"] == ordinal
                    and frame["frame_seq"] == ordinal
                    and frame["boot_index"] == boot
                    and frame["info"] == pilot["qual_info"]
                    and frame["entry_count"] == 2016
                    and len(frame["pairs"]) == 2016,
                    f"frame shape mismatch {boot}/{ordinal}")
            require(entry["bch_corr"] == 0
                    and entry["pk_sha256"] == pilot["public_key_sha256"],
                    f"E2E mismatch {boot}/{ordinal}")
            require(entry["result_tag"] not in tags,
                    f"duplicate result tag {boot}/{ordinal}")
            tags.add(entry["result_tag"])
            require(sum(bool(pair["tie"]) for pair in frame["pairs"])
                    == entry["ties"], f"tie count mismatch {boot}/{ordinal}")
            require(all(pair["valid"] == 1 and pair["timeout"] == 0
                        and pair["ovf_a"] == 0 and pair["ovf_b"] == 0
                        for pair in frame["pairs"]),
                    f"invalid pair {boot}/{ordinal}")
            total_ties += entry["ties"]
            overrun += bool(entry["overrun"])
            frame_hashes.append(entry["sha256"])
        rows.append({"boot_index": boot, "session_sha256": digest(session_path),
                     "frame_sha256": frame_hashes})
    manifest = {
        "schema": "r6-operational-train-input-freeze-v1",
        "status": "TRAIN_INPUT_FROZEN_HOLDOUT_BLOCKED",
        "pilot_boot_index": 502,
        "pilot_session_sha256": digest(pilot_path),
        "identity": {key: pilot[key] for key in IDENTITY},
        "train_boots": rows,
        "train_boot_count": len(rows),
        "train_frame_count": len(tags),
        "bch_corrections": 0,
        "full_pool_tie_events": total_ties,
        "conservative_overrun_flags": overrun,
        "note": "This freezes inputs only; no holdout authorization or release claim.",
    }
    payload = json.dumps(manifest, indent=2, sort_keys=True) + "\n"
    if OUTPUT.exists():
        require(OUTPUT.read_text() == payload, "existing freeze differs; refusing overwrite")
        print(f"R6_TRAIN_INPUT_FREEZE_RECHECK_PASS {digest(OUTPUT)}")
    else:
        with OUTPUT.open("x") as handle:
            handle.write(payload)
        print(f"R6_TRAIN_INPUT_FROZEN_HOLDOUT_BLOCKED {digest(OUTPUT)}")
    print(f"boots={len(rows)} frames={len(tags)} ties={total_ties} overrun={overrun}")


if __name__ == "__main__":
    main()
