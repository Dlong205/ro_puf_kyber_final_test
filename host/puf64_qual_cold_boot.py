#!/usr/bin/env python3
"""One cold operational qualification boot, with durable private evidence.

The operator must power-cycle the board before invoking this command.  Every
boot index is reserved before JTAG programming, so an interrupted attempt can
never silently become a new sample under the same index.  The output directory
is git-ignored because telemetry is a per-device physical fingerprint.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys
import time

import serial

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "host"))
import puf64_picorv32_operational_e2e as e2e  # noqa: E402
import puf64_qual_telemetry_read as telemetry  # noqa: E402
import puf64_qual_authorize_holdout as holdout_gate  # noqa: E402
sys.path.insert(0, str(ROOT / "scripts"))
import helper_record_spec as spec  # noqa: E402

BITSTREAM = (ROOT / "build/puf64_qual_A/puf64_qual_zynq7020_A.runs/impl_1/"
             "Edge_Puf64_Zynq_PicoRV32_Final_100MHz_Top.bit")
MACRO_DCP = ROOT / "build/puf64_macro_v2/macro_v2_routed_ooc.dcp"
MACRO_FP = ROOT / "reports/puf64_qual_A/qual_r2_macro_fingerprint.tsv"
FROZEN_MACRO_FP = ROOT / "build/puf64_macro_v2/macro_v2_fingerprint.tsv"
INFLUENCE_FP = (ROOT / "reports/puf64_qual_A/"
                "qual_operational_influence_fingerprint.tsv")
HELPER = ROOT / "reports/puf64_macrov2_campaign/private_enrollment_helper.record"
ANCHOR = ROOT / "reports/puf64_macrov2_campaign/private_device_anchor.json"
DEFAULT_OUT = ROOT / "reports/puf64_operational_native_campaign"
EXPECTED_BIT_SHA = "a9ffce0e3cb23c894c99e45c27aebc1770a24c505da35ea0eac27315194dc280"
EXPECTED_MACRO_SHA = "bd0cd6200ca4e122932596eb8502d29f1b7d4b1aedf974a79990b4d1f5a9fdd4"
QUAL_INFO = bytes.fromhex("4541010171")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


def save_new(path: Path, payload: dict) -> None:
    with path.open("x", encoding="utf-8") as destination:
        json.dump(payload, destination, indent=1, sort_keys=True)
        destination.write("\n")


def preflight(args) -> tuple[dict, bytes]:
    if args.board_id != "ZYNQ-A01":
        raise RuntimeError("R6_IDENTITY_FAIL: unexpected board ID")
    expected_frames = 5 if args.campaign == "train" else 50
    if args.frames != expected_frames:
        raise RuntimeError("R6_FRAME_COUNT_FAIL: pilot/holdout=50, train=5")
    if args.boot_index <= 501:
        raise RuntimeError("R6_BOOT_INDEX_REUSE: indices through 501 consumed")
    if sha256(BITSTREAM) != EXPECTED_BIT_SHA:
        raise RuntimeError("R6_BITSTREAM_SHA_MISMATCH")
    if sha256(MACRO_DCP) != EXPECTED_MACRO_SHA:
        raise RuntimeError("R6_MACRO_SHA_MISMATCH")
    authorization = None
    if args.campaign == "holdout":
        check = subprocess.run(
            [sys.executable, str(ROOT / "host/puf64_qual_authorize_holdout.py")],
            cwd=ROOT, text=True, capture_output=True, timeout=90)
        if check.returncode != 0 or "R6_HOLDOUT_AUTHORIZATION_RECHECK_PASS" not in check.stdout:
            raise RuntimeError("R6_HOLDOUT_BLOCKED: " + (check.stderr or check.stdout)[-300:])
        authorization = json.loads(holdout_gate.OUTPUT.read_text())
        if args.boot_index not in authorization["holdout_boot_indices"]:
            raise RuntimeError("R6_HOLDOUT_INDEX_NOT_AUTHORIZED")
        if authorization["bitstream_sha256"] != EXPECTED_BIT_SHA:
            raise RuntimeError("R6_HOLDOUT_IMAGE_MISMATCH")
    gate = subprocess.run([sys.executable, str(ROOT / "scripts/check_r6_ab_gate.py")],
                          cwd=ROOT, text=True, capture_output=True, timeout=90)
    if gate.returncode != 0 or "R6_AB_GATE_PASS" not in gate.stdout:
        raise RuntimeError("R6_AB_GATE_FAIL: " + (gate.stderr or gate.stdout)[-300:])
    record = HELPER.read_bytes()
    status, _, _, _ = spec.validate_record(record, expected_mapping_tag=0x81B5)
    if len(record) != spec.RECORD_BYTES or status != spec.REC_OK:
        raise RuntimeError("R6_HELPER_INVALID")
    anchor = json.loads(ANCHOR.read_text())
    helper_sha = hashlib.sha256(record).hexdigest()
    if anchor.get("helper_record_sha256") != helper_sha:
        raise RuntimeError("R6_HELPER_ANCHOR_MISMATCH")
    identity = {
        "schema": "r6-operational-cold-boot-v1",
        "board_id": args.board_id,
        "campaign": args.campaign,
        "boot_index": args.boot_index,
        "frames_requested": args.frames,
        "bitstream_sha256": EXPECTED_BIT_SHA,
        "macro_dcp_sha256": EXPECTED_MACRO_SHA,
        "frozen_macro_fingerprint_sha256": sha256(FROZEN_MACRO_FP),
        "macro_fingerprint_sha256": sha256(MACRO_FP),
        "influence_fingerprint_sha256": sha256(INFLUENCE_FP),
        "helper_record_sha256": helper_sha,
        "qual_info": QUAL_INFO.hex(),
        "created_utc": now(),
    }
    if authorization is not None:
        identity["holdout_authorization_sha256"] = sha256(holdout_gate.OUTPUT)
    return identity, record


def run_boot(args, identity: dict, record: bytes, boot_dir: Path) -> dict:
    authorization = (json.loads(holdout_gate.OUTPUT.read_text())
                     if args.campaign == "holdout" else None)
    if authorization is not None and sha256(holdout_gate.OUTPUT) != identity["holdout_authorization_sha256"]:
        raise RuntimeError("R6_HOLDOUT_AUTHORIZATION_CHANGED")
    program = subprocess.run(
        [args.vivado, "-mode", "batch", "-nolog", "-nojournal", "-source",
         str(ROOT / "scripts/program_puf64_qual.tcl"), "-tclargs", "A",
         EXPECTED_BIT_SHA], cwd=ROOT, text=True, capture_output=True,
        timeout=300)
    with (boot_dir / "program.log").open("x", encoding="utf-8") as log:
        log.write(program.stdout + program.stderr)
    if program.returncode != 0 or "QUAL_PROGRAM_PASS" not in program.stdout:
        raise RuntimeError("R6_PROGRAM_FAIL: inspect program.log")
    if sha256(BITSTREAM) != EXPECTED_BIT_SHA:
        raise RuntimeError("R6_BITSTREAM_CHANGED_AFTER_PROGRAM")
    print("R6_PROGRAM_PASS; warming for 30 s", flush=True)
    time.sleep(30)

    frames = []
    pk_first = None
    with serial.Serial(args.port, 115200, timeout=1.0) as port:
        e2e.drain(port)
        port.write(bytes([0]))
        info = e2e.read_exact(port, 5, "QUAL INFO")
        if info != QUAL_INFO:
            raise RuntimeError(f"R6_INFO_MISMATCH: {info.hex()}")
        port.write(bytes([1]))
        denied = e2e.read_exact(port, 2, "ENROLL_DISABLED")
        if denied != bytes([0xFF, 0x01]):
            raise RuntimeError(f"R6_ENROLL_FAIL_OPEN: {denied.hex()}")
        for ordinal in range(1, args.frames + 1):
            nonce = struct.pack("<I", 0x56000000 + args.boot_index * 100 + ordinal)
            result = e2e.session(port, record, nonce, True,
                                 f"BOOT_{args.boot_index}_FRAME_{ordinal}")
            if pk_first is None:
                pk_first = result["pk_sha256"]
            elif result["pk_sha256"] != pk_first:
                raise RuntimeError(f"R6_PK_DRIFT frame={ordinal}")
            frame = telemetry.read_frame(port, args.boot_index,
                                         f"{args.campaign}_{ordinal:03d}")
            if frame["frame_seq"] != ordinal:
                raise RuntimeError(f"R6_SEQ_FAIL frame={ordinal} "
                                   f"seq={frame['frame_seq']}")
            frame_path = boot_dir / f"frame_{ordinal:03d}.json"
            save_new(frame_path, frame)
            selected_errors = None
            if authorization is not None:
                selected = holdout_gate.selected(frame)
                if any(pair["tie"] for pair in selected):
                    raise RuntimeError(f"R6_HOLDOUT_SELECTED_TIE frame={ordinal}")
                selected_errors = sum(
                    pair["winner"] != bit for pair, bit in
                    zip(selected, authorization["reference_bits"]))
                if selected_errors > 8 or frame["bch_corr"] > 8:
                    raise RuntimeError(f"R6_HOLDOUT_ERROR_CAP frame={ordinal} "
                                       f"bits={selected_errors} corr={frame['bch_corr']}")
            ties = sum(pair["tie"] for pair in frame["pairs"])
            frame_record = {"ordinal": ordinal, "frame_seq": frame["frame_seq"],
                            "sha256": sha256(frame_path), "ties": ties,
                            "bch_corr": frame["bch_corr"],
                            "overrun": frame["status"]["overrun"],
                            "pk_sha256": result["pk_sha256"],
                            "result_tag": result["result_tag"]}
            if selected_errors is not None:
                frame_record["selected_bit_errors"] = selected_errors
            frames.append(frame_record)
            print(f"R6_FRAME_VALID boot={args.boot_index} {ordinal}/{args.frames} "
                  f"ties={ties} corr={frame['bch_corr']}", flush=True)
        if args.campaign == "pilot":
            bad_crc = bytearray(record)
            bad_crc[-1] ^= 1
            rejection = e2e.session(port, bytes(bad_crc), b"CRC!", False,
                                    "R6_BAD_CRC", send_nonce=False)
            if rejection["failure_code"] != 0x08:
                raise RuntimeError("R6_BAD_CRC_CODE_FAIL")
    if authorization is not None and sha256(holdout_gate.OUTPUT) != identity["holdout_authorization_sha256"]:
        raise RuntimeError("R6_HOLDOUT_AUTHORIZATION_CHANGED")
    return {**identity, "status": "VALID", "completed_utc": now(),
            "frames": frames, "public_key_sha256": pk_first}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--board-id", default="ZYNQ-A01")
    ap.add_argument("--campaign", required=True, choices=["pilot", "train", "holdout"])
    ap.add_argument("--boot-index", required=True, type=int)
    ap.add_argument("--frames", required=True, type=int)
    ap.add_argument("--port", default="/dev/serial/by-id/usb-1a86_USB_Serial-if00-port0")
    ap.add_argument("--vivado", default="/media/donglong/tools/Xilinx/Vivado/2020.1/bin/vivado")
    ap.add_argument("--out-dir", type=Path, default=DEFAULT_OUT)
    ap.add_argument("--cold-boot-confirmed", action="store_true")
    ap.add_argument("--preflight-only", action="store_true")
    args = ap.parse_args()
    try:
        identity, record = preflight(args)
        if args.preflight_only:
            print("R6_COLD_PREFLIGHT_PASS " + json.dumps(identity, sort_keys=True))
            return 0
        if not args.cold_boot_confirmed:
            raise RuntimeError("R6_OPERATOR_COLD_CONFIRMATION_REQUIRED")
        args.out_dir.mkdir(parents=True, exist_ok=True)
        # Atomic reservation is the consumed-index ledger, even on interruption.
        boot_dir = args.out_dir / f"{args.campaign}_{args.board_id}_{args.boot_index}"
        boot_dir.mkdir(exist_ok=False)
        save_new(boot_dir / "attempt.json", {**identity, "status": "STARTED"})
        try:
            result = run_boot(args, identity, record, boot_dir)
        except (Exception, KeyboardInterrupt) as exc:
            save_new(boot_dir / "session.json.invalid",
                     {**identity, "status": "INVALID", "error": str(exc),
                      "ended_utc": now()})
            raise
        save_new(boot_dir / "session.json", result)
        print(f"R6_BOOT_VALID boot={args.boot_index} campaign={args.campaign} "
              f"frames={len(result['frames'])} path={boot_dir}")
        return 0
    except (OSError, RuntimeError, TimeoutError, serial.SerialException,
            subprocess.SubprocessError) as exc:
        print(f"R6_BOOT_STOP: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
