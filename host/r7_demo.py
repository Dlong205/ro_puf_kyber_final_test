#!/usr/bin/env python3
"""One-command R7 demo for video: INFO -> enroll-deny -> 1 positive ->
1 negative -> summary. Prints only public data (pk prefix, tags,
PASS/FAIL). Never prints helper/record/secret/KCV.
"""
import struct
import sys
import time
from pathlib import Path

import serial

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "host"))
import puf64_picorv32_operational_e2e as e2e  # noqa: E402
sys.path.insert(0, str(ROOT / "scripts"))
import helper_record_spec as spec  # noqa: E402
import hashlib
import json

HELPER = ROOT / "reports/puf64_finalchar_campaign/r7_helper.record"
ANCHOR = ROOT / "reports/puf64_finalchar_campaign/r7_anchor.json"
PORT = "/dev/serial/by-id/usb-1a86_USB_Serial-if00-port0"


def banner(text):
    print(f"\n===== {text} =====", flush=True)


def main() -> int:
    record = HELPER.read_bytes()
    assert spec.validate_record(record, expected_mapping_tag=0x81B7)[0] == spec.REC_OK
    anchor = json.loads(ANCHOR.read_text())
    assert anchor["helper_record_sha256"] == hashlib.sha256(record).hexdigest()
    print("R7 DEMO - release B (ab075bfd) + mapping 0x81B7 - public output only")
    t0 = time.time()
    with serial.Serial(PORT, 115200, timeout=2.0) as port:
        time.sleep(1.5)
        banner("1. DEVICE INFO")
        e2e.drain(port)
        port.write(bytes([0x00]))
        print("INFO:", e2e.read_exact(port, 5, "INFO").hex())
        banner("2. ENROLL DISABLED (fail-closed)")
        port.write(bytes([0x01]))
        print("ENROLL deny:", e2e.read_exact(port, 2, "deny").hex())
        banner("3. POSITIVE SESSION")
        out = e2e.session(port, record, struct.pack("<I", 0xDE001337),
                          True, "DEMO_POS")
        print(f"pk: {out['pk_sha256'][:16]}...  tag: 0x{out['result_tag']:08x}")
        banner("4. NEGATIVE (bad CRC -> reject 0x08)")
        bad = bytearray(record)
        bad[-1] ^= 1
        neg = e2e.session(port, bytes(bad), b"CRC!", False, "DEMO_NEG",
                          send_nonce=False)
        print(f"rejected code=0x{neg['failure_code']:02x} (fail-closed OK)")
    banner(f"DEMO DONE in {time.time() - t0:.0f}s - all public, no secrets shown")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
