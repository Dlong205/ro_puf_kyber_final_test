#!/usr/bin/env python3
"""Collect count-margin telemetry without writing raw PUF responses.

The generated report contains per-challenge physical fingerprints and must be
treated as private characterization data.  It is not suitable for committing
to a public repository.
"""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import statistics
import struct
import sys
import time

import serial


CMD_INFO = 0x00
CMD_MARGIN = 0x71
STATUS_SUCCESS = 0xAA
EXPECTED_INFO = b"PUF\x01\x01\x03"
RECORD_COUNT = 264
RECORD_SIZE = 16
RECORD_STRUCT = struct.Struct("<HBBIII")


def read_exact(port, length):
    data = port.read(length)
    if len(data) != length:
        raise RuntimeError(f"UART timeout: expected {length} byte(s), got {len(data)}")
    return data


def percentile_nearest_rank(values, percentile):
    ordered = sorted(values)
    rank = max(1, math.ceil(percentile * len(ordered)))
    return ordered[rank - 1]


def read_margin(port):
    port.write(bytes([CMD_MARGIN]))
    status = read_exact(port, 1)[0]
    if status != STATUS_SUCCESS:
        raise RuntimeError("margin measurement returned non-success status")
    payload = read_exact(port, RECORD_COUNT * RECORD_SIZE)
    records = []
    for expected_index in range(RECORD_COUNT):
        offset = expected_index * RECORD_SIZE
        index, challenge, flags, count0, count1, margin = RECORD_STRUCT.unpack_from(
            payload, offset
        )
        if index != expected_index:
            raise RuntimeError(
                f"telemetry index mismatch: expected {expected_index}, got {index}"
            )
        if flags & ~0x03:
            raise RuntimeError(f"reserved telemetry flags set at index {index}")
        winner = flags & 1
        tie = (flags >> 1) & 1
        expected_margin = abs(count0 - count1)
        expected_winner = 0 if count0 > count1 else 1
        if margin != expected_margin or winner != expected_winner:
            raise RuntimeError(f"incoherent telemetry record at index {index}")
        if tie != int(count0 == count1):
            raise RuntimeError(f"incorrect tie flag at index {index}")
        records.append((challenge, winner, tie, count0, count1, margin))
    return records


def collect(port_name, count, timeout):
    measurements = []
    started = time.perf_counter()
    with serial.Serial(port_name, 115200, timeout=timeout) as port:
        time.sleep(0.1)
        port.reset_input_buffer()
        port.write(bytes([CMD_INFO]))
        info = read_exact(port, len(EXPECTED_INFO))
        if info != EXPECTED_INFO:
            raise RuntimeError("wrong image or margin telemetry is unsupported")
        for index in range(count):
            measurements.append(read_margin(port))
            if (index + 1) % 10 == 0 or index + 1 == count:
                print(f"[{index + 1}/{count}] margin frames collected", flush=True)
    return measurements, time.perf_counter() - started


def summary_stats(values):
    return {
        "min": min(values),
        "mean": statistics.fmean(values),
        "p01": percentile_nearest_rank(values, 0.01),
        "p05": percentile_nearest_rank(values, 0.05),
        "p50": percentile_nearest_rank(values, 0.50),
        "p95": percentile_nearest_rank(values, 0.95),
        "max": max(values),
    }


