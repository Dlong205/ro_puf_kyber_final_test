#!/usr/bin/env python3
"""Characterize raw RO-PUF stability without persisting response values."""

import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import statistics
import sys
import time

import serial


CMD_INFO = 0x00
CMD_RAW = 0x70
STATUS_SUCCESS = 0xAA
RAW_BYTES = 33
RAW_BITS = 264
EXPECTED_INFO = b"PUF\x01\x00\x01"
REPEATED_CHALLENGE_OFFSET = 255
REPEATED_CHALLENGE_COUNT = RAW_BITS - REPEATED_CHALLENGE_OFFSET


def read_exact(port, length):
    data = port.read(length)
    if len(data) != length:
        raise RuntimeError(f"UART timeout: expected {length} byte(s), got {len(data)}")
    return data


def percentile_nearest_rank(values, percentile):
    ordered = sorted(values)
    rank = max(1, math.ceil(percentile * len(ordered)))
    return ordered[rank - 1]


def distance_stats(values):
    return {
        "min": min(values),
        "mean": statistics.fmean(values),
        "p50": percentile_nearest_rank(values, 0.50),
        "p95": percentile_nearest_rank(values, 0.95),
        "p99": percentile_nearest_rank(values, 0.99),
        "max": max(values),
    }


def read_raw(port):
    port.write(bytes([CMD_RAW]))
    status = read_exact(port, 1)[0]
    if status != STATUS_SUCCESS:
        raise RuntimeError("raw measurement returned non-success status")
    return int.from_bytes(read_exact(port, RAW_BYTES), "little")


def collect(port_name, count, timeout):
    responses = []
    counts = Counter()
    started = time.perf_counter()

    with serial.Serial(port_name, 115200, timeout=timeout) as port:
        time.sleep(0.1)
        port.reset_input_buffer()
        port.write(bytes([CMD_INFO]))
        info = read_exact(port, len(EXPECTED_INFO))
        if info != EXPECTED_INFO:
            raise RuntimeError("wrong image or unsupported characterization protocol")

        # Keep this measurement separate from the statistical sample set. It
        # models a fixed enrollment response for BCH-radius qualification.
        enrollment_reference = read_raw(port)
        for index in range(count):
            response = read_raw(port)
            responses.append(response)
            counts[response] += 1
            if (index + 1) % 1000 == 0 or index + 1 == count:
                print(
                    f"[{index + 1}/{count}] unique raw responses={len(counts)}",
                    flush=True,
                )

    return enrollment_reference, responses, time.perf_counter() - started


