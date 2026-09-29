#!/usr/bin/env python3
"""R7 release stress: N positive SESSIONs, pk stability + tag uniqueness.

Usage: python3 host/puf64_r7_stress.py --count 1000 [--port ...]
Board must hold the R7 release image (program first). Logs progress every
50 sessions; final line summarizes. Exit nonzero on first failure.
"""
import argparse
import hashlib
import json
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

HELPER = ROOT / "reports/puf64_finalchar_campaign/r7_helper.record"
ANCHOR = ROOT / "reports/puf64_finalchar_campaign/r7_anchor.json"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--count", type=int, default=1000)
    ap.add_argument("--port",
                    default="/dev/serial/by-id/usb-1a86_USB_Serial-if00-port0")
    ap.add_argument("--mapping-tag", default="0x81B7")
    ap.add_argument("--out", type=Path, default=Path("/tmp/r7_stress.json"))
    args = ap.parse_args()
    tag = int(args.mapping_tag, 16)

    record = HELPER.read_bytes()
    status, _, _, _ = spec.validate_record(record, expected_mapping_tag=tag)
    assert len(record) == spec.RECORD_BYTES and status == spec.REC_OK, \
        "helper invalid"
    anchor = json.loads(ANCHOR.read_text())
    assert anchor.get("helper_record_sha256") == hashlib.sha256(record).hexdigest()
    assert anchor.get("kcv_ctx_fields", {}).get("mapping_tag") == tag

    pks, tags = set(), set()
    fails = 0
    t0 = time.time()
    with serial.Serial(args.port, 115200, timeout=2.0) as port:
        time.sleep(1.0)
        for i in range(args.count):
            try:
                nonce = struct.pack("<I", 0x60000000 + i)
                out = e2e.session(port, record, nonce, True, f"STRESS_{i}")
                pks.add(out["pk_sha256"])
                tags.add(out["result_tag"])
                if len(pks) != 1:
                    raise RuntimeError(f"pk drift at {i}")
            except Exception as exc:  # noqa: BLE001 - count and continue
                fails += 1
                print(f"STRESS_{i}: FAIL {str(exc)[:100]}", flush=True)
                if fails > 10:
                    print("too many failures, aborting")
                    break
            if (i + 1) % 50 == 0:
                print(f"progress {i + 1}/{args.count} fails={fails} "
                      f"elapsed={time.time() - t0:.0f}s", flush=True)
    summary = {"sessions": args.count, "fails": fails,
               "distinct_pk": len(pks), "distinct_tags": len(tags),
               "elapsed_s": round(time.time() - t0, 1)}
    args.out.write_text(json.dumps(summary, indent=1) + "\n")
    print("STRESS_SUMMARY " + json.dumps(summary))
    return 0 if fails == 0 and len(pks) == 1 else 1


if __name__ == "__main__":
    raise SystemExit(main())
