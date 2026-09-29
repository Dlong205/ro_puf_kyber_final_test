#!/usr/bin/env python3
"""R6.1 private qualification telemetry reader (QUALIFICATION_NONRELEASE only).

Reads one captured sweep frame from a qual image (INFO marker 0x71):
  -> 0x70, <- 'Q' + 10-byte header + 2016 x 11-byte entries + CRC16.

Header: frame_seq u32LE, entry_count u16LE, bch_corr u8, status u8, rsvd u16.
  status bits: 0=frame_valid 1=overrun 2=fe_ok 3=kcv_ok 4=timeout_seen
  5=ovf_seen.
Entry: c0 u32LE, c1 u32LE, a u8, b u8, flags u8
  (flags bits 5..0 = winner,stable,timeout,ovf_a,ovf_b,valid).

Output JSON: per-pair counts/margins + frame outcome.  No FE key, no KCV
value, no shared secret is ever transferred (counts + metadata only).

Refuses to run against a non-qual INFO (byte4 must be 0x71) so qual tooling
can never be mistaken for release capture.  QUALIFICATION_NONRELEASE.
"""
from pathlib import Path
import argparse
import json
import struct
import sys
import time

import serial

BAUD = 115200
CMD_INFO = 0x00
CMD_QUAL = 0x70
QUAL_MARKER = 0x51  # 'Q'
QUAL_INFO_BYTE4 = 0x71
N_PAIRS = 2016
HDR_LEN = 10
ENTRY_LEN = 11


def read_exact(port, count, label, timeout=60.0):
    data = bytearray()
    end = time.time() + timeout
    while len(data) < count:
        if time.time() >= end:
            raise TimeoutError(f"{label}: got {len(data)}/{count} bytes")
        chunk = port.read(count - len(data))
        if chunk:
            data.extend(chunk)
    return bytes(data)


def crc16_ccitt_false(data: bytes, crc: int = 0xFFFF) -> int:
    for byte in data:
        crc ^= byte << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
    return crc


def read_frame(port, boot_index=-1, frame_label=""):
    """Read and validate one private qualification frame on an open UART."""
    time.sleep(0.15)
    if port.in_waiting:
        port.read(port.in_waiting)
    port.write(bytes([CMD_INFO]))
    info = read_exact(port, 5, "INFO")
    if info != bytes.fromhex("4541010171"):
        raise RuntimeError(f"QUAL_REFUSE: INFO {info.hex()} is not qual A")
    port.write(bytes([CMD_QUAL]))
    mark = read_exact(port, 1, "QUAL mark")
    if mark[0] != QUAL_MARKER:
        raise RuntimeError(f"QUAL_REFUSE: bad mark {mark.hex()}")
    hdr = read_exact(port, HDR_LEN, "QUAL header")
    seq = struct.unpack("<I", hdr[0:4])[0]
    count = struct.unpack("<H", hdr[4:6])[0]
    bch, status = hdr[6], hdr[7]
    body = read_exact(port, N_PAIRS * ENTRY_LEN, "QUAL body", timeout=120.0)
    crc_rx = read_exact(port, 2, "QUAL crc")
    if struct.unpack("<H", crc_rx)[0] != crc16_ccitt_false(hdr + body):
        raise RuntimeError("QUAL_CRC_FAIL")
    pairs = []
    for i in range(N_PAIRS):
        e = body[i * ENTRY_LEN:(i + 1) * ENTRY_LEN]
        c0, c1 = struct.unpack("<II", e[0:8])
        a, b, flags = e[8], e[9], e[10]
        pairs.append({"idx": i, "a": a, "b": b, "c0": c0, "c1": c1,
                      "winner": (flags >> 5) & 1, "stable": (flags >> 4) & 1,
                      "timeout": (flags >> 3) & 1,
                      "ovf_a": (flags >> 2) & 1, "ovf_b": (flags >> 1) & 1,
                      "valid": flags & 1,
                      "margin": abs(int(c0) - int(c1)), "tie": c0 == c1})
    out = {
        "schema": "ro-puf-qual-telemetry-v1",
        "qualification_nonrelease": True,
        "info": info.hex(), "boot_index": boot_index,
        "frame_label": frame_label, "frame_seq": seq,
        "entry_count": count, "bch_corr": bch,
        "status": {"raw": status, "frame_valid": bool(status & 1),
                   "overrun": bool(status & 2), "fe_ok": bool(status & 4),
                   "kcv_ok": bool(status & 8),
                   "timeout_seen": bool(status & 16),
                   "ovf_seen": bool(status & 32)},
        "pairs": pairs,
    }
    if count != N_PAIRS:
        raise RuntimeError(f"QUAL_COUNT_FAIL {count}/{N_PAIRS}")
    if not out["status"]["frame_valid"] or not out["status"]["fe_ok"] or \
            not out["status"]["kcv_ok"] or out["status"]["timeout_seen"] or \
            out["status"]["ovf_seen"]:
        raise RuntimeError(f"QUAL_STATUS_FAIL {status:#04x}")
    a = 0
    b = 1
    for pair in pairs:
        if (pair["a"], pair["b"]) != (a, b) or not pair["valid"] or \
                not pair["stable"] or pair["timeout"] or pair["ovf_a"] or \
                pair["ovf_b"] or pair["c0"] == 0 or pair["c1"] == 0 or \
                pair["winner"] != int(pair["c0"] <= pair["c1"]):
            raise RuntimeError(f"QUAL_PAIR_FAIL index={pair['idx']}")
        if b == 63:
            a += 1
            b = a + 1
        else:
            b += 1
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--boot-index", type=int, default=-1)
    ap.add_argument("--frame-label", default="")
    args = ap.parse_args()

    with serial.Serial(args.port, BAUD, timeout=1.0) as port:
        out = read_frame(port, args.boot_index, args.frame_label)
    with Path(args.out).open("x") as destination:
        json.dump(out, destination, indent=1)
    n_tie = sum(1 for p in out["pairs"] if p["tie"])
    print(f"QUAL_FRAME_OK seq={out['frame_seq']} valid={N_PAIRS}/{N_PAIRS} "
          f"ties={n_tie} bch={out['bch_corr']} "
          f"status={out['status']['raw']:#04x} -> {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