def analyze(enrollment_reference, responses):
    if not responses:
        raise ValueError("at least one measured response is required")
    count = len(responses)
    response_counts = Counter(responses)
    whole_mode, whole_mode_count = response_counts.most_common(1)[0]
    ones = [sum((value >> bit) & 1 for value in responses) for bit in range(RAW_BITS)]
    consensus = sum(
        1 << bit
        for bit, one_count in enumerate(ones)
        if one_count * 2 >= count
    )

    hd_reference = [(value ^ enrollment_reference).bit_count() for value in responses]
    hd_consensus = [(value ^ consensus).bit_count() for value in responses]
    hd_whole_mode = [(value ^ whole_mode).bit_count() for value in responses]
    reference_errors = [
        sum(((value ^ enrollment_reference) >> bit) & 1 for value in responses)
        for bit in range(RAW_BITS)
    ]
    minority_counts = [min(one_count, count - one_count) for one_count in ones]
    unstable = [bit for bit, flips in enumerate(minority_counts) if flips]
    worst_bits = sorted(
        unstable, key=lambda bit: minority_counts[bit], reverse=True
    )[:16]

    repeated_pair_mismatches = [
        sum(
            ((value >> bit) & 1)
            != ((value >> (bit + REPEATED_CHALLENGE_OFFSET)) & 1)
            for value in responses
        )
        for bit in range(REPEATED_CHALLENGE_COUNT)
    ]

    return {
        "metric_scope": "raw 264-bit response; one board and one diagnostic bitstream",
        "sample_count": count,
        "enrollment_reference_samples": 1,
        "unique_raw_responses": len(response_counts),
        "whole_response_mode_rate_percent": whole_mode_count * 100.0 / count,
        "bitwise_consensus_is_observed_response": consensus in response_counts,
        "intra_hd_to_enrollment_reference": distance_stats(hd_reference),
        "intra_hd_to_whole_response_mode": distance_stats(hd_whole_mode),
        "intra_hd_to_bitwise_consensus": distance_stats(hd_consensus),
        "samples_over_bch_t8_vs_enrollment_reference": sum(
            distance > 8 for distance in hd_reference
        ),
        "samples_over_bch_t8_vs_bitwise_consensus": sum(
            distance > 8 for distance in hd_consensus
        ),
        "unstable_bit_count_vs_consensus": len(unstable),
        "worst_minority_flip_rate_percent": max(minority_counts) * 100.0 / count,
        "worst_unstable_bits": [
            {
                "bit_index": bit,
                "minority_count": minority_counts[bit],
                "minority_rate_percent": minority_counts[bit] * 100.0 / count,
                "error_count_vs_enrollment_reference": reference_errors[bit],
            }
            for bit in worst_bits
        ],
        "per_bit_error_counts_vs_enrollment_reference": reference_errors,
        "per_bit_minority_counts_vs_consensus": minority_counts,
        "repeated_challenge_pairs": {
            "pairs": [
                {"first_bit": bit, "repeated_bit": bit + REPEATED_CHALLENGE_OFFSET}
                for bit in range(REPEATED_CHALLENGE_COUNT)
            ],
            "mismatch_counts": repeated_pair_mismatches,
            "total_mismatches": sum(repeated_pair_mismatches),
        },
        "all_zero_response_count": response_counts[0],
        "all_one_response_count": response_counts[(1 << RAW_BITS) - 1],
        "response_uniformity_percent": {
            "mean": statistics.fmean(value.bit_count() for value in responses)
            * 100.0
            / RAW_BITS,
            "min": min(value.bit_count() for value in responses) * 100.0 / RAW_BITS,
            "max": max(value.bit_count() for value in responses) * 100.0 / RAW_BITS,
        },
        "consecutive_transitions": sum(
            responses[index] != responses[index - 1]
            for index in range(1, count)
        ),
        "raw_response_values_written_by_tool": False,
    }


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(
        description="Raw RO-PUF characterization (diagnostic bitstream only)"
    )
    parser.add_argument("--port", required=True, help="Stable UART device path")
    parser.add_argument("--count", type=int, default=1000)
    parser.add_argument("--timeout", type=float, default=10.0)
    parser.add_argument(
        "--bitstream",
        required=True,
        help="Local diagnostic bitstream used to identify this campaign",
    )
    parser.add_argument(
        "--report",
        help="Optional JSON summary path; raw responses are never written",
    )
    args = parser.parse_args()
    if args.count <= 0:
        parser.error("--count must be greater than zero")
    bitstream_path = Path(args.bitstream).resolve()
    if not bitstream_path.is_file():
        parser.error("--bitstream must name an existing file")

    started_utc = datetime.now(timezone.utc).isoformat()
    try:
        enrollment_reference, responses, elapsed = collect(
            args.port, args.count, args.timeout
        )
        result = analyze(enrollment_reference, responses)
    except (RuntimeError, serial.SerialException, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1

    result["campaign"] = {
        "started_utc": started_utc,
        "elapsed_seconds": elapsed,
        "board_count": 1,
        "top": "Puf_Characterization_Top",
        "target_part": "xc7z020clg400-2",
        "seed_hex": "42",
        "ref_cycles": 255,
        "response_bits": RAW_BITS,
        "lfsr_period": 255,
        "repeated_challenge_count": REPEATED_CHALLENGE_COUNT,
        "ro_lut_loc_bel_locked": True,
        "ro_routing_locked": False,
        "release_equivalence_established": False,
        "local_bitstream_sha256": sha256_file(bitstream_path),
        "bitstream_identity_scope": (
            "hash identifies the supplied local file; UART protocol cannot attest "
            "the image programmed in PL"
        ),
    }

    print("=== RAW RO-PUF CHARACTERIZATION ===")
    print(json.dumps(result, indent=2, sort_keys=True))
    print(
        "SECURITY: this tool did not write raw response values to a file. "
        "Process memory may still be subject to OS swap/core-dump policy. "
        "Reprogram the release bitstream after characterization."
    )
    if args.report:
        report_path = Path(args.report)
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(
            json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        print(f"Non-secret summary written to {report_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
