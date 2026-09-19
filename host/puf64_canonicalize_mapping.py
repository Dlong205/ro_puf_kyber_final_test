#!/usr/bin/env python3
"""Canonicalize the holdout-qualified PUF64 mapping and derive its wire tag.

Produces two non-secret artifacts:
  * ``*.canonical.json``: canonical serialization bytes that are hashed.
  * ``*.public.json``: the public manifest = canonical payload + full
    SHA3-256 digest + truncated 16-bit on-wire tag + wire-encoding facts.

The canonical payload contains no raw response, no 264-bit reference, no
helper secret, no fingerprint and no private paths.  The on-wire ``mapping_tag``
is the little-endian low 16 bits of the full digest; it is a configuration
mismatch identifier, NOT a cryptographic binding (KCV owns same-root).

Wire width was read from the single source of truth, not assumed:
``scripts/helper_record_spec.py`` / ``rtl/top/helper_record_spec.vh`` /
``firmware/helper_record_spec.h`` define ``mapping_len`` as 1 byte (offset 8)
and ``mapping_tag`` as 2 bytes little-endian (offset 9).  ``mapping_len=264``
does NOT fit in one byte: that is reported as a blocker and the field is left
unchanged (no RTL/protocol edit here).
"""

import argparse
import hashlib
import json
from pathlib import Path
import sys

SCHEMA = "ro-puf-final-mapping-canonical-v1"
PUBLIC_SCHEMA = "ro-puf-final-mapping-public-v1"
STATUS = "RELIABILITY_QUALIFIED_ZYNQ_A01_GOLDEN_BITSTREAM"
ALGORITHM = "puf64-train-select-v1"
MAPPING_TAG_WIDTH_BITS = 16
MAPPING_LEN_WIDTH_BITS = 8
MAPPING_TAG_BYTE_ORDER = "little"

LIMITATIONS = [
    "Single device ZYNQ-A01; inter-device uniqueness NOT established.",
    "10 independent cold-boot holdout sessions on one golden bitstream.",
    "500 holdout frames are NOT 500 independent cold boots.",
    "Temperature and voltage variation NOT evaluated (no PVT qualification).",
    "min-entropy 256 bit NOT proven; log2(64!) is a structural order ceiling only.",
    "On-wire mapping_tag is a 16-bit configuration mismatch identifier, not a "
    "cryptographic collision-resistant binding; the KCV is the same-root check.",
    "Response balance (152/112) is an observation, never a selection criterion.",
    "Not an operational release; not ASIC qualified.",
]


def canonical_bytes(payload):
    """Exact hashed serialization.

    UTF-8, no BOM, keys sorted by Unicode code point, no insignificant
    whitespace (``,``/``:`` separators), ASCII-escaped, integers decimal with
    no leading zeros, SHA fields lowercase hex without ``0x``, pairs as
    ``[a,b]`` in frozen order.  No trailing newline: the file writes exactly
    one ``\\n`` after these bytes, and the hash covers the bytes without it.
    """
    return json.dumps(payload, sort_keys=True, separators=(",", ":"),
                      ensure_ascii=True).encode("utf-8")


def digest_and_tag(canonical):
    digest = hashlib.sha3_256(canonical).hexdigest()
    tag = int.from_bytes(bytes.fromhex(digest)[:2], "little")
    if tag == 0:
        tag = 0x0001  # documented reserved adjustment; must be nonzero
    return digest, tag


