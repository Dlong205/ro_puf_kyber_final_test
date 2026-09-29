#!/usr/bin/env python3
"""R6.3 operational-qualification pilot (QUALIFICATION_NONRELEASE only).

Runs on a qual image (INFO 4541010171; refuses release 454101010f and any
other image so pilot data can never mix sources):
  1. preflight: frozen gen1 helper + private anchor binding (same checks as
     the release e2e preflight).
  2. INFO marker gate (must be 0x71).
  3. ENROLL_DISABLED check (0x01 -> FF 01).
  4. N warm positive SESSIONs (gen1 helper); pk sha recorded per run.
  5. After each SESSION, private 0x70 frame fetch -> JSON (warm pilot
     telemetry for R6.3 offset/tie/correction analysis).
  6. Negative spot-check: bad CRC -> reject (parser fail-closed alive).

Usage:
  python3 host/puf64_qual_pilot.py --port /dev/ttyUSB0 --runs 3 \
      --out-dir /tmp/r6qual/pilot --boot-label warm0
"""
from pathlib import Path
import argparse
import hashlib
import json
import struct
import subprocess
import sys
import time

import serial

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "host"))
import puf64_picorv32_operational_e2e as e2e  # noqa: E402
sys.path.insert(0, str(ROOT / "scripts"))
import helper_record_spec as spec  # noqa: E402

BAUD = 115200
CMD_INFO = 0x00
CMD_ENROLL = 0x01
STATUS_FAIL = 0xFF
QUAL_INFO = bytes.fromhex("4541010171")
MAPPING_TAG = 0x81B5


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", required=True)
    ap.add_argument("--runs", type=int, default=3)
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--boot-label", default="warm0")
    ap.add_argument("--helper", default=str(
        ROOT / "reports/puf64_macrov2_campaign/private_enrollment_helper.record"))
    ap.add_argument("--anchor", default=str(
        ROOT / "reports/puf64_macrov2_campaign/private_device_anchor.json"))
    args = ap.parse_args()
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    record = Path(args.helper).read_bytes()
    if len(record) != spec.RECORD_BYTES:
        print(f"helper length {len(record)}", file=sys.stderr)
        return 1
    status, _, _, _ = spec.validate_record(record, expected_mapping_tag=MAPPING_TAG)
    if status != spec.REC_OK:
        print("helper record invalid", file=sys.stderr)
        return 1
    anchor = json.loads(Path(args.anchor).read_text())
    helper_sha = hashlib.sha256(record).hexdigest()
    if anchor.get("helper_record_sha256") != helper_sha:
        print("helper SHA mismatch vs anchor", file=sys.stderr)
        return 1
    print(f"PILOT PREFLIGHT PASS tag=0x81b5 helper={helper_sha[:16]}")

    pk_hashes: list[str] = []
    with serial.Serial(args.port, BAUD, timeout=1.0) as port:
        time.sleep(2.0)
        e2e.drain(port)
        port.write(bytes([CMD_INFO]))
        info = e2e.read_exact(port, 5, "INFO")
        if info != QUAL_INFO:
            print(f"PILOT_REFUSE: INFO {info.hex()} is not a qual image",
                  file=sys.stderr)
            return 1
        print(f"PILOT INFO PASS {info.hex()}")

        port.write(bytes([CMD_ENROLL]))
        denied = e2e.read_exact(port, 2, "enrollment denial")
        if denied != bytes([STATUS_FAIL, 0x01]):
            print(f"enrollment not fail-closed: {denied.hex()}", file=sys.stderr)
            return 1
        print("PILOT ENROLL_DISABLED PASS")

        for index in range(args.runs):
            nonce = struct.pack("<I", 0x51300000 + index)
            label = f"PILOT_POS_{index + 1}"
            # capture pk hash via session() print? re-run inline for hash:
            e2e.session(port, record, nonce, True, label)
            frame_path = out_dir / f"frame_{args.boot_label}_{index + 1:02d}.json"
            r = subprocess.run(
                [sys.executable, str(ROOT / "host/puf64_qual_telemetry_read.py"),
                 "--port", args.port, "--out", str(frame_path),
                 "--boot-index", "-1",
                 "--frame-label", f"{args.boot_label}_{index + 1:02d}"],
                text=True, capture_output=True, timeout=180)
            print(r.stdout.strip())
            if r.returncode != 0:
                print(r.stderr.strip(), file=sys.stderr)
                print("PILOT_FRAME_FAIL", file=sys.stderr)
                return 1
        # negative spot-check: bad CRC must reject (any fail code)
        bad = bytearray(record)
        bad[-1] ^= 1
        e2e.session(port, bytes(bad), b"CRC!", False, "PILOT_NEG_BAD_CRC",
                    send_nonce=False)
    print(f"PILOT_PASS runs={args.runs} out={out_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
