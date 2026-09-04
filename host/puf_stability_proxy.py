#!/usr/bin/env python3
"""Measure repeated-enrollment helper variation without exposing PUF secrets.

This tool works with the normal release firmware.  It is deliberately called a
proxy: BCH helper-data distance is not the raw 264-bit PUF response distance.
Use a characterization-only bitstream before making entropy, intra-HD, or
per-bit reliability claims.
"""

import argparse
from collections import Counter
import json
from pathlib import Path
import statistics
import sys
import time

import serial


CMD_ENROLL = 0x01
STATUS_SUCCESS = 0xAA
STATUS_FAIL = 0xFF
HELPER_BYTES = 33


def read_exact(port, length):
    data = port.read(length)
    if len(data) != length:
        raise RuntimeError(f"expected {length} byte(s), received {len(data)}")
    return data


def collect(port_name, count, timeout):
    counts = Counter()
    sequence = []
    started = time.perf_counter()

    with serial.Serial(port_name, 115200, timeout=timeout) as port:
        time.sleep(0.1)
        if port.in_waiting:
            port.read(port.in_waiting)

        for index in range(count):
            port.write(bytes([CMD_ENROLL]))
            status = read_exact(port, 1)[0]
            if status == STATUS_FAIL:
                code = read_exact(port, 1)[0]
                raise RuntimeError(
                    f"enroll {index + 1} failed with firmware error 0x{code:02x}"
                )
            if status != STATUS_SUCCESS:
                raise RuntimeError(
                    f"enroll {index + 1} returned invalid status 0x{status:02x}"
                )

            helper = read_exact(port, HELPER_BYTES)
            counts[helper] += 1
            sequence.append(helper)

            if (index + 1) % 1000 == 0 or index + 1 == count:
                print(
                    f"[{index + 1}/{count}] unique helper values={len(counts)}",
                    flush=True,
                )

    elapsed = time.perf_counter() - started
    ranked = counts.most_common()
    mode = ranked[0][0]
    mode_int = int.from_bytes(mode, "little")
    distances = [
        (int.from_bytes(value, "little") ^ mode_int).bit_count()
        for value in sequence
    ]
    changing_mask = 0
    for value in counts:
        changing_mask |= int.from_bytes(value, "little") ^ mode_int

    return {
        "metric_scope": "BCH helper-data stability proxy; not raw PUF HD",
        "sample_count": count,
        "unique_helper_values": len(ranked),
        "mode_rate_percent": ranked[0][1] * 100.0 / count,
        "helper_hd_to_mode": {
            "min": min(distances),
            "mean": statistics.fmean(distances),
            "max": max(distances),
        },
        "changing_helper_bit_positions": changing_mask.bit_count(),
        "consecutive_transitions": sum(
            sequence[index] != sequence[index - 1]
            for index in range(1, len(sequence))
        ),
        "value_ranks": [
            {
                "count": value_count,
                "rate_percent": value_count * 100.0 / count,
                "hd_to_mode": (int.from_bytes(value, "little") ^ mode_int).bit_count(),
            }
            for value, value_count in ranked
        ],
        "elapsed_seconds": elapsed,
    }


def main():
    parser = argparse.ArgumentParser(
        description="Repeated-enrollment helper stability proxy for release firmware"
    )
    parser.add_argument("--port", required=True, help="Stable UART device path")
    parser.add_argument("--count", type=int, default=1000)
    parser.add_argument("--timeout", type=float, default=10.0)
    parser.add_argument(
        "--report",
        help="Optional JSON summary path; raw helper values are never written",
    )
    args = parser.parse_args()

    if args.count <= 0:
        parser.error("--count must be greater than zero")

    try:
        result = collect(args.port, args.count, args.timeout)
    except (RuntimeError, serial.SerialException) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1

    print("=== PUF HELPER STABILITY PROXY ===")
    print(json.dumps(result, indent=2, sort_keys=True))
    print(
        "WARNING: do not interpret helper HD as raw PUF HD or entropy. "
        "Use a characterization-only raw-response interface for those claims."
    )

    if args.report:
        report_path = Path(args.report)
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(
            json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        print(f"Summary written to {report_path}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