def assemble_payload(golden, mapping, train_input, holdout_input,
                     holdout_report, mapping_sha, report_sha):
    config = mapping.get("config", {})
    pairs = mapping["pairs"]
    degree = mapping["ro_degree"]
    hist = {}
    for value in degree:
        hist[str(value)] = hist.get(str(value), 0) + 1
    return {
        "schema": SCHEMA,
        "status": STATUS,
        "algorithm": ALGORITHM,
        "board_id": golden["board_id"],
        "part": golden["part"],
        "protocol": golden["protocol"],
        "build_id": golden["build_id"],
        "topology_id": golden["topology_id"],
        "topology_id_semantics": golden["topology_id_semantics"],
        "measurement_architecture_tuple":
            golden["measurement_architecture_tuple"],
        "num_ro": golden["num_ro"],
        "pair_count": golden["pair_count"],
        "mapping_length": len(pairs),
        "counter_width": golden["width"],
        "ripple_stages_per_ro": golden["ripple_stages_per_ro"],
        "clock_input_hz": golden["clock_input_hz"],
        "clock_system_hz": golden["clock_system_hz"],
        "ref_cycles": golden["ref_cycles"],
        "measurement_window_ns": golden["measurement_window_ns"],
        "bitstream_sha256": golden["bitstream_sha256"],
        "route_fingerprint_sha256": golden["route_fingerprint_sha256"],
        "lock_level": golden["lock_level"],
        "fixed_route": golden["fixed_route"],
        "pairs": pairs,
        "ro_degree": degree,
        "degree_histogram": hist,
        "selection_sha256": mapping["selection_sha256"],
        "mapping_candidate_sha256": mapping_sha,
        "train_input_aggregate_sha256": train_input["aggregate_sha256"],
        "holdout_input_aggregate_sha256": holdout_input["aggregate_sha256"],
        "holdout_report_sha256": report_sha,
        "train_boot_count": len(mapping.get("train_boots", [])),
        "holdout_boot_count": len(holdout_input.get("boots", [])),
        "train_boots": list(mapping.get("train_boots", [])),
        "holdout_boots": [entry["boot_index"]
                          for entry in holdout_input.get("boots", [])],
        "thresholds": {
            "min_boots": str(config.get("min_boots")),
            "max_minority_rate_percent": "10.0",
            "min_margin_p01": "4.0",
            "select_count": str(config.get("select_count")),
            "degree_high": str(config.get("degree_high")),
        },
        "holdout_gate": holdout_report["gate"],
        "holdout_passed": bool(holdout_report["passed"]),
        "holdout_metrics": {
            "frames": holdout_report["frames_observed"],
            "independent_boots": holdout_report["independent_boots"],
            "errors_per_vector_p50": holdout_report["p50"],
            "errors_per_vector_p95": holdout_report["p95"],
            "errors_per_vector_p99": holdout_report["p99"],
            "errors_per_vector_max": holdout_report["max"],
            "frames_errors_0": holdout_report["frame_error_histogram"]["errors_0"],
            "frames_errors_1_4":
                holdout_report["frame_error_histogram"]["errors_1_4"],
            "frames_errors_5_8":
                holdout_report["frame_error_histogram"]["errors_5_8"],
            "frames_errors_over_8":
                holdout_report["frame_error_histogram"]["errors_over_8"],
            "frames_over_bch": holdout_report["frames_over_bch"],
            "boots_majority_over_bch": holdout_report["boots_majority_over_bch"],
            "observed_frr": holdout_report["observed_frr"],
            "selected_pairs_with_any_error":
                holdout_report["selected_pair_error_frequency"]
                ["pairs_with_any_error"],
            "selected_pairs_with_tie": holdout_report["selected_pairs_with_tie"],
            "selected_pairs_with_minority":
                holdout_report["selected_pairs_with_minority"],
            "selected_margin_p01_worst":
                holdout_report["selected_margin_p01"]["worst"],
            "selected_margin_p01_median":
                holdout_report["selected_margin_p01"]["median"],
            "selected_margin_p50_median":
                holdout_report["selected_margin_p50_median"],
            "response_balance_ones":
                holdout_report["selected_response_balance"]["ones"],
            "response_balance_zeros":
                holdout_report["selected_response_balance"]["zeros"],
        },
        "limitations": LIMITATIONS,
    }


def verify_inputs(golden, mapping, train_input, holdout_input, holdout_report,
                  mapping_sha, report_sha, mapping_path, report_path):
    problems = []
    if not golden.get("holdout_eligible"):
        problems.append("golden holdout_eligible is not true")
    if golden.get("mapping_tag") not in (0, None):
        problems.append("golden mapping_tag is already nonzero")
    if holdout_report.get("passed") is not True:
        problems.append("holdout report did not PASS")
    if not all(holdout_report.get("gate", {}).values()):
        problems.append("holdout gate has a failed condition")
    if mapping.get("selection_sha256") != holdout_input.get(
            "candidate_selection_sha256"):
        problems.append("selection hash != frozen holdout candidate")
    if mapping_sha != holdout_input.get("candidate_mapping_file_sha256"):
        problems.append("mapping file SHA != frozen holdout candidate")
    if train_input.get("aggregate_sha256") != holdout_input.get(
            "train_input_aggregate_sha256"):
        problems.append("train-input hash != frozen holdout candidate")
    if report_sha != hashlib.sha256(Path(report_path).read_bytes()).hexdigest():
        problems.append("holdout report SHA mismatch")
    if len(mapping.get("pairs", [])) != 264:
        problems.append("selected pair list is not 264")
    if sorted(set(mapping.get("source_pair_indices", []))) != \
            sorted(mapping.get("source_pair_indices", [])):
        problems.append("duplicate selected pair index")
    del mapping_path  # kept for interface symmetry
    return problems