def analyze(measurements, thresholds, max_minority_rate):
    if not measurements:
        raise ValueError("at least one telemetry measurement is required")
    sample_count = len(measurements)
    for frame in measurements:
        if len(frame) != RECORD_COUNT:
            raise ValueError("telemetry frame has the wrong record count")

    reference_winners = [record[1] for record in measurements[0]]
    per_index = []
    for index in range(RECORD_COUNT):
        records = [frame[index] for frame in measurements]
        challenges = {record[0] for record in records}
        if len(challenges) != 1:
            raise ValueError(f"challenge changed across samples at index {index}")
        winners = [record[1] for record in records]
        ones = sum(winners)
        minority = min(ones, sample_count - ones)
        count0 = [record[3] for record in records]
        count1 = [record[4] for record in records]
        margins = [record[5] for record in records]
        per_index.append(
            {
                "index": index,
                "challenge": records[0][0],
                "reference_winner": reference_winners[index],
                "consensus_winner": int(ones * 2 >= sample_count),
                "minority_count": minority,
                "minority_rate_percent": minority * 100.0 / sample_count,
                "flips_vs_first_sample": sum(
                    winner != reference_winners[index] for winner in winners
                ),
                "tie_count": sum(record[2] for record in records),
                "count0": summary_stats(count0),
                "count1": summary_stats(count1),
                "margin": summary_stats(margins),
            }
        )

    challenge_to_indices = {}
    for entry in per_index:
        challenge_to_indices.setdefault(entry["challenge"], []).append(entry["index"])
    duplicate_groups = [
        {"challenge": challenge, "indices": indices}
        for challenge, indices in sorted(challenge_to_indices.items())
        if len(indices) > 1
    ]

    sweeps = []
    for threshold in thresholds:
        accepted = [
            entry["index"]
            for entry in per_index
            if entry["margin"]["p01"] >= threshold
            and entry["minority_rate_percent"] <= max_minority_rate
            and entry["tie_count"] == 0
        ]
        sweeps.append(
            {
                "margin_p01_threshold": threshold,
                "max_minority_rate_percent": max_minority_rate,
                "accepted_position_count": len(accepted),
                "accepted_unique_challenge_count": len(
                    {per_index[index]["challenge"] for index in accepted}
                ),
                "accepted_indices": accepted,
                "fe_n264_capacity_met": len(accepted) >= RECORD_COUNT,
            }
        )

    return {
        "metric_scope": "private per-challenge count-margin telemetry",
        "sample_count": sample_count,
        "record_count": RECORD_COUNT,
        "unique_challenge_count": len(challenge_to_indices),
        "duplicate_challenge_groups": duplicate_groups,
        "per_index": per_index,
        "threshold_sweep": sweeps,
        "security": {
            "contains_raw_response_values": False,
            "contains_device_fingerprinting_metadata": True,
            "public_repository_allowed": False,
        },
        "interpretation": (
            "Threshold results are characterization candidates only. A release "
            "mask requires PVT, power-cycle, and multi-board data plus authenticated "
            "device/build binding."
        ),
    }


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(
        description="RO-PUF count-margin characterization (diagnostic image only)"
    )
    parser.add_argument("--port", required=True)
    parser.add_argument("--count", type=int, default=100)
    parser.add_argument("--timeout", type=float, default=10.0)
    parser.add_argument("--bitstream", required=True)
    parser.add_argument("--report", required=True)
    parser.add_argument(
        "--thresholds", default="0,1,2,4,8,16,32",
        help="comma-separated count-margin p01 thresholds",
    )
    parser.add_argument("--max-minority-rate", type=float, default=1.0)
    args = parser.parse_args()
    if args.count <= 0:
        parser.error("--count must be greater than zero")
    if not 0.0 <= args.max_minority_rate <= 50.0:
        parser.error("--max-minority-rate must be between 0 and 50")
    try:
        thresholds = sorted({int(value) for value in args.thresholds.split(",")})
    except ValueError:
        parser.error("--thresholds must contain comma-separated integers")
    if not thresholds or thresholds[0] < 0:
        parser.error("thresholds must be non-negative")
    bitstream = Path(args.bitstream).resolve()
    if not bitstream.is_file():
        parser.error("--bitstream must name an existing file")

    started_utc = datetime.now(timezone.utc).isoformat()
    try:
        measurements, elapsed = collect(args.port, args.count, args.timeout)
        result = analyze(measurements, thresholds, args.max_minority_rate)
    except (RuntimeError, ValueError, serial.SerialException) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1

    result["campaign"] = {
        "started_utc": started_utc,
        "elapsed_seconds": elapsed,
        "board_count": 1,
        "top": "Puf_Characterization_Top",
        "target_part": "xc7z020clg400-2",
        "protocol": "1.1",
        "seed_hex": "42",
        "ref_cycles": 255,
        "local_bitstream_sha256": sha256_file(bitstream),
        "release_equivalence_established": False,
    }
    report = Path(args.report)
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    print("=== RO-PUF COUNT-MARGIN CHARACTERIZATION ===")
    print(f"samples={result['sample_count']} unique_challenges={result['unique_challenge_count']}")
    for sweep in result["threshold_sweep"]:
        print(
            "threshold=%d accepted=%d unique=%d FE-N264=%s"
            % (
                sweep["margin_p01_threshold"],
                sweep["accepted_position_count"],
                sweep["accepted_unique_challenge_count"],
                "YES" if sweep["fe_n264_capacity_met"] else "NO",
            )
        )
    print(f"Private characterization report written to {report}")
    print("SECURITY: do not commit this device-fingerprinting report publicly.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
