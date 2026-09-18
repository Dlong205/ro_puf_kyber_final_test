#!/usr/bin/env python3
"""Diagnostic host for the PUF64 C1-C4 RO bench (protocol D1).

This tool validates the ripple-counter measurement architecture on real
hardware.  It is NOT a campaign tool: it never writes train/holdout data.
"""

import argparse
import statistics
import sys
import time

import serial

CMD_INFO = 0x00
CMD_RUN = 0x01
CMD_STATUS = 0x02
CMD_READ = 0x03
CMD_ABORT = 0x04

DIAG_MAGIC = b"PUF"
DIAG_VERSION = 0xD1
EXPECTED_BUILD_ID = 0x0001
EXPECTED_TOPOLOGY_ID = 0xC0DE


def read_exact(port, length, timeout_s):
    deadline = time.perf_counter() + timeout_s
    data = bytearray()
    while len(data) < length and time.perf_counter() < deadline:
        chunk = port.read(length - len(data))
        if chunk:
            data.extend(chunk)
    if len(data) != length:
        raise RuntimeError(
            f"timeout: wanted {length} byte(s), got {len(data)}: {bytes(data).hex()}"
        )
    return bytes(data)


def read_response(port, num_ro, timeout_s):
    first = read_exact(port, 1, timeout_s)[0]
    if first == 0xA5:
        tail = read_exact(port, 3 + (num_ro + 7) // 8, timeout_s)
        return "STATUS", {
            "busy": tail[0], "done": tail[1], "error": tail[2],
            "bitmap": tail[3:],
        }
    if first == 0xA6:
        tail = read_exact(port, 21, timeout_s)
        return "READ", {
            "diag_version": tail[0],
            "build_id": tail[1] | (tail[2] << 8),
            "num_ro": tail[3],
            "topology_id": tail[4] | (tail[5] << 8),
            "ro_index": tail[6],
            "count": tail[7] | (tail[8] << 8),
            "flags": tail[9],
            "input_hz": int.from_bytes(tail[10:14], "little"),
            "system_hz": int.from_bytes(tail[14:18], "little"),
            "ref_cycles": tail[18] | (tail[19] << 8),
            "error": tail[20],
        }
    if first == 0xFF:
        code = read_exact(port, 1, timeout_s)[0]
        return "ERROR", {"code": code}
    raise RuntimeError(f"unknown response marker {first:#04x}")


def bitmap_count(bitmap):
    return sum(bin(byte).count("1") for byte in bitmap)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", required=True)
    parser.add_argument("--num-ro", required=True, type=int)
    parser.add_argument("--timeout", type=float, default=5.0)
    parser.add_argument("--run-timeout", type=float, default=10.0)
    parser.add_argument("--ref-cycles", type=int, default=1023)
    args = parser.parse_args()
    num_ro = args.num_ro
    failures = []

    with serial.Serial(args.port, 115200, timeout=args.timeout) as port:
        time.sleep(0.2)
        port.reset_input_buffer()

        port.write(bytes([CMD_INFO]))
        info_raw = read_exact(port, 21, args.timeout)
        if info_raw[:3] != DIAG_MAGIC or info_raw[3] != DIAG_VERSION:
            raise SystemExit(f"bad diag INFO header: {info_raw.hex()}")
        build_id = info_raw[4] | (info_raw[5] << 8)
        reported_ro = info_raw[6]
        topology = info_raw[7] | (info_raw[8] << 8)
        ref_cycles = info_raw[9] | (info_raw[10] << 8)
        mmcm_locked = info_raw[11]
        input_hz = int.from_bytes(info_raw[12:16], "little")
        system_hz = int.from_bytes(info_raw[16:20], "little")
        flags = info_raw[20]
        print(
            f"INFO build_id={build_id:#06x} num_ro={reported_ro} "
            f"topology={topology:#06x} ref={ref_cycles} locked={mmcm_locked} "
            f"in={input_hz} sys={system_hz} diag_only={flags & 1}"
        )
        if build_id != EXPECTED_BUILD_ID:
            raise SystemExit("unexpected build ID")
        if reported_ro != num_ro:
            raise SystemExit(f"NUM_RO mismatch: host {num_ro} device {reported_ro}")
        if topology != EXPECTED_TOPOLOGY_ID:
            raise SystemExit("unexpected topology ID")
        if ref_cycles != args.ref_cycles:
            raise SystemExit("unexpected REF_CYCLES")
        if input_hz != 50000000 or system_hz != 100000000 or mmcm_locked != 1:
            raise SystemExit("clock identity mismatch")
        if not (flags & 1):
            raise SystemExit("device did not mark output diagnostic-only")

        port.write(bytes([CMD_RUN]))
        deadline = time.perf_counter() + args.run_timeout
        status = None
        while time.perf_counter() < deadline:
            port.write(bytes([CMD_STATUS]))
            kind, payload = read_response(port, num_ro, args.timeout)
            if kind != "STATUS":
                raise SystemExit(f"expected STATUS, got {kind}")
            status = payload
            if payload["error"]:
                raise SystemExit(f"RUN error code {payload['error']:#04x}")
            if payload["done"]:
                break
            time.sleep(0.01)
        if not status or not status["done"]:
            raise SystemExit("RUN did not complete before timeout")
        covered = bitmap_count(status["bitmap"])
        print(f"RUN done valid_count={covered}/{num_ro}")
        if covered != num_ro:
            failures.append("status bitmap does not cover every RO")

        per_ro = {}
        for index in range(num_ro):
            port.write(bytes([CMD_READ, index]))
            kind, rec = read_response(port, num_ro, args.timeout)
            if kind == "ERROR":
                failures.append(f"RO {index}: error {rec['code']:#04x}")
                continue
            if kind != "READ":
                failures.append(f"RO {index}: unexpected {kind}")
                continue
            if rec["ro_index"] != index:
                failures.append(f"RO {index}: response index {rec['ro_index']}")
            if rec["build_id"] != build_id or rec["num_ro"] != num_ro:
                failures.append(f"RO {index}: identity changed mid-run")
            f = rec["flags"]
            valid, stable, timeout, wrap, locked = (
                f & 1, (f >> 1) & 1, (f >> 2) & 1, (f >> 3) & 1, (f >> 4) & 1
            )
            if not valid:
                failures.append(f"RO {index}: invalid")
            if not stable:
                failures.append(f"RO {index}: unstable")
            if timeout:
                failures.append(f"RO {index}: timeout")
            if wrap:
                failures.append(f"RO {index}: wrap")
            if not locked:
                failures.append(f"RO {index}: mmcm not locked")
            if rec["count"] == 0:
                failures.append(f"RO {index}: count=0")
            per_ro[index] = rec["count"]

        counts = list(per_ro.values())
        if counts:
            print("per-RO counts:")
            for index in sorted(per_ro):
                print(f"  RO {index:3d}: {per_ro[index]}")
            print(
                f"count min={min(counts)} max={max(counts)} "
                f"mean={statistics.mean(counts):.1f}"
            )
        if len(per_ro) != num_ro:
            failures.append(f"read {len(per_ro)}/{num_ro} ROs")

    if failures:
        print("FAIL:")
        for reason in failures:
            print(f"  - {reason}")
        return 1
    print(f"PASS: {num_ro}/{num_ro} ROs measured, all valid/stable/in-range")
    return 0


if __name__ == "__main__":
    sys.exit(main())