def derive_public(canonical, digest, tag):
    return {
        "schema": PUBLIC_SCHEMA,
        "status": STATUS,
        "canonical_schema": SCHEMA,
        "canonical_bytes_sha256": hashlib.sha256(canonical).hexdigest(),
        "full_mapping_digest_sha3_256": digest,
        "mapping_tag": tag,
        "mapping_tag_hex": "0x%04x" % tag,
        "mapping_tag_width_bits": MAPPING_TAG_WIDTH_BITS,
        "mapping_tag_byte_order": MAPPING_TAG_BYTE_ORDER,
        "mapping_length": 264,
        "wire_encoding": {
            "source_of_truth": "scripts/helper_record_spec.py",
            "helper_record": "76-byte record, all multi-byte fields little-endian",
            "mapping_len": {
                "offset": 8,
                "width_bits": MAPPING_LEN_WIDTH_BITS,
                "status": "BLOCKED",
                "blocker": "mapping_len=264 does not fit in the 1-byte u8 "
                           "field (max 255); a protocol/RTL revision is "
                           "required and was intentionally NOT made during "
                           "canonicalization",
            },
            "mapping_tag": {
                "offset": 9,
                "width_bits": MAPPING_TAG_WIDTH_BITS,
                "byte_order": MAPPING_TAG_BYTE_ORDER,
                "role": "configuration mismatch identifier, NOT a "
                        "cryptographic collision-resistant binding; the KCV "
                        "is the same-root check",
            },
        },
    }


def write_artifact(path, data):
    """Canonical/public artifacts are non-secret (no raw/reference/fingerprint)."""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--golden-manifest", required=True)
    parser.add_argument("--mapping", required=True)
    parser.add_argument("--train-input", required=True)
    parser.add_argument("--holdout-input", required=True)
    parser.add_argument("--holdout-report", required=True)
    parser.add_argument("--public-out", required=True)
    parser.add_argument("--canonical-out", required=True)
    args = parser.parse_args(argv)

    golden = json.loads(Path(args.golden_manifest).read_text())
    mapping = json.loads(Path(args.mapping).read_text())
    train_input = json.loads(Path(args.train_input).read_text())
    holdout_input = json.loads(Path(args.holdout_input).read_text())
    holdout_report = json.loads(Path(args.holdout_report).read_text())
    mapping_sha = hashlib.sha256(Path(args.mapping).read_bytes()).hexdigest()
    report_sha = hashlib.sha256(Path(args.holdout_report).read_bytes()).hexdigest()

    problems = verify_inputs(
        golden, mapping, train_input, holdout_input, holdout_report,
        mapping_sha, report_sha, args.mapping, args.holdout_report)
    if problems:
        print("BLOCKER: canonicalization preflight failed:")
        for problem in problems:
            print(f"  - {problem}")
        return 2

    payload = assemble_payload(
        golden, mapping, train_input, holdout_input, holdout_report,
        mapping_sha, report_sha)
    canonical = canonical_bytes(payload)
    digest, tag = digest_and_tag(canonical)
    if tag == 0:
        print("BLOCKER: derived mapping_tag is zero")
        return 2
    public = derive_public(canonical, digest, tag)
    public_doc = dict(payload)
    public_doc.update(public)
    public_bytes = (json.dumps(public_doc, indent=2, sort_keys=True)
                    + "\n").encode("utf-8")

    canonical_path = Path(args.canonical_out)
    public_path = Path(args.public_out)
    for path, data in ((canonical_path, canonical + b"\n"),
                       (public_path, public_bytes)):
        if path.exists():
            if path.read_bytes() != data:
                print(f"BLOCKER: existing artifact differs: {path}")
                return 2
    write_artifact(canonical_path, canonical + b"\n")
    write_artifact(public_path, public_bytes)
    print(json.dumps({
        "status": "CANONICALIZED",
        "public_manifest": str(public_path),
        "canonical_bytes": str(canonical_path),
        "canonical_bytes_sha256": public["canonical_bytes_sha256"],
        "full_mapping_digest_sha3_256": digest,
        "mapping_tag": tag,
        "mapping_tag_hex": public["mapping_tag_hex"],
        "mapping_tag_width_bits": MAPPING_TAG_WIDTH_BITS,
        "mapping_tag_byte_order": MAPPING_TAG_BYTE_ORDER,
        "wire_mapping_len_status": "BLOCKED",
    }, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
