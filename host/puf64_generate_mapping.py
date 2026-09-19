#!/usr/bin/env python3
"""Single-source generator for the frozen PUF64 mapping artifacts.

Reads ``constraints/puf64_final_mapping_manifest.json`` (the canonical public
manifest) and emits deterministic, checked artifacts:

  * ``rtl/top/puf64_mapping_data.vh``  - pair table + identity constants (RTL)
  * ``host/puf64_mapping_generated.py`` - ordered pair table (host tooling)
  * ``firmware/puf64_mapping_data.h``   - identity constants (SoC firmware)

No 264-pair list is ever hand-copied.  ``--check`` fails if any generated
artifact drifts from the manifest.

Frozen bit convention (from characterization RTL / host parser / train
reference; audited, not assumed):

  * ordered pair j = (a, b) with 0 <= a < b < 64, j = 0..263.
  * mapping response bit j = 1 if count_a < count_b, 0 if count_a > count_b.
  * count_a == count_b is a tie: INVALID, the operational path must
    fail-closed and never emit a mapping bit for it.
  * FE/response vector packs LSB-first: bit j -> byte j//8, bit j%8.
  * RTL vector ``PUF64_MAP_PAIRS`` stores {a[5:0], b[5:0]} per pair, j=0 at
    the most significant end.
"""

import argparse
import hashlib
import json
from pathlib import Path
import sys

SCHEMA = "puf64-mapping-generated-v1"
RTL_PATH = "rtl/top/puf64_mapping_data.vh"
HOST_PATH = "host/puf64_mapping_generated.py"
FIRMWARE_PATH = "firmware/puf64_mapping_data.h"
EXPECTED_TAG = 0xD501
EXPECTED_LEN_BITS = 264
EXPECTED_LEN_BYTES = 33
EXPECTED_PAIR_COUNT = 264
EXPECTED_NUM_RO = 64


def load_manifest(path):
    manifest = json.loads(Path(path).read_text())
    problems = []
    if manifest.get("full_mapping_digest_sha3_256") in (None, ""):
        problems.append("missing full_mapping_digest_sha3_256")
    if manifest.get("mapping_tag") != EXPECTED_TAG:
        problems.append(f"mapping_tag {manifest.get('mapping_tag')} != "
                        f"{EXPECTED_TAG:#x}")
    if manifest.get("mapping_tag_hex") != "0xd501":
        problems.append(f"mapping_tag_hex {manifest.get('mapping_tag_hex')}")
    if manifest.get("mapping_length_bits") != EXPECTED_LEN_BITS:
        problems.append("mapping_length_bits != 264")
    if manifest.get("selected_pair_count") != EXPECTED_PAIR_COUNT:
        problems.append("selected_pair_count != 264")
    if manifest.get("mapping_len_bytes") != EXPECTED_LEN_BYTES:
        problems.append("mapping_len_bytes != 33")
    pairs = manifest.get("pairs", [])
    if len(pairs) != EXPECTED_PAIR_COUNT:
        problems.append(f"pairs length {len(pairs)} != 264")
    seen = set()
    for j, pair in enumerate(pairs):
        if len(pair) != 2:
            problems.append(f"pair {j} is not [a,b]")
            break
        a, b = pair
        if not (0 <= a < b < EXPECTED_NUM_RO):
            problems.append(f"pair {j} non-canonical ({a},{b})")
            break
        if (a, b) in seen:
            problems.append(f"duplicate pair at {j}")
            break
        seen.add((a, b))
    degree = manifest.get("ro_degree", [])
    if len(degree) != EXPECTED_NUM_RO:
        problems.append("ro_degree length != 64")
    histogram = manifest.get("degree_histogram", {})
    if histogram != {"8": 48, "9": 16}:
        problems.append(f"degree_histogram {histogram} != 48x8/16x9")
    if manifest.get("holdout_passed") is not True:
        problems.append("public manifest is not holdout PASS")
    for key in ("full_mapping_digest_sha3_256", "selection_sha256",
                "bitstream_sha256"):
        value = manifest.get(key)
        if not isinstance(value, str) or len(value) != 64:
            problems.append(f"{key} is not a 32-byte hex digest")
    if problems:
        print("BLOCKER: mapping manifest is not canonical:")
        for problem in problems:
            print(f"  - {problem}")
        return None
    return manifest


