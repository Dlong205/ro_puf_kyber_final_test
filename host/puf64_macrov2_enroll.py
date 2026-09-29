#!/usr/bin/env python3
"""Macro-V2 enrollment: train reference -> RTL BCH encode -> KCV anchor.

Two steps around the RTL sim (sim/puf64_enroll, `make puf64-enroll-sim`):
  --build-stimulus : build the 264-bit enrollment response in scheduler
                     destination order from the frozen train reference, write
                     sim stimulus hex (response + kcv_ctx).
  --collect        : read sim results (helper/key/kcv), verify the host KCV
                     model reproduces the RTL KCV exactly, emit the private
                     76-byte helper record (tag 0x81b5) + anchor manifest.

Fail-closed throughout: reference/mapping SHA binding, KCV cross-check,
record self-validation.  Helper/anchor outputs are private (git-ignored).
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))
from helper_record_spec import (  # noqa: E402
    serialize_record, validate_record, kcv, kcv_context,
    DEFAULT_PROFILE, DEFAULT_FE_PARAM, RECORD_VERSION, PROTOCOL_VERSION)

ROOT = Path(__file__).resolve().parent.parent
CAMPAIGN = ROOT / "reports/puf64_macrov2_campaign"
SIMDIR = ROOT / "sim/puf64_enroll"

MAPPING_TAG = 0x81B5
GENERATION = 0x01
SELECTION_SHA = "2e37c3c11d5c02cfd0bbc21e0837f2738b24e0de9ad020f596fc1381e449d317"
# Generation overrides (gen2+): set from CLI --mapping-tag/--generation/
# --selection-sha/--mapping-file/--reference-file/--helper-out/--anchor-out/
# --work-dir. Defaults preserve the frozen gen1 behavior exactly.
MAPPING_FILE = "train_mapping_candidate.json"
REFERENCE_FILE = "train_reference_private.json"
HELPER_OUT = "private_enrollment_helper.record"
ANCHOR_OUT = "private_device_anchor.json"
WORK_DIR = None  # None -> SIMDIR


def _workdir():
    return Path(WORK_DIR) if WORK_DIR else SIMDIR


def _mapping_path():
    return CAMPAIGN / MAPPING_FILE


def _reference_path():
    return CAMPAIGN / REFERENCE_FILE


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def load_frozen(name):
    path = CAMPAIGN / name
    return json.loads(path.read_text()), sha256_file(path)


def build_response():
    mapping, _ = load_frozen(MAPPING_FILE)
    reference, _ = load_frozen(REFERENCE_FILE)
    if mapping.get("selection_sha256") != SELECTION_SHA:
        raise ValueError("mapping is not the frozen V2 selection")
    if reference.get("selection_sha256") != SELECTION_SHA:
        raise ValueError("reference is not bound to the frozen selection")
    pairs = mapping["pairs"]
    indices = mapping["source_pair_indices"]
    if len(pairs) != 264 or len(indices) != 264:
        raise ValueError("mapping is not 264 pairs")
    ref_bits = reference["reference_bit"]
    response = 0
    for dest, (pair, index) in enumerate(zip(pairs, indices)):
        bit = ref_bits[str(index)]
        if bit not in (0, 1):
            raise ValueError(f"pair index {index} has no binary reference")
        if bit:
            response |= (1 << dest)
    return response


def ctx_int():
    return kcv_context(record_version=RECORD_VERSION,
                       protocol_version=PROTOCOL_VERSION,
                       profile_id=DEFAULT_PROFILE,
                       fe_param_id=DEFAULT_FE_PARAM,
                       mapping_tag=MAPPING_TAG, generation=GENERATION)


def cmd_build_stimulus(_args):
    response = build_response()
    work = _workdir()
    work.mkdir(parents=True, exist_ok=True)
    (work / "enroll_stimulus_response.hex").write_text(f"{response:066x}\n")
    (work / "enroll_stimulus_ctx.hex").write_text(f"{ctx_int():014x}\n")
    print(json.dumps({
        "status": "STIMULUS_WRITTEN",
        "response_sha256": hashlib.sha256(
            response.to_bytes(33, "little")).hexdigest(),
        "kcv_ctx": f"0x{ctx_int():014x}",
    }, indent=2))
    return 0


def cmd_build_reconstruct_stimulus(args):
    """Emit one frozen holdout frame plus the provisioned helper/anchor.

    This is a diagnostic/release regression input for the real RTL FE and KCV
    blocks.  It never changes enrollment artifacts.
    """
    mapping, _ = load_frozen(MAPPING_FILE)
    raw_path = CAMPAIGN / f"holdout_ZYNQ-A01_{args.boot}.raw.json"
    raw = json.loads(raw_path.read_text())
    frames = raw.get("frames_winners_hex", [])
    if not (0 <= args.frame < len(frames)):
        raise ValueError(f"frame {args.frame} is outside {raw_path.name}")
    full_response = int(frames[args.frame], 16)
    response = 0
    for dest, index in enumerate(mapping["source_pair_indices"]):
        response |= ((full_response >> index) & 1) << dest

    record = (CAMPAIGN / HELPER_OUT).read_bytes()
    status, parsed_ctx, helper, trusted_kcv = validate_record(
        record, expected_mapping_tag=MAPPING_TAG)
    if status != 0 or parsed_ctx != ctx_int():
        raise ValueError("provisioned helper record does not match V2 context")

    work = _workdir()
    work.mkdir(parents=True, exist_ok=True)
    (work / "reconstruct_stimulus_response.hex").write_text(
        f"{response:066x}\n")
    (work / "reconstruct_stimulus_helper.hex").write_text(
        f"{int.from_bytes(helper, 'little'):066x}\n")
    (work / "reconstruct_stimulus_ctx.hex").write_text(
        f"{parsed_ctx:014x}\n")
    (work / "reconstruct_stimulus_kcv.hex").write_text(
        f"{int.from_bytes(trusted_kcv, 'little'):056x}\n")

    reference = build_response()
    print(json.dumps({
        "status": "RECONSTRUCT_STIMULUS_WRITTEN",
        "boot": args.boot,
        "frame": args.frame,
        "hamming_distance": (response ^ reference).bit_count(),
        "kcv_ctx": f"0x{parsed_ctx:014x}",
    }, indent=2))
    return 0


def read_hex(name, chars):
    text = (_workdir() / name).read_text().strip()
    if len(text) != chars or any(c not in "0123456789abcdefABCDEF" for c in text):
        raise ValueError(f"{name}: expected {chars} hex chars")
    return text.lower()


def cmd_collect(_args):
    helper_hex = read_hex("enroll_result_helper.hex", 66)
    key_hex = read_hex("enroll_result_key.hex", 48)
    kcv_hex = read_hex("enroll_result_kcv.hex", 56)
    # Key bytes are little-endian (byte i = key[8i+7:8i]); the %h file form
    # is big-endian, so convert explicitly (bytes.fromhex would be wrong).
    key_bytes = int(key_hex, 16).to_bytes(24, "little")
    # Host KCV model must reproduce the RTL KCV exactly.
    # PROVEN (KAT vector + live enroll sim): the 224-bit kcv_out value, in
    # %h order, is the byte-reverse of the SHAKE-256 digest (sponge squeeze
    # shift convention in edge_root_binding).
    host_digest = kcv(key_bytes, ctx_int())
    kcv_value_hex = host_digest[::-1].hex()
    if kcv_value_hex != kcv_hex:
        raise ValueError(
            f"host KCV != RTL KCV:\nhost {kcv_value_hex}\nrtl  {kcv_hex}")
    helper_bytes = int(helper_hex, 16).to_bytes(33, "little")
    kcv_record_bytes = int(kcv_value_hex, 16).to_bytes(28, "little")
    record = serialize_record(bytes(helper_bytes),
                              bytes(kcv_record_bytes),
                              record_version=RECORD_VERSION,
                              protocol_version=PROTOCOL_VERSION,
                              profile_id=DEFAULT_PROFILE,
                              fe_param_id=DEFAULT_FE_PARAM,
                              mapping_len_bytes=33,
                              mapping_tag=MAPPING_TAG,
                              generation=GENERATION)
    status, ctx_parsed, helper_parsed, kcv_parsed = validate_record(
        record, expected_mapping_tag=MAPPING_TAG)
    if status != 0:
        raise ValueError(f"self-built record invalid: status {status}")
    if ctx_parsed != ctx_int():
        raise ValueError("record ctx != enrollment ctx")
    rec_path = CAMPAIGN / HELPER_OUT
    rec_path.write_bytes(record)
    rec_path.chmod(0o600)
    anchor = {
        "schema": "ro-puf-macrov2-anchor-v1",
        "board_id": "ZYNQ-A01",
        "trusted_kcv_hex": kcv_hex,
        "kcv_ctx": f"0x{ctx_int():014x}",
        "kcv_ctx_fields": {
            "generation": GENERATION, "mapping_tag": MAPPING_TAG,
            "mapping_tag_hex": "0x%04x" % MAPPING_TAG, "fe_param_id": DEFAULT_FE_PARAM,
            "profile_id": DEFAULT_PROFILE, "protocol_version": PROTOCOL_VERSION,
            "record_version": RECORD_VERSION,
        },
        "selection_sha256": SELECTION_SHA,
        "helper_record_sha256": sha256_file(rec_path),
        "helper_record_bytes": len(record),
        "bitstream_sha256": "cfc72674b654d1f44d5fcb0eed8ed7dc51b2b27a7f8ed9283c7ad6d1878699bd",
        "macro_dcp_sha256": "bd0cd6200ca4e122932596eb8502d29f1b7d4b1aedf974a79990b4d1f5a9fdd4",
        "fingerprint_sha256": "7d12e3a99849f6d6351e414ebe17829fa2175cdbe42c55bc19df27bbd45afbf5",
        "host_kcv_matches_rtl": True,
    }
    anchor_path = CAMPAIGN / ANCHOR_OUT
    anchor_path.write_text(json.dumps(anchor, indent=2, sort_keys=True) + "\n")
    anchor_path.chmod(0o600)
    print(json.dumps({
        "status": "ENROLL_COLLECTED",
        "helper_record": str(rec_path),
        "helper_record_sha256": anchor["helper_record_sha256"],
        "trusted_kcv": kcv_hex,
        "anchor_manifest": str(anchor_path),
    }, indent=2))
    return 0


def main(argv=None):
    global MAPPING_TAG, GENERATION, SELECTION_SHA
    global MAPPING_FILE, REFERENCE_FILE, HELPER_OUT, ANCHOR_OUT, WORK_DIR
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--build-stimulus", action="store_true")
    group.add_argument("--collect", action="store_true")
    group.add_argument("--build-reconstruct-stimulus", action="store_true")
    parser.add_argument("--boot", type=int, default=401)
    parser.add_argument("--frame", type=int, default=0)
    parser.add_argument("--mapping-tag", default="0x81b5",
                        help="on-wire mapping tag hex (default gen1 0x81b5)")
    parser.add_argument("--generation", type=int, default=1)
    parser.add_argument("--selection-sha", default=SELECTION_SHA)
    parser.add_argument("--mapping-file", default=MAPPING_FILE)
    parser.add_argument("--reference-file", default=REFERENCE_FILE)
    parser.add_argument("--helper-out", default=HELPER_OUT)
    parser.add_argument("--anchor-out", default=ANCHOR_OUT)
    parser.add_argument("--work-dir", default=None,
                        help="stimulus/result dir (default sim/puf64_enroll)")
    args = parser.parse_args(argv)
    MAPPING_TAG = int(args.mapping_tag, 16)
    GENERATION = args.generation
    SELECTION_SHA = args.selection_sha
    MAPPING_FILE = args.mapping_file
    REFERENCE_FILE = args.reference_file
    HELPER_OUT = args.helper_out
    ANCHOR_OUT = args.anchor_out
    WORK_DIR = args.work_dir
    try:
        if args.build_stimulus:
            return cmd_build_stimulus(args)
        if args.build_reconstruct_stimulus:
            return cmd_build_reconstruct_stimulus(args)
        return cmd_collect(args)
    except (ValueError, OSError, KeyError) as error:
        print(f"ENROLL_BLOCKER: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
