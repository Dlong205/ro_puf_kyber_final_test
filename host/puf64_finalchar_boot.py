#!/usr/bin/env python3
"""One cold R7 final-char boot: characterize the PUF through the FINAL path.

The operator must power-cycle the board before invoking this command.  Every
boot index is reserved before JTAG programming, so an interrupted attempt can
never silently become a new sample under the same index.  The output directory
is git-ignored (per-device physical fingerprint; R7 campaign, not R6).

Unlike the R6 collector, SESSIONs are EXPECTED to fail here (the frozen
mapping does not match the final path — that is what this campaign measures).
Each iteration runs one SESSION (recording the fail code) followed by one raw
0x70 telemetry read whose CRC must verify; the frame is saved regardless of
FE/KCV status.  Mapping selection happens offline from these frames.
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
import puf64_r7_authorize_holdout as holdout_gate  # noqa: E402
sys.path.insert(0, str(ROOT / "scripts"))
import helper_record_spec as spec  # noqa: E402

BITSTREAM = (ROOT / "build/puf64_operational_final_char/"
             "puf64_operational_final_char_zynq7020.runs/impl_1/"
             "Edge_Puf64_Zynq_Operational_Final_100MHz_Top.bit")
MACRO_DCP = ROOT / "build/puf64_macro_v2/macro_v2_routed_ooc.dcp"
HELPER = ROOT / "reports/puf64_macrov2_campaign/private_enrollment_helper.record"
ANCHOR = ROOT / "reports/puf64_macrov2_campaign/private_device_anchor.json"
DEFAULT_OUT = ROOT / "reports/puf64_finalchar_campaign"
EXPECTED_BIT_SHA = "3e7ef33229395d76eee324510bae164775c198471609b8a5f5036e3c75606bca"
EXPECTED_MACRO_SHA = "bd0cd6200ca4e122932596eb8502d29f1b7d4b1aedf974a79990b4d1f5a9fdd4"
CHAR_INFO = bytes.fromhex("4541010171")


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


def raw_telemetry_frame(port, boot_index: int, label: str) -> dict:
    """0x70 read with CRC gate but WITHOUT the FE/KCV status gate."""
    port.write(bytes([telemetry.CMD_QUAL]))
    mark = e2e.read_exact(port, 1, "QUAL mark")
    if mark[0] != telemetry.QUAL_MARKER:
        raise RuntimeError(f"R7_QUAL_REFUSE: bad mark {mark.hex()}")
    hdr = e2e.read_exact(port, telemetry.HDR_LEN, "QUAL header")
    seq = struct.unpack("<I", hdr[0:4])[0]
    count = struct.unpack("<H", hdr[4:6])[0]
    bch, status = hdr[6], hdr[7]
    body = e2e.read_exact(port, telemetry.N_PAIRS * telemetry.ENTRY_LEN,
                          "QUAL body", timeout=120.0)
    crc_rx = e2e.read_exact(port, 2, "QUAL crc")
    if struct.unpack("<H", crc_rx)[0] != telemetry.crc16_ccitt_false(hdr + body):
        raise RuntimeError("R7_QUAL_CRC_FAIL")
    pairs = []
    for i in range(telemetry.N_PAIRS):
        e = body[i * telemetry.ENTRY_LEN:(i + 1) * telemetry.ENTRY_LEN]
        c0, c1 = struct.unpack("<II", e[0:8])
        a, b, flags = e[8], e[9], e[10]
        pairs.append({"idx": i, "a": a, "b": b, "c0": c0, "c1": c1,
                      "winner": (flags >> 5) & 1, "stable": (flags >> 4) & 1,
                      "timeout": (flags >> 3) & 1,
                      "ovf_a": (flags >> 2) & 1, "ovf_b": (flags >> 1) & 1,
                      "valid": flags & 1,
                      "margin": abs(int(c0) - int(c1)), "tie": c0 == c1})
    return {
        "schema": "ro-puf-qual-telemetry-v1",
        "qualification_nonrelease": True,
        "finalchar_path": True,
        "info": CHAR_INFO.hex(), "boot_index": boot_index,
        "frame_label": label, "frame_seq": seq,
        "entry_count": count, "bch_corr": bch,
        "status": {"raw": status, "frame_valid": bool(status & 1),
                   "overrun": bool(status & 2), "fe_ok": bool(status & 4),
                   "kcv_ok": bool(status & 8),
                   "timeout_seen": bool(status & 16),
                   "ovf_seen": bool(status & 32)},
        "pairs": pairs,
    }


def preflight(args) -> tuple[dict, bytes]:
    if args.board_id != "ZYNQ-A01":
        raise RuntimeError("R7_IDENTITY_FAIL: unexpected board ID")
    expected_frames = 5 if args.campaign == "train" else 50
    if args.frames != expected_frames:
        raise RuntimeError("R7_FRAME_COUNT_FAIL: pilot/holdout=50, train=5")
    if args.boot_index < 701:
        raise RuntimeError("R7_BOOT_INDEX_RESERVED: use 701+ (R6 owns <=610)")
    if sha256(BITSTREAM) != EXPECTED_BIT_SHA:
        raise RuntimeError("R7_BITSTREAM_SHA_MISMATCH")
    if sha256(MACRO_DCP) != EXPECTED_MACRO_SHA:
        raise RuntimeError("R7_MACRO_SHA_MISMATCH")
    record = HELPER.read_bytes()
    status, _, _, _ = spec.validate_record(record, expected_mapping_tag=0x81B5)
    if len(record) != spec.RECORD_BYTES or status != spec.REC_OK:
        raise RuntimeError("R7_HELPER_INVALID")
    anchor = json.loads(ANCHOR.read_text())
    helper_sha = hashlib.sha256(record).hexdigest()
    if anchor.get("helper_record_sha256") != helper_sha:
        raise RuntimeError("R7_HELPER_ANCHOR_MISMATCH")
    authorization = None
    if args.campaign == "holdout":
        check = subprocess.run(
            [sys.executable, str(ROOT / "host/puf64_r7_authorize_holdout.py")],
            cwd=ROOT, text=True, capture_output=True, timeout=90)
        if check.returncode != 0 or "R7_HOLDOUT_AUTHORIZATION_RECHECK_PASS" not in check.stdout:
            raise RuntimeError("R7_HOLDOUT_BLOCKED: " + (check.stderr or check.stdout)[-300:])
        authorization = json.loads(holdout_gate.OUTPUT.read_text())
        if args.boot_index not in authorization["holdout_boot_indices"]:
            raise RuntimeError("R7_HOLDOUT_INDEX_NOT_AUTHORIZED")
        if authorization["bitstream_sha256"] != EXPECTED_BIT_SHA:
            raise RuntimeError("R7_HOLDOUT_IMAGE_MISMATCH")
    identity = {
        "schema": "r7-finalchar-cold-boot-v1",
        "board_id": args.board_id,
        "campaign": args.campaign,
        "boot_index": args.boot_index,
        "frames_requested": args.frames,
        "bitstream_sha256": EXPECTED_BIT_SHA,
        "macro_dcp_sha256": EXPECTED_MACRO_SHA,
        "helper_record_sha256": helper_sha,
        "char_info": CHAR_INFO.hex(),
        "created_utc": now(),
    }
    if authorization is not None:
        identity["holdout_authorization_sha256"] = sha256(holdout_gate.OUTPUT)
    return identity, record, authorization


def selected_in_order(frame: dict, ordered_pairs) -> list:
    """Selected pairs in mapping order with winner/tie flags."""
    by_pair = {(p["a"], p["b"]): p for p in frame["pairs"]}
    return [by_pair[(x, y)] for x, y in ordered_pairs]


def run_boot(args, identity: dict, record: bytes, authorization, boot_dir: Path) -> dict:
    if authorization is not None and sha256(holdout_gate.OUTPUT) != identity["holdout_authorization_sha256"]:
        raise RuntimeError("R7_HOLDOUT_AUTHORIZATION_CHANGED")
    program = subprocess.run(
        [args.vivado, "-mode", "batch", "-nolog", "-nojournal", "-source",
         str(ROOT / "scripts/program_puf64_operational_final_char.tcl"),
         "-tclargs", EXPECTED_BIT_SHA], cwd=ROOT, text=True,
        capture_output=True, timeout=300)
    with (boot_dir / "program.log").open("x", encoding="utf-8") as log:
        log.write(program.stdout + program.stderr)
    if program.returncode != 0 or "FINAL_CHAR_PROGRAM_PASS" not in program.stdout:
        raise RuntimeError("R7_PROGRAM_FAIL: inspect program.log")
    if sha256(BITSTREAM) != EXPECTED_BIT_SHA:
        raise RuntimeError("R7_BITSTREAM_CHANGED_AFTER_PROGRAM")
    print("R7_PROGRAM_PASS; warming for 30 s", flush=True)
    time.sleep(30)

    frames = []
    with serial.Serial(args.port, 115200, timeout=1.0) as port:
        e2e.drain(port)
        port.write(bytes([0]))
        info = e2e.read_exact(port, 5, "CHAR INFO")
        if info != CHAR_INFO:
            raise RuntimeError(f"R7_INFO_MISMATCH: {info.hex()}")
        port.write(bytes([1]))
        denied = e2e.read_exact(port, 2, "ENROLL_DISABLED")
        if denied != bytes([0xFF, 0x01]):
            raise RuntimeError(f"R7_ENROLL_FAIL_OPEN: {denied.hex()}")
        for ordinal in range(1, args.frames + 1):
            nonce = struct.pack("<I", 0x70000000 + args.boot_index * 100 + ordinal)
            e2e.drain(port)
            port.write(bytes([2]))
            if e2e.read_exact(port, 1, f"BOOT_{args.boot_index}_H") != b"H":
                raise RuntimeError(f"R7_NO_H frame={ordinal}")
            port.write(record + nonce)
            first = e2e.read_exact(port, 1, f"BOOT_{args.boot_index}_RESP")
            if first == b"P":
                raise RuntimeError(f"R7_UNEXPECTED_SESSION_PASS frame={ordinal} "
                                   f"(frozen mapping should not match final path)")
            if first != bytes([0xFF]):
                raise RuntimeError(f"R7_PROTOCOL_FAIL frame={ordinal} "
                                   f"byte=0x{first[0]:02x}")
            code = e2e.read_exact(port, 1, f"BOOT_{args.boot_index}_CODE")[0]
            frame = raw_telemetry_frame(port, args.boot_index,
                                        f"{args.campaign}_{ordinal:03d}")
            if frame["entry_count"] != telemetry.N_PAIRS:
                raise RuntimeError(f"R7_COUNT_FAIL frame={ordinal} "
                                   f"{frame['entry_count']}/{telemetry.N_PAIRS}")
            frame_path = boot_dir / f"frame_{ordinal:03d}.json"
            save_new(frame_path, frame)
            ties = sum(pair["tie"] for pair in frame["pairs"])
            frame_record = {"ordinal": ordinal, "frame_seq": frame["frame_seq"],
                            "sha256": sha256(frame_path), "ties": ties,
                            "bch_corr": frame["bch_corr"],
                            "overrun": frame["status"]["overrun"],
                            "session_fail_code": code,
                            "fe_ok": frame["status"]["fe_ok"],
                            "kcv_ok": frame["status"]["kcv_ok"]}
            if authorization is not None:
                ordered = authorization["mapping_ordered_pairs"]
                ref_bits = authorization["reference_bits"]
                sel = selected_in_order(frame, ordered)
                if any(p["tie"] for p in sel):
                    raise RuntimeError(f"R7_HOLDOUT_SELECTED_TIE frame={ordinal}")
                sel_errors = sum(
                    p["winner"] != bit for p, bit in zip(sel, ref_bits))
                if sel_errors > 8 or frame["bch_corr"] > 8:
                    raise RuntimeError(f"R7_HOLDOUT_ERROR_CAP frame={ordinal} "
                                       f"bits={sel_errors} corr={frame['bch_corr']}")
                frame_record["selected_bit_errors"] = sel_errors
            frames.append(frame_record)
            print(f"R7_FRAME_VALID boot={args.boot_index} {ordinal}/{args.frames} "
                  f"code=0x{code:02x} ties={ties} "
                  f"corr={frame['bch_corr']}", flush=True)
    return {**identity, "status": "VALID", "completed_utc": now(),
            "frames": frames}


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
        identity, record, authorization = preflight(args)
        if args.preflight_only:
            print("R7_COLD_PREFLIGHT_PASS " + json.dumps(identity, sort_keys=True))
            return 0
        if not args.cold_boot_confirmed:
            raise RuntimeError("R7_OPERATOR_COLD_CONFIRMATION_REQUIRED")
        args.out_dir.mkdir(parents=True, exist_ok=True)
        boot_dir = args.out_dir / f"{args.campaign}_{args.board_id}_{args.boot_index}"
        boot_dir.mkdir(exist_ok=False)
        save_new(boot_dir / "attempt.json", {**identity, "status": "STARTED"})
        try:
            result = run_boot(args, identity, record, authorization, boot_dir)
        except (Exception, KeyboardInterrupt) as exc:
            save_new(boot_dir / "session.json.invalid",
                     {**identity, "status": "INVALID", "error": str(exc),
                      "ended_utc": now()})
            raise
        save_new(boot_dir / "session.json", result)
        print(f"R7_BOOT_VALID boot={args.boot_index} campaign={args.campaign} "
              f"frames={len(result['frames'])} path={boot_dir}")
        return 0
    except (OSError, RuntimeError, TimeoutError, serial.SerialException,
            subprocess.SubprocessError) as exc:
        print(f"R7_BOOT_STOP: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
