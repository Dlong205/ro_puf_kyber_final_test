#!/usr/bin/env python3
"""Collect private count-margin telemetry for all C(32,2)=496 RO pairs."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import statistics
import struct
import subprocess
import sys
import time

import serial


CMD_INFO = 0x00
CMD_MARGIN = 0x71
STATUS_SUCCESS = 0xAA
EXPECTED_INFO = b"PUF\x02\x00\x07"
RO_COUNT = 32
PAIR_COUNT = 496
RECORD_SIZE = 16
RECORD_STRUCT = struct.Struct("<HBBIII")


def canonical_pairs():
    return [(a, b) for a in range(RO_COUNT) for b in range(a + 1, RO_COUNT)]


EXPECTED_PAIRS = canonical_pairs()


def read_exact(port, length):
    data = port.read(length)
    if len(data) != length:
        raise RuntimeError(f"UART timeout: expected {length} byte(s), got {len(data)}")
    return data


def percentile_nearest_rank(values, percentile):
    ordered = sorted(values)
    rank = max(1, math.ceil(percentile * len(ordered)))
    return ordered[rank - 1]


def assess_order_structure(measurements, max_phi_pairs=1000):
    """Screen the structural entropy ceiling of the 496-response pool.

    All 496 responses compare the same 32 ring frequencies, so a stable device
    produces essentially one total ordering of the 32 ROs.  The maximum number
    of such orderings is 32! which bounds the entropy that any 264-pair mapping
    can extract.  This routine measures, from the per-frame winner bits:

    - transitivity/cycle rate: the fraction of triples (a<b<c) that violate the
      ordering assumption of a consistent tournament.  Zero cycle rate per frame
      means the frame is exactly one total ordering of the ROs (32! states);
    - correlation between pair responses over samples (phi coefficient on a
      deterministic sample of pair combinations).  Constant responses inside one
      power-on show as zero-variance series (in-window variation is not entropy);
    - the honest entropy ceiling log2(32!), plus a cross-device note.

    This is a screening metric, not a full entropy estimator: conditional entropy
    given public helper data and the frozen mapping still requires a separate
    analysis.
    """
    sample_count = len(measurements)
    triples = [(a, b, c) for a in range(RO_COUNT)
               for b in range(a + 1, RO_COUNT)
               for c in range(b + 1, RO_COUNT)]
    triple_count = len(triples)
    cycle_violations = []
    winner_frame = []
    for frame in measurements:
        # winner == 0 means count0 > count1, i.e. the first RO in the pair is
        # faster.  faster_matrix[i][j] = 1 if RO i is faster than RO j.
        faster = [[0] * RO_COUNT for _ in range(RO_COUNT)]
        for a, b, winner, tie, count0, count1, margin in frame:
            faster[a][b] = 0 if winner else 1
            faster[b][a] = 1 if winner else 0
        winner_frame.append(faster)
        violations = 0
        for a, b, c in triples:
            ab, bc, ac = faster[a][b], faster[b][c], faster[a][c]
            # Transitivity only constrains ab==bc: ab=bc=1 requires ac=1,
            # ab=bc=0 requires ac=0.  ab != bc leaves ac unconstrained.
            if ab == 1 and bc == 1 and ac != 1:
                violations += 1
            elif ab == 0 and bc == 0 and ac != 0:
                violations += 1
        cycle_violations.append(violations)
    cycle_rate_mean = 100.0 * sum(cycle_violations) / sample_count / triple_count

    phi_samples = []
    phi_undefined = 0
    all_combos = [
        (i, j) for i in range(PAIR_COUNT)
        for j in range(i + 1, PAIR_COUNT)
    ]
    combo_step = max(1, len(all_combos) // max_phi_pairs)
    pair_combos = all_combos[::combo_step]
    if pair_combos:
        for i, j in pair_combos:
            series_i = [frame[i][2] for frame in measurements]
            series_j = [frame[j][2] for frame in measurements]
            n11 = sum(x == 1 and y == 1 for x, y in zip(series_i, series_j))
            n00 = sum(x == 0 and y == 0 for x, y in zip(series_i, series_j))
            n10 = sum(x == 1 and y == 0 for x, y in zip(series_i, series_j))
            n01 = sum(x == 0 and y == 1 for x, y in zip(series_i, series_j))
            row = n11 + n10
            col = n11 + n01
            denom = math.sqrt(row * (sample_count - row) * col * (sample_count - col))
            if denom == 0:
                phi_undefined += 1
                continue
            phi = (n11 * n00 - n10 * n01) / denom
            phi_samples.append(abs(phi))
    phi_mean = (sum(phi_samples) / len(phi_samples)) if phi_samples else None
    phi_abs_list = sorted(phi_samples)
    phi_p95 = (phi_abs_list[int(0.95 * len(phi_abs_list))]
               if phi_abs_list else None)
    ceiling_bits = math.log2(math.factorial(RO_COUNT))
    max_minority = 0.0
    for index in range(PAIR_COUNT):
        ones = sum(frame[index][2] for frame in measurements)
        minority = min(ones, sample_count - ones)
        rate = 100.0 * minority / sample_count
        max_minority = max(max_minority, rate)
    return {
        "metric": "order-structure screening (not a full entropy estimator)",
        "sample_count": sample_count,
        "ro_count": RO_COUNT,
        "pair_count": PAIR_COUNT,
        "order_cycle_rate_percent": {
            "mean": round(cycle_rate_mean, 4),
            "max_single_sample": round(100.0 * max(cycle_violations) / triple_count, 4),
            "zero_cycle_sample_rate_percent": round(
                100.0 * sum(v == 0 for v in cycle_violations) / sample_count, 4),
        },
        "pairwise_phi_abs": {
            "pair_combos_sampled": len(pair_combos),
            "with_defined_phi": len(phi_samples),
            "undefined_constant_pairs": phi_undefined,
            "mean": round(phi_mean, 4) if phi_mean is not None else None,
            "p95": round(phi_p95, 4) if phi_p95 is not None else None,
        },
        "bias_strongest_minority_percent": round(max_minority, 4),
        "entropy_ceiling_bits": round(ceiling_bits, 3),
        "entropy_ceiling_explains_states": "32!",
        "above_128bit_target": ceiling_bits >= 128.0,
        "interpretation": (
            "Fixed-frequency ROs place every response near a total ordering of "
            "the 32 oscillators; 264 selected comparisons do not create 264 "
            "independent entropy bits. log2(32!) ~= 117.7 bit is below the "
            "128-bit ML-KEM-512 target, before any bias or selection loss. "
            "Constant in-window responses are expected and mean zero in-window "
            "variation, not real entropy. Conditional entropy given public "
            "helper/mapping needs a separate device-ensemble and helper "
            "analysis. Correlation screening is NOT complete from one device."
        ),
    }


def read_margin(port):
    port.write(bytes([CMD_MARGIN]))
    status = read_exact(port, 1)[0]
    if status != STATUS_SUCCESS:
        raise RuntimeError("all-pairs measurement returned non-success status")
    payload = read_exact(port, PAIR_COUNT * RECORD_SIZE)
    records = []
    for expected_index, expected_pair in enumerate(EXPECTED_PAIRS):
        offset = expected_index * RECORD_SIZE
        index, pair_a_raw, pair_flags, count0, count1, margin = (
            RECORD_STRUCT.unpack_from(payload, offset)
        )
        pair_a = pair_a_raw & 0x1F
        pair_b = pair_flags & 0x1F
        winner = (pair_flags >> 5) & 1
        tie = (pair_flags >> 6) & 1
        if index != expected_index:
            raise RuntimeError(
                f"telemetry index mismatch: expected {expected_index}, got {index}"
            )
        if pair_a_raw & 0xE0 or pair_flags & 0x80:
            raise RuntimeError(f"reserved pair bits set at index {index}")
        if (pair_a, pair_b) != expected_pair:
            raise RuntimeError(
                f"pair schedule mismatch at {index}: expected {expected_pair}, "
                f"got {(pair_a, pair_b)}"
            )
        expected_margin = abs(count0 - count1)
        expected_winner = 0 if count0 > count1 else 1
        if margin != expected_margin or winner != expected_winner:
            raise RuntimeError(f"incoherent telemetry record at index {index}")
        if tie != int(count0 == count1):
            raise RuntimeError(f"incorrect tie flag at index {index}")
        records.append((pair_a, pair_b, winner, tie, count0, count1, margin))
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
            raise RuntimeError("wrong image or all-pairs protocol 2.0 is unsupported")
        for index in range(count):
            measurements.append(read_margin(port))
            if (index + 1) % 10 == 0 or index + 1 == count:
                print(f"[{index + 1}/{count}] all-pairs frames collected", flush=True)
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


def select_balanced(entries, select_count, margin_threshold,
                    max_minority_rate, max_ro_degree):
    """Produce a deterministic preview while limiting repeated use of one RO.

    This is not an entropy estimator and must not be promoted directly into a
    release mapping.  It is only a feasibility check for a later train/holdout
    selection across boards and PVT conditions.
    """
    candidates = [
        entry for entry in entries
        if entry["margin"]["p01"] >= margin_threshold
        and entry["minority_rate_percent"] <= max_minority_rate
        and entry["tie_count"] == 0
    ]
    candidates.sort(
        key=lambda entry: (
            -entry["margin"]["p01"],
            entry["minority_rate_percent"],
            -entry["margin"]["p05"],
            entry["pair"][0],
            entry["pair"][1],
        )
    )
    degree = [0] * RO_COUNT
    selected = []
    remaining = candidates[:]
    while remaining and len(selected) < select_count:
        feasible = [
            entry for entry in remaining
            if degree[entry["pair"][0]] < max_ro_degree
            and degree[entry["pair"][1]] < max_ro_degree
        ]
        if not feasible:
            break
        # Prefer strong margin, but among similar candidates penalize already
        # heavily used endpoints so the preview does not collapse onto a few ROs.
        best = min(
            feasible,
            key=lambda entry: (
                max(degree[entry["pair"][0]], degree[entry["pair"][1]]),
                degree[entry["pair"][0]] + degree[entry["pair"][1]],
                -entry["margin"]["p01"],
                entry["minority_rate_percent"],
                entry["pair"][0],
                entry["pair"][1],
            ),
        )
        remaining.remove(best)
        selected.append(best)
        degree[best["pair"][0]] += 1
        degree[best["pair"][1]] += 1
    return {
        "requested_count": select_count,
        "selected_count": len(selected),
        "complete": len(selected) == select_count,
        "criteria": {
            "margin_p01_min": margin_threshold,
            "minority_rate_percent_max": max_minority_rate,
            "tie_count": 0,
            "max_ro_degree": max_ro_degree,
        },
        "ro_degree": degree,
        "pairs": [entry["pair"] for entry in selected],
        "warning": (
            "Preview only; select on multi-board/PVT training data and validate "
            "on held-out boards before generating an authenticated mapping."
        ),
    }


def analyze(measurements, thresholds, max_minority_rate,
            select_count=264, selection_threshold=4, max_ro_degree=17):
    if not measurements:
        raise ValueError("at least one all-pairs measurement is required")
    sample_count = len(measurements)
    for frame in measurements:
        if len(frame) != PAIR_COUNT:
            raise ValueError("all-pairs frame has the wrong record count")

    per_pair = []
    for index, expected_pair in enumerate(EXPECTED_PAIRS):
        records = [frame[index] for frame in measurements]
        pairs = {(record[0], record[1]) for record in records}
        if pairs != {expected_pair}:
            raise ValueError(f"pair changed across samples at index {index}")
        winners = [record[2] for record in records]
        ones = sum(winners)
        minority = min(ones, sample_count - ones)
        per_pair.append(
            {
                "index": index,
                "pair": list(expected_pair),
                "consensus_winner": int(ones * 2 >= sample_count),
                "minority_count": minority,
                "minority_rate_percent": minority * 100.0 / sample_count,
                "tie_count": sum(record[3] for record in records),
                "count0": summary_stats([record[4] for record in records]),
                "count1": summary_stats([record[5] for record in records]),
                "margin": summary_stats([record[6] for record in records]),
            }
        )

    sweeps = []
    for threshold in thresholds:
        accepted = [
            entry for entry in per_pair
            if entry["margin"]["p01"] >= threshold
            and entry["minority_rate_percent"] <= max_minority_rate
            and entry["tie_count"] == 0
        ]
        sweeps.append(
            {
                "margin_p01_threshold": threshold,
                "accepted_pair_count": len(accepted),
                "n264_pool_capacity_met": len(accepted) >= 264,
            }
        )

    preview = select_balanced(
        per_pair, select_count, selection_threshold,
        max_minority_rate, max_ro_degree
    )
    return {
        "metric_scope": "private 32-RO all-pairs count-margin telemetry",
        "sample_count": sample_count,
        "ro_count": RO_COUNT,
        "pair_count": PAIR_COUNT,
        "pair_schedule": "lexicographic unordered pairs, 0 <= a < b < 32",
        "per_pair": per_pair,
        "threshold_sweep": sweeps,
        "selection_preview": preview,
        "assessment": assess_order_structure(measurements),
        "security": {
            "contains_raw_response_values": False,
            "contains_device_fingerprinting_metadata": True,
            "public_repository_allowed": False,
        },
        "interpretation": (
            "More pair comparisons improve the candidate pool, not the entropy "
            "upper bound of 32 underlying oscillator frequencies."
        ),
    }


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def git_commit_hash(root=None):
    """Resolve the current git HEAD for build traceability without requiring it."""
    try:
        cwd = root or Path(Path(__file__).resolve().parent.parent)
        output = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=cwd, capture_output=True, check=True, text=True, timeout=10,
        )
        return output.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return "UNKNOWN"


def main():
    parser = argparse.ArgumentParser(
        description="Characterize every unordered pair of 32 physical ROs"
    )
    parser.add_argument("--port", required=True)
    parser.add_argument("--count", type=int, default=100)
    parser.add_argument("--timeout", type=float, default=15.0)
    parser.add_argument("--bitstream", required=True)
    parser.add_argument("--report", required=True)
    parser.add_argument(
        "--board-id", default="UNSPECIFIED",
        help="Pseudonymous device ID; required later for train/holdout qualification"
    )
    parser.add_argument(
        "--boot-index", required=True, type=int,
        help="Monotonic power-cycle/boot session index; disjoint train/holdout "
             "sessions must never share a boot index"
    )
    parser.add_argument(
        "--condition-id", default="UNSPECIFIED",
        help="Campaign condition/boot label, for example room-coldboot-001"
    )
    parser.add_argument(
        "--build-commit", default=None,
        help="git commit of the characterization image; defaults to this repo HEAD"
    )
    parser.add_argument(
        "--fingerprint-file", default=None,
        help="path to the locked-image RO physical fingerprint .tsv whose SHA-256 is recorded"
    )
    parser.add_argument("--thresholds", default="0,1,2,4,8,16,32")
    parser.add_argument("--max-minority-rate", type=float, default=1.0)
    parser.add_argument("--selection-threshold", type=int, default=4)
    parser.add_argument("--max-ro-degree", type=int, default=17)
    args = parser.parse_args()
    if args.count <= 0:
        parser.error("--count must be greater than zero")
    if not 0.0 <= args.max_minority_rate <= 50.0:
        parser.error("--max-minority-rate must be between 0 and 50")
    if args.selection_threshold < 0:
        parser.error("--selection-threshold must be non-negative")
    if not 1 <= args.max_ro_degree <= 31:
        parser.error("--max-ro-degree must be between 1 and 31")
    if args.boot_index <= 0:
        parser.error("--boot-index must be a positive integer")
    try:
        thresholds = sorted({int(value) for value in args.thresholds.split(",")})
    except ValueError:
        parser.error("--thresholds must contain comma-separated integers")
    if not thresholds or thresholds[0] < 0:
        parser.error("thresholds must be non-negative")
    bitstream = Path(args.bitstream).resolve()
    if not bitstream.is_file():
        parser.error("--bitstream must name an existing file")
    fingerprint_hash = "UNKNOWN"
    if args.fingerprint_file:
        fingerprint_path = Path(args.fingerprint_file).resolve()
        if not fingerprint_path.is_file():
            parser.error("--fingerprint-file must name an existing file")
        fingerprint_hash = sha256_file(fingerprint_path)

    started_utc = datetime.now(timezone.utc).isoformat()
    try:
        measurements, elapsed = collect(args.port, args.count, args.timeout)
        result = analyze(
            measurements, thresholds, args.max_minority_rate,
            selection_threshold=args.selection_threshold,
            max_ro_degree=args.max_ro_degree,
        )
    except (RuntimeError, ValueError, serial.SerialException) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1

    result["campaign"] = {
        "started_utc": started_utc,
        "elapsed_seconds": elapsed,
        "board_count": 1,
        "board_id": args.board_id,
        "boot_index": args.boot_index,
        "condition_id": args.condition_id,
        "top": "Puf_AllPairs_Characterization_Top",
        "target_part": "xc7z020clg400-2",
        "protocol": "2.0",
        "ref_cycles": 255,
        "clock_mhz": 100,
        "local_bitstream_sha256": sha256_file(bitstream),
        "build_commit": args.build_commit or git_commit_hash(),
        "build_datetime": "2026-09-18",
        "placement_fingerprint_sha256": fingerprint_hash,
        "release_equivalence_established": False,
    }
    report = Path(args.report)
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")

    print("=== RO-PUF 32-RO ALL-PAIRS CHARACTERIZATION ===")
    print(f"samples={result['sample_count']} pairs={result['pair_count']}")
    for sweep in result["threshold_sweep"]:
        print(
            "threshold=%d accepted=%d N264=%s"
            % (
                sweep["margin_p01_threshold"],
                sweep["accepted_pair_count"],
                "YES" if sweep["n264_pool_capacity_met"] else "NO",
            )
        )
    preview = result["selection_preview"]
    print(
        "selection_preview=%d/%d degree_min=%d degree_max=%d complete=%s"
        % (
            preview["selected_count"], preview["requested_count"],
            min(preview["ro_degree"]), max(preview["ro_degree"]),
            "YES" if preview["complete"] else "NO",
        )
    )
    assessment = result["assessment"]
    print(
        "order_cycle_rate_mean=%.3f%% zero_cycle_sample=%s%% "
        "entropy_ceiling=%.2f bits (32!) above_128=%s"
        % (
            assessment["order_cycle_rate_percent"]["mean"],
            assessment["order_cycle_rate_percent"]["zero_cycle_sample_rate_percent"],
            assessment["entropy_ceiling_bits"],
            "YES" if assessment["above_128bit_target"] else "NO",
        )
    )
    print(f"Private report written to {report}")
    print("SECURITY: do not commit this device-fingerprinting report publicly.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
