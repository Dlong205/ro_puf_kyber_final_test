#!/usr/bin/env python3
"""Collect private count-margin telemetry for an all-pairs RO pool.

PUF32 baseline:  NUM_RO=32, C(32,2)=496 pairs, protocol 2.0.
PUF64 candidate: NUM_RO=64, C(64,2)=2016 pairs, protocol 3.0.

The variant is auto-detected from the device INFO reply and cross-checked
against --num-ro when provided.  Mixing reports from different pools or boards
is refused downstream.
"""

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
RO_COUNT = 32
PAIR_COUNT = 496
RECORD_SIZE = 16
RECORD_STRUCT = struct.Struct("<HBBIII")
ICON_MAGIC = b"PUF"


def canonical_pairs(ro_count=None):
    ro_count = ro_count or RO_COUNT
    return [(a, b) for a in range(ro_count) for b in range(a + 1, ro_count)]


def expected_info_bytes(ro_count, pair_count):
    """INFO payload returned by the rtl endpoint for a given pool."""
    if ro_count == 32:
        return b"PUF\x02\x00\x07"
    if ro_count == 64:
        return bytes([0x50, 0x55, 0x46, 0x03, ro_count,
                      pair_count & 0xFF, (pair_count >> 8) & 0xFF, 0x07])
    raise ValueError(f"unsupported NUM_RO={ro_count}")


def protocol_label(ro_count):
    return "2.0" if ro_count == 32 else "3.0"


def ro_bits(ro_count):
    return max(1, (ro_count - 1).bit_length())


def index_bits(pair_count):
    return max(1, (pair_count - 1).bit_length())


def read_exact(port, length):
    data = port.read(length)
    if len(data) != length:
        raise RuntimeError(f"UART timeout: expected {length} byte(s), got {len(data)}")
    return data


def probe_image(port):
    """Detect the on-board pool from CMD_INFO without trusting the CLI."""
    port.write(bytes([CMD_INFO]))
    header = read_exact(port, 4)
    if header[:3] != ICON_MAGIC:
        raise RuntimeError(
            f"wrong image: expected 'PUF' magic, got {header[:3]!r}"
        )
    proto = header[3]
    if proto == 0x02:
        tail = read_exact(port, 2)
        ro_count, pair_count, capabilities = 32, 496, tail[1]
        if tail[0] != 0x00:
            raise RuntimeError("PUF32 INFO reserved byte is non-zero")
    elif proto == 0x03:
        payload = read_exact(port, 4)
        ro_count = payload[0]
        pair_count = payload[1] | (payload[2] << 8)
        capabilities = payload[3]
    else:
        raise RuntimeError(f"unknown all-pairs protocol version {proto:#04x}")
    if ro_count not in (32, 64):
        raise RuntimeError(f"unsupported NUM_RO={ro_count}")
    if pair_count != ro_count * (ro_count - 1) // 2:
        raise RuntimeError("device INFO self-report contradicts C(NUM_RO,2)")
    return ro_count, pair_count, capabilities


def percentile_nearest_rank(values, percentile):
    ordered = sorted(values)
    rank = max(1, math.ceil(percentile * len(ordered)))
    return ordered[rank - 1]