def pairs_payload_bits(pairs):
    packed = 0
    for a, b in pairs:
        packed = (packed << 12) | ((a & 0x3F) << 6) | (b & 0x3F)
    return packed


def mapping_bit(count0, count1):
    """Frozen response bit; returns None for a tie (must fail-closed)."""
    if count0 == count1:
        return None
    return 1 if count0 < count1 else 0


def pack_mapping_bits(bits):
    """LSB-first packing: bit j -> byte j//8, bit j%8; returns exactly 33 bytes."""
    packed = bytearray((len(bits) + 7) // 8)
    for j, bit in enumerate(bits):
        if bit:
            packed[j // 8] |= 1 << (j % 8)
    return bytes(packed)


def golden_vector():
    """Synthetic deterministic 264-pair counts -> bits -> 33 bytes."""
    pairs = [(a, b) for a in range(EXPECTED_NUM_RO)
             for b in range(a + 1, EXPECTED_NUM_RO)][:EXPECTED_PAIR_COUNT]
    bits = []
    for j, (a, b) in enumerate(pairs):
        count0 = 1000 + j
        count1 = count0 + (1 if j % 2 == 0 else -1)
        bits.append(mapping_bit(count0, count1))
    packed = pack_mapping_bits(bits)
    return {
        "pair_count": len(pairs),
        "bits": bits,
        "packed_hex": packed.hex(),
        "first_pair": list(pairs[0]),
        "last_pair": list(pairs[-1]),
    }


def render_rtl(manifest):
    pairs = manifest["pairs"]
    packed = ("%x" % pairs_payload_bits(pairs)).zfill(3168 // 4)
    digest = manifest["full_mapping_digest_sha3_256"]
    selection = manifest["selection_sha256"]
    return "\n".join([
        "// AUTO-GENERATED by host/puf64_generate_mapping.py --emit. Do not edit.",
        "// Mapping bit convention (frozen, audited):",
        "//   pair j = ordered_pairs[j] = (a,b), 0 <= a < b < 64.",
        "//   response bit j = 1 if count_a < count_b, 0 if count_a > count_b.",
        "//   count_a == count_b is a tie: INVALID, fail-closed in operation.",
        "//   FE vector packs LSB-first: bit j -> byte j/8, bit j%8.",
        "localparam integer PUF64_MAP_LEN_BITS   = %d;" % EXPECTED_LEN_BITS,
        "localparam integer PUF64_MAP_LEN_BYTES  = %d;" % EXPECTED_LEN_BYTES,
        "localparam integer PUF64_MAP_PAIR_COUNT = %d;" % EXPECTED_PAIR_COUNT,
        "localparam [15:0]  PUF64_MAP_TAG        = 16'h%04x;" % EXPECTED_TAG,
        "localparam [255:0] PUF64_MAP_DIGEST_SHA3_256 = 256'h%s;" % digest,
        "localparam [255:0] PUF64_MAP_SELECTION_SHA256 = 256'h%s;" % selection,
        "// {a[5:0], b[5:0]} per pair, pair 0 at the most significant end.",
        "localparam [3167:0] PUF64_MAP_PAIRS = 3168'h%s;" % packed,
        "function automatic [5:0] puf64_map_pair_a(input integer j);",
        "    puf64_map_pair_a = PUF64_MAP_PAIRS[3168-1 - 12*j -: 6];",
        "endfunction",
        "function automatic [5:0] puf64_map_pair_b(input integer j);",
        "    puf64_map_pair_b = PUF64_MAP_PAIRS[3168-1 - 12*j - 6 -: 6];",
        "endfunction",
        "",
    ])


def render_host(manifest):
    lines = [
        '"""AUTO-GENERATED by host/puf64_generate_mapping.py --emit. Do not edit."""',
        "",
        'SCHEMA = "%s"' % SCHEMA,
        'MAPPING_STATUS = "%s"' % manifest["status"],
        "MAPPING_TAG = 0x%04X" % EXPECTED_TAG,
        "MAPPING_LEN_BITS = %d" % EXPECTED_LEN_BITS,
        "MAPPING_LEN_BYTES = %d" % EXPECTED_LEN_BYTES,
        "SELECTED_PAIR_COUNT = %d" % EXPECTED_PAIR_COUNT,
        'FULL_MAPPING_DIGEST_SHA3_256 = "%s"' % manifest[
            "full_mapping_digest_sha3_256"],
        'SELECTION_SHA256 = "%s"' % manifest["selection_sha256"],
        "ORDERED_PAIRS = (",
    ]
    for a, b in manifest["pairs"]:
        lines.append("    (%d, %d)," % (a, b))
    lines += [
        ")",
        "",
        "",
        "def mapping_bit(count0, count1):",
        '    """Frozen bit; None for a tie (operational fail-closed)."""',
        "    if count0 == count1:",
        "        return None",
        "    return 1 if count0 < count1 else 0",
        "",
        "",
        "def pack_mapping_bits(bits):",
        '    """LSB-first: bit j -> byte j//8, bit j%8."""',
        "    packed = bytearray((len(bits) + 7) // 8)",
        "    for j, bit in enumerate(bits):",
        "        if bit:",
        "            packed[j // 8] |= 1 << (j % 8)",
        "    return bytes(packed)",
        "",
    ]
    return "\n".join(lines)


def render_firmware(manifest):
    digest = bytes.fromhex(manifest["full_mapping_digest_sha3_256"])
    selection = bytes.fromhex(manifest["selection_sha256"])
    lines = [
        "/* AUTO-GENERATED by host/puf64_generate_mapping.py --emit. Do not edit. */",
        "#ifndef PUF64_MAPPING_DATA_H",
        "#define PUF64_MAPPING_DATA_H",
        "",
        "#define PUF64_MAP_LEN_BITS   %du" % EXPECTED_LEN_BITS,
        "#define PUF64_MAP_LEN_BYTES  %du" % EXPECTED_LEN_BYTES,
        "#define PUF64_MAP_PAIR_COUNT %du" % EXPECTED_PAIR_COUNT,
        "#define PUF64_MAP_TAG        0x%04Xu" % EXPECTED_TAG,
        "",
        "static const unsigned char PUF64_MAP_DIGEST_SHA3_256[32] = {",
        "    " + ", ".join("0x%02x" % byte for byte in digest),
        "};",
        "static const unsigned char PUF64_MAP_SELECTION_SHA256[32] = {",
        "    " + ", ".join("0x%02x" % byte for byte in selection),
        "};",
        "",
        "#endif",
        "",
    ]
    return "\n".join(lines)


def expected_files(manifest):
    return {
        RTL_PATH: render_rtl(manifest),
        HOST_PATH: render_host(manifest),
        FIRMWARE_PATH: render_firmware(manifest),
    }


def emit(manifest_path, root):
    manifest = load_manifest(manifest_path)
    if manifest is None:
        return 2
    root = Path(root)
    for rel, text in expected_files(manifest).items():
        path = root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        print("wrote %s" % rel)
    print(json.dumps({
        "status": "EMITTED",
        "mapping_tag": manifest["mapping_tag_hex"],
        "digest": manifest["full_mapping_digest_sha3_256"],
        "pairs": len(manifest["pairs"]),
    }, indent=2))
    return 0


def check(manifest_path, root):
    manifest = load_manifest(manifest_path)
    if manifest is None:
        return 2
    root = Path(root)
    failed = False
    for rel, text in expected_files(manifest).items():
        path = root / rel
        if not path.is_file() or path.read_text() != text:
            print("STALE: %s" % rel, file=sys.stderr)
            failed = True
    if failed:
        print("run: python3 host/puf64_generate_mapping.py --emit", file=sys.stderr)
        return 1
    print("puf64_mapping_data: generated artifacts in sync")
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", default=str(
        Path(__file__).resolve().parent.parent
        / "constraints" / "puf64_final_mapping_manifest.json"))
    parser.add_argument("--emit", action="store_true")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--golden-vector", action="store_true")
    args = parser.parse_args(argv)
    root = Path(__file__).resolve().parent.parent
    if args.golden_vector:
        print(json.dumps(golden_vector(), indent=2, sort_keys=True))
        return 0
    if args.emit:
        return emit(args.manifest, root)
    if args.check:
        return check(args.manifest, root)
    parser.print_help()
    return 0


if __name__ == "__main__":
    sys.exit(main())
