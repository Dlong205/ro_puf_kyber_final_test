#!/usr/bin/env python3
"""Operational-final board E2E using the frozen helper (no enrollment)."""

from pathlib import Path
import argparse
import hashlib
import json
import struct
import sys
import time

import serial

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import helper_record_spec as spec  # noqa: E402

BAUD = 115200
CMD_INFO = 0x00
CMD_ENROLL = 0x01
CMD_SESSION = 0x02
STATUS_OK = 0xAA
STATUS_FAIL = 0xFF
PK_BYTES = 800
CT_BYTES = 768
FROZEN_MAPPING_TAG = 0x81B5


def read_exact(port, count, label, timeout=60.0):
    data = bytearray()
    end = time.time() + timeout
    while len(data) < count:
        if time.time() >= end:
            raise TimeoutError(f"{label}: received {len(data)}/{count} bytes")
        chunk = port.read(count - len(data))
        if chunk:
            data.extend(chunk)
    return bytes(data)


def crc_record(body):
    body = bytes(body[:spec.OFF_CRC])
    return body + struct.pack("<H", spec.crc16_ccitt_false(body))


def drain(port):
    time.sleep(0.15)
    if port.in_waiting:
        port.read(port.in_waiting)


def session(port, record, nonce, expect_pass, label, *, send_nonce=True):
    started = time.perf_counter()
    drain(port)
    port.write(bytes([CMD_SESSION]))
    if read_exact(port, 1, f"{label} H") != b"H":
        raise RuntimeError(f"{label}: missing H marker")
    # Parser-level failures occur immediately after the record. Do not leave a
    # nonce queued as stray UART commands when a malformed record is rejected.
    port.write(record + nonce if send_nonce else record)
    first = read_exact(port, 1, f"{label} response")
    if not expect_pass:
        if first != bytes([STATUS_FAIL]):
            raise RuntimeError(f"{label}: fail-open byte=0x{first[0]:02x}")
        code = read_exact(port, 1, f"{label} failure code")[0]
        print(f"{label}: REJECTED code=0x{code:02x} "
              f"elapsed={time.perf_counter() - started:.3f}s")
        return {"accepted": False, "failure_code": code}
    if first == bytes([STATUS_FAIL]):
        code = read_exact(port, 1, f"{label} failure code")[0]
        raise RuntimeError(f"{label}: rejected code=0x{code:02x} "
                           f"elapsed={time.perf_counter() - started:.3f}s")
    if first != b"P":
        raise RuntimeError(f"{label}: expected P, got 0x{first[0]:02x}")
    public_key = read_exact(port, PK_BYTES, f"{label} public key")
    if read_exact(port, 1, f"{label} C") != b"C":
        raise RuntimeError(f"{label}: missing C marker")
    ciphertext = bytes((i + nonce[0]) & 0xFF for i in range(CT_BYTES))
    port.write(ciphertext)
    result = read_exact(port, 5, f"{label} result", timeout=90.0)
    if result[0] != STATUS_OK:
        raise RuntimeError(f"{label}: ML-KEM result status=0x{result[0]:02x}")
    tag = struct.unpack("<I", result[1:])[0]
    pk_sha256 = hashlib.sha256(public_key).hexdigest()
    print(f"{label}: PASS pk_sha256={pk_sha256[:16]} result_tag=0x{tag:08x}")
    return {"accepted": True, "pk_sha256": pk_sha256, "result_tag": tag}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", default="/dev/serial/by-id/usb-1a86_USB_Serial-if00-port0")
    parser.add_argument("--helper", type=Path, default=ROOT / "reports/puf64_macrov2_campaign/private_enrollment_helper.record")
    parser.add_argument("--anchor", type=Path, default=ROOT / "reports/puf64_macrov2_campaign/private_device_anchor.json")
    parser.add_argument("--positive-runs", type=int, default=3)
    parser.add_argument("--mapping-tag", default="0x81B5",
                        help="expected on-wire mapping tag hex (gen2: 0x005D)")
    parser.add_argument("--preflight-only", action="store_true",
                        help="validate frozen helper/anchor without opening UART")
    args = parser.parse_args()
    mapping_tag = int(args.mapping_tag, 16)

    record = args.helper.read_bytes()
    if len(record) != spec.RECORD_BYTES:
        raise SystemExit(f"helper length is {len(record)}, expected {spec.RECORD_BYTES}")
    status, _, _, _ = spec.validate_record(
        record, expected_mapping_tag=mapping_tag
    )
    if status != spec.REC_OK:
        raise SystemExit(f"helper record invalid: {spec.ERROR_NAMES.get(status, status)}")
    anchor = json.loads(args.anchor.read_text())
    helper_sha = hashlib.sha256(record).hexdigest()
    if anchor.get("helper_record_sha256") != helper_sha:
        raise SystemExit("helper SHA does not match private anchor manifest")
    if anchor.get("kcv_ctx_fields", {}).get("mapping_tag") != mapping_tag:
        raise SystemExit("anchor mapping tag does not match frozen mapping")
    legacy_status, _, _, _ = spec.validate_record(record)
    if legacy_status == spec.REC_OK:
        raise SystemExit("helper unexpectedly validates as legacy profile")
    print(f"PREFLIGHT: PASS mapping_tag=0x{mapping_tag:04x} "
          f"helper_sha256={helper_sha}")
    if args.preflight_only:
        return 0

    with serial.Serial(args.port, BAUD, timeout=1.0) as port:
        time.sleep(2.0)  # MMCM/reset and PicoRV32 firmware boot margin.
        drain(port)
        port.write(bytes([CMD_INFO]))
        info = read_exact(port, 5, "INFO")
        if info != bytes.fromhex("454101010f"):
            raise RuntimeError(f"INFO mismatch: {info.hex()}")
        print(f"INFO: PASS {info.hex()} helper_sha256={helper_sha}")

        port.write(bytes([CMD_ENROLL]))
        denied = read_exact(port, 2, "enrollment denial")
        if denied != bytes([STATUS_FAIL, 0x01]):
            raise RuntimeError(f"enrollment not fail-closed: {denied.hex()}")
        print("ENROLL_DISABLED: PASS")

        for index in range(args.positive_runs):
            nonce = struct.pack("<I", 0x50360000 + index)
            session(port, record, nonce, True, f"POSITIVE_{index + 1}")

        bad_crc = bytearray(record)
        bad_crc[-1] ^= 1
        session(port, bytes(bad_crc), b"CRC!", False, "NEG_BAD_CRC",
                send_nonce=False)

        wrong_kcv = bytearray(record)
        wrong_kcv[spec.OFF_KCV] ^= 1
        session(port, crc_record(wrong_kcv), b"KCV!", False, "NEG_WRONG_KCV")

        wrong_tag = bytearray(record)
        wrong_tag[spec.OFF_MAPPING_TAG] ^= 1
        session(port, crc_record(wrong_tag), b"TAG!", False,
                "NEG_WRONG_MAPPING_TAG", send_nonce=False)

        far_helper = bytearray(record)
        for i in range(16):
            far_helper[spec.OFF_HELPER + (2 * i) % 33] ^= 0xFF
        session(port, crc_record(far_helper), b"HELP", False, "NEG_HELPER_SUBSTITUTION")

    print("PICORV32_OPERATIONAL_E2E_PASS")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, serial.SerialException, TimeoutError, RuntimeError) as exc:
        print(f"PICORV32_OPERATIONAL_E2E_FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