def assess_order_structure(measurements, ro_count=RO_COUNT,
                           pair_count=PAIR_COUNT, max_phi_pairs=1000):
    """Screen the structural entropy ceiling of the pair-response pool.

    All responses compare the same NUM_RO ring frequencies, so a stable device
    produces essentially one total ordering of the ROs.  The maximum number of
    such orderings is NUM_RO! which bounds the entropy any pair mapping can
    extract.  This routine measures, from the per-frame winner bits:

    - transitivity/cycle rate: the fraction of triples (a<b<c) that violate the
      ordering assumption of a consistent tournament.  Zero cycle rate per frame
      means the frame is exactly one total ordering of the ROs (NUM_RO! states);
    - correlation between pair responses over samples (phi coefficient on a
      deterministic sample of pair combinations).  Constant responses inside one
      power-on show as zero-variance series (in-window variation is not entropy);
    - the honest entropy ceiling log2(NUM_RO!), plus a cross-device note.

    This is a screening metric, not a full entropy estimator: conditional entropy
    given public helper data and the frozen mapping still requires a separate
    analysis.
    """
    sample_count = len(measurements)
    triples = [(a, b, c) for a in range(ro_count)
               for b in range(a + 1, ro_count)
               for c in range(b + 1, ro_count)]
    triple_count = len(triples)
    cycle_violations = []
    winner_frame = []
    for frame in measurements:
        # winner == 0 means count0 > count1, i.e. the first RO in the pair is
        # faster.  faster_matrix[i][j] = 1 if RO i is faster than RO j.
        faster = [[0] * ro_count for _ in range(ro_count)]
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
        (i, j) for i in range(pair_count)
        for j in range(i + 1, pair_count)
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
    ceiling_bits = math.log2(math.factorial(ro_count))
    max_minority = 0.0
    for index in range(pair_count):
        ones = sum(frame[index][2] for frame in measurements)
        minority = min(ones, sample_count - ones)
        rate = 100.0 * minority / sample_count
        max_minority = max(max_minority, rate)
    return {
        "metric": "order-structure screening (not a full entropy estimator)",
        "sample_count": sample_count,
        "ro_count": ro_count,
        "pair_count": pair_count,
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
        "entropy_ceiling_explains_states": f"{ro_count}!",
        "above_128bit_target": ceiling_bits >= 128.0,
        "interpretation": (
            f"Fixed-frequency ROs place every response near a total ordering of "
            f"the {ro_count} oscillators; selected comparisons do not create "
            f"{pair_count} independent entropy bits beyond log2({ro_count}!) "
            f"= {round(ceiling_bits, 1)} bit.  Constant in-window responses "
            f"are expected and mean zero in-window variation, not real entropy. "
            f"Conditional entropy given public helper/mapping needs a separate "
            f"device-ensemble and helper analysis. Correlation screening is NOT "
            f"complete from one device."
        ),
    }


def decode_pair_fields(pair_a_raw, pair_flags, ro_count):
    """Decode the 16-byte record pair fields for the detected NUM_RO.

    PUF32 (protocol 2.0): byte2 = {3'b0, pair_a[4:0]},
                          byte3 = {1'b0, tie, winner, pair_b[4:0]}.
    PUF64 (protocol 3.0): byte2 = {2'b0, pair_a[5:0]},
                          byte3 = {pair_b[5], RESERVED, tie, winner, pair_b[4:0]}.
    """
    rb = ro_bits(ro_count)
    pair_a = pair_a_raw & ((1 << rb) - 1)
    if pair_a_raw & ~((1 << rb) - 1):
        raise RuntimeError("reserved pair_a bits are set")
    winner = (pair_flags >> 5) & 1
    tie = (pair_flags >> 6) & 1
    pair_b_low = pair_flags & 0x1F
    pair_b_high = (pair_flags >> 7) & 1
    pair_b = pair_b_low | (pair_b_high << 5) if ro_count > 32 else pair_b_low
    return pair_a, pair_b, winner, tie


def read_margin(port, ro_count, pair_count):
    expected_pairs = canonical_pairs(ro_count)
    port.write(bytes([CMD_MARGIN]))
    status = read_exact(port, 1)[0]
    if status != STATUS_SUCCESS:
        raise RuntimeError("all-pairs measurement returned non-success status")
    payload = read_exact(port, pair_count * RECORD_SIZE)
    records = []
    for expected_index, expected_pair in enumerate(expected_pairs):
        offset = expected_index * RECORD_SIZE
        index, pair_a_raw, pair_flags, count0, count1, margin = (
            RECORD_STRUCT.unpack_from(payload, offset)
        )
        pair_a, pair_b, winner, tie = decode_pair_fields(
            pair_a_raw, pair_flags, ro_count
        )
        if index != expected_index:
            raise RuntimeError(
                f"telemetry index mismatch: expected {expected_index}, got {index}"
            )
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


