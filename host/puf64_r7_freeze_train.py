#!/usr/bin/env python3
"""R7 train-input freeze: pilot 703 + train 704-723 through the final path.

Verifies exact boot/frame counts, 2016 pairs per frame, per-file SHA-256,
then writes the private frozen manifest with an aggregate hash. A second
computation must reproduce the same aggregate (determinism gate). Private,
git-ignored; only the aggregate hash may be quoted.
"""
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CAMPAIGN = ROOT / "reports/puf64_finalchar_campaign"
OUT = CAMPAIGN / "r7_train_input_703_723.frozen.json"
PILOT = ("pilot_ZYNQ-A01_703", 50)
TRAINS = [(f"train_ZYNQ-A01_{b}", 5) for b in range(704, 724)]


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def collect():
    boots = []
    for dirname, want_frames in [PILOT] + TRAINS:
        boot_dir = CAMPAIGN / dirname
        session = json.loads((boot_dir / "session.json").read_text())
        if session.get("status") != "VALID":
            raise RuntimeError(f"{dirname}: session not VALID")
        frames = []
        for ordinal in range(1, want_frames + 1):
            fp = boot_dir / f"frame_{ordinal:03d}.json"
            frame = json.loads(fp.read_text())
            if len(frame["pairs"]) != 2016:
                raise RuntimeError(f"{dirname} frame {ordinal}: pair count")
            if frame["frame_seq"] != ordinal:
                raise RuntimeError(f"{dirname} frame {ordinal}: seq")
            frames.append({"ordinal": ordinal,
                           "sha256": sha256_file(fp)})
        boots.append({"dir": dirname,
                      "boot_index": session["boot_index"],
                      "campaign": session["campaign"],
                      "session_sha256": sha256_file(boot_dir / "session.json"),
                      "frames": frames})
    aggregate = hashlib.sha256(json.dumps(
        boots, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    return {"schema": "r7-train-input-freeze-v1",
            "pilot_boot_index": 703,
            "train_boot_range": [704, 723],
            "train_boot_count": 20,
            "train_frame_count": 100 + 50,
            "boots": boots,
            "aggregate_sha256": aggregate}


def main() -> int:
    first = collect()
    second = collect()
    if first["aggregate_sha256"] != second["aggregate_sha256"]:
        print("R7_TRAIN_FREEZE_NONDETERMINISTIC", file=sys.stderr)
        return 1
    if OUT.exists():
        current = json.loads(OUT.read_text())
        if current["aggregate_sha256"] != first["aggregate_sha256"]:
            print("R7_TRAIN_FREEZE_MISMATCH: existing freeze differs",
                  file=sys.stderr)
            return 1
        print(f"R7_TRAIN_INPUT_FREEZE_RECHECK_PASS {first['aggregate_sha256']}")
        return 0
    OUT.write_text(json.dumps(first, indent=1, sort_keys=True) + "\n")
    print(f"R7_TRAIN_INPUT_FREEZE_PASS {first['aggregate_sha256']} "
          f"boots=21 frames={first['train_frame_count']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