def collect(port_name, count, timeout, ro_count):
    pair_count = ro_count * (ro_count - 1) // 2
    measurements = []
    started = time.perf_counter()
    with serial.Serial(port_name, 115200, timeout=timeout) as port:
        time.sleep(0.1)
        port.reset_input_buffer()
        detected_ro, detected_pairs, capabilities = probe_image(port)
        if detected_ro != ro_count:
            raise RuntimeError(
                f"NUM_RO mismatch: --num-ro says {ro_count}, device reports "
                f"{detected_ro}"
            )
        if detected_pairs != pair_count:
            raise RuntimeError("device self-report contradicts --num-ro pool size")
        for index in range(count):
            measurements.append(read_margin(port, ro_count, pair_count))
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
                    max_minority_rate, max_ro_degree, ro_count=RO_COUNT):
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
    degree = [0] * ro_count
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
            select_count=264, selection_threshold=4, max_ro_degree=17,
            ro_count=RO_COUNT, pair_count=PAIR_COUNT):
    if not measurements:
        raise ValueError("at least one all-pairs measurement is required")
    sample_count = len(measurements)
    for frame in measurements:
        if len(frame) != pair_count:
            raise ValueError("all-pairs frame has the wrong record count")

    expected_pairs = canonical_pairs(ro_count)
    per_pair = []
    for index, expected_pair in enumerate(expected_pairs):
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
                "n264_pool_capacity_met": len(accepted) >= select_count,
            }
        )

    preview = select_balanced(
        per_pair, select_count, selection_threshold,
        max_minority_rate, max_ro_degree, ro_count=ro_count
    )
    ceiling = math.log2(math.factorial(ro_count))
    return {
        "metric_scope": (
            f"private {ro_count}-RO all-pairs count-margin telemetry"
        ),
        "sample_count": sample_count,
        "ro_count": ro_count,
        "pair_count": pair_count,
        "pair_schedule": f"lexicographic unordered pairs, 0 <= a < b < {ro_count}",
        "per_pair": per_pair,
        "threshold_sweep": sweeps,
        "selection_preview": preview,
        "assessment": assess_order_structure(
            measurements, ro_count=ro_count, pair_count=pair_count
        ),
        "security": {
            "contains_raw_response_values": False,
            "contains_device_fingerprinting_metadata": True,
            "public_repository_allowed": False,
        },
        "interpretation": (
            f"More pair comparisons improve the candidate pool, not the entropy "
            f"upper bound of the {ro_count} underlying oscillator frequencies: "
            f"log2({ro_count}!) = {round(ceiling, 1)} bit structural ceiling. "
            f"Selection chooses FE positions; it does not certify entropy."
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
        description="Characterize every unordered pair of NUM_RO physical ROs"
    )
    parser.add_argument("--port", required=True)
    parser.add_argument("--count", type=int, default=100)
    parser.add_argument("--timeout", type=float, default=15.0)
    parser.add_argument("--bitstream", required=True)
    parser.add_argument("--report", required=True)
    parser.add_argument(
        "--num-ro", type=int, default=None, choices=[32, 64],
        help="Expected pool size; if omitted the device INFO reply selects it. "
             "A mismatch between CLI and device is refused."
    )
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
    if not 1 <= args.max_ro_degree <= 63:
        parser.error("--max-ro-degree must be between 1 and 63")
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

    ro_count = args.num_ro or RO_COUNT
    pair_count = ro_count * (ro_count - 1) // 2
    deployment_top = (
        "Puf_AllPairs_Characterization_Top" if ro_count == 32
        else "Puf_AllPairs64_Characterization_Top"
    )
    started_utc = datetime.now(timezone.utc).isoformat()
    try:
        measurements, elapsed = collect(args.port, args.count, args.timeout, ro_count)
        result = analyze(
            measurements, thresholds, args.max_minority_rate,
            selection_threshold=args.selection_threshold,
            max_ro_degree=args.max_ro_degree,
            ro_count=ro_count, pair_count=pair_count,
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
        "top": deployment_top,
        "target_part": "xc7z020clg400-2",
        "protocol": protocol_label(ro_count),
        "num_ro": ro_count,
        "pair_count": pair_count,
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

    print(f"=== RO-PUF {ro_count}-RO ALL-PAIRS CHARACTERIZATION (protocol "
          f"{protocol_label(ro_count)}) ===")
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
        "entropy_ceiling=%.2f bits (%d!) above_128=%s"
        % (
            assessment["order_cycle_rate_percent"]["mean"],
            assessment["order_cycle_rate_percent"]["zero_cycle_sample_rate_percent"],
            assessment["entropy_ceiling_bits"],
            ro_count,
            "YES" if assessment["above_128bit_target"] else "NO",
        )
    )
    print(f"Private report written to {report}")
    print("SECURITY: do not commit this device-fingerprinting report publicly.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
