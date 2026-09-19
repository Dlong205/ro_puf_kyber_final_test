#!/usr/bin/env python3
"""Single source of truth for the Phase-1 helper record format.

Generates the RTL and firmware constant headers so the CPU-free Edge RTL
enforcement path, the SoC firmware mirror and the host serializer cannot
drift apart.  All multi-byte fields are little-endian.

Record layout (76 bytes, byte 0 transmitted first):

    offset size field
    0      4    magic
    4      1    record_version
    5      1    protocol_version
    6      1    profile_id
    7      1    fe_param_id
    8      1    mapping_len_bytes (33 = ceil(264/8); response bytes)
    9      2    mapping_tag
    11     1    generation
    12     1    reserved (must be 0)
    13     33   helper[264]
    46     28   kcv
    74     2    crc16 (CCITT-FALSE over bytes 0..73)

Usage:
    python3 scripts/helper_record_spec.py --emit
    python3 scripts/helper_record_spec.py --check
    python3 scripts/helper_record_spec.py --kat
    python3 scripts/helper_record_spec.py --selftest
"""

from __future__ import annotations

import argparse
import hashlib
import struct
import sys
from pathlib import Path

MAGIC = 0x55464B52  # matches docs/PUF_ROOT_BINDING_DESIGN.md ("RKPU")
RECORD_VERSION = 0x02
PROTOCOL_VERSION = 0x01
DEFAULT_PROFILE = 0x01
DEFAULT_FE_PARAM = 0x01  # BCH T=8, N=264, DATA=192
DEFAULT_MAPPING_LEN_BYTES = 33
DEFAULT_MAPPING_LEN_BITS = 264
DEFAULT_MAPPING_TAG = 0xD501
DEFAULT_GENERATION = 0x01
RESERVED = 0x00

MAGIC_BYTES = struct.pack("<I", MAGIC)

HEADER_BYTES = 13
HELPER_BYTES = 33
KCV_BYTES = 28
CRC_BYTES = 2
RECORD_BYTES = HEADER_BYTES + HELPER_BYTES + KCV_BYTES + CRC_BYTES

OFF_MAGIC = 0
OFF_RECORD_VERSION = 4
OFF_PROTOCOL_VERSION = 5
OFF_PROFILE = 6
OFF_FE_PARAM = 7
OFF_MAPPING_LEN_BYTES = 8
OFF_MAPPING_TAG = 9
OFF_GENERATION = 11
OFF_RESERVED = 12
OFF_HELPER = 13
OFF_KCV = 46
OFF_CRC = 74

KCV_LABEL = b"RO-PUF-KCV-v"
KCV_DOMAIN_SEP = 0x01

# Validation status codes shared by RTL parser and firmware mirror.
REC_OK = 0
REC_ERR_MAGIC = 1
REC_ERR_RECORD_VERSION = 2
REC_ERR_PROTOCOL_VERSION = 3
REC_ERR_PROFILE = 4
REC_ERR_FE_PARAM = 5
REC_ERR_MAPPING = 6
REC_ERR_RESERVED = 7
REC_ERR_CRC = 8
REC_ERR_LENGTH = 9

ERROR_NAMES = {
    REC_OK: "OK",
    REC_ERR_MAGIC: "MAGIC",
    REC_ERR_RECORD_VERSION: "RECORD_VERSION",
    REC_ERR_PROTOCOL_VERSION: "PROTOCOL_VERSION",
    REC_ERR_PROFILE: "PROFILE",
    REC_ERR_FE_PARAM: "FE_PARAM",
    REC_ERR_MAPPING: "MAPPING",
    REC_ERR_RESERVED: "RESERVED",
    REC_ERR_CRC: "CRC",
    REC_ERR_LENGTH: "LENGTH",
}


def crc16_ccitt_false(data: bytes) -> int:
    """CRC-16/CCITT-FALSE: poly 0x1021, init 0xFFFF, no reflect, xorout 0."""
    crc = 0xFFFF
    for byte in data:
        crc ^= byte << 8
        for _ in range(8):
            if crc & 0x8000:
                crc = ((crc << 1) ^ 0x1021) & 0xFFFF
            else:
                crc = (crc << 1) & 0xFFFF
    return crc


def kcv_context(
    record_version: int = RECORD_VERSION,
    protocol_version: int = PROTOCOL_VERSION,
    profile_id: int = DEFAULT_PROFILE,
    fe_param_id: int = DEFAULT_FE_PARAM,
    mapping_tag: int = DEFAULT_MAPPING_TAG,
    generation: int = DEFAULT_GENERATION,
) -> int:
    """56-bit context field consumed by rtl/top/edge_root_binding.sv."""
    return (
        ((generation & 0xFF) << 48)
        | ((mapping_tag & 0xFFFF) << 32)
        | ((fe_param_id & 0xFF) << 24)
        | ((profile_id & 0xFF) << 16)
        | ((protocol_version & 0xFF) << 8)
        | (record_version & 0xFF)
    )


def kcv_message(root_key: bytes, ctx: int) -> bytes:
    if len(root_key) != 24:
        raise ValueError("root key must be 24 bytes")
    # ctx bytes little-endian:
    #   [0]=record_version [1]=protocol [2]=profile [3]=fe_id
    #   [4]=mapping_tag_lo [5]=mapping_tag_hi [6]=generation
    # rtl/top/edge_root_binding.sv absorbs word4 = domain,record,protocol,
    # profile and word5 = generation,fe_id,tag_lo,tag_hi (LSB-first bytes).
    c = ctx.to_bytes(7, "little")
    msg = bytearray()
    msg += KCV_LABEL
    msg += bytes([0x31, 0x00, 0x00, 0x00])
    msg += bytes([KCV_DOMAIN_SEP])
    msg += bytes([c[0], c[1], c[2], c[6], c[3], c[4], c[5]])
    msg += root_key
    assert len(msg) == 48
    return bytes(msg)


def kcv(root_key: bytes, ctx: int) -> bytes:
    return hashlib.shake_256(kcv_message(root_key, ctx)).digest(KCV_BYTES)


def kcv_words(root_key: bytes, ctx: int) -> list[int]:
    digest = kcv(root_key, ctx)
    return [int.from_bytes(digest[i * 4 : (i + 1) * 4], "little") for i in range(7)]


def serialize_record(
    helper: bytes,
    kcv_bytes: bytes,
    *,
    record_version: int = RECORD_VERSION,
    protocol_version: int = PROTOCOL_VERSION,
    profile_id: int = DEFAULT_PROFILE,
    fe_param_id: int = DEFAULT_FE_PARAM,
    mapping_len_bytes: int = DEFAULT_MAPPING_LEN_BYTES,
    mapping_tag: int = DEFAULT_MAPPING_TAG,
    generation: int = DEFAULT_GENERATION,
    corrupt_crc: bool = False,
) -> bytes:
    if len(helper) != HELPER_BYTES:
        raise ValueError("helper must be 33 bytes")
    if len(kcv_bytes) != KCV_BYTES:
        raise ValueError("kcv must be 28 bytes")
    body = bytearray()
    body += MAGIC_BYTES
    body.append(record_version)
    body.append(protocol_version)
    body.append(profile_id)
    body.append(fe_param_id)
    body.append(mapping_len_bytes)
    body += struct.pack("<H", mapping_tag)
    body.append(generation)
    body.append(RESERVED)
    body += helper
    body += kcv_bytes
    assert len(body) == OFF_CRC
    crc = crc16_ccitt_false(bytes(body)) ^ (0xFFFF if corrupt_crc else 0x0000)
    body += struct.pack("<H", crc)
    return bytes(body)


def validate_record(
    record: bytes,
    *,
    expected_profile: int = DEFAULT_PROFILE,
    expected_fe_param: int = DEFAULT_FE_PARAM,
    expected_mapping_len_bytes: int = DEFAULT_MAPPING_LEN_BYTES,
    expected_mapping_tag: int = DEFAULT_MAPPING_TAG,
) -> tuple[int, int, bytes, bytes]:
    """Return (status, ctx, helper, kcv_bytes); status 0 means valid."""
    if len(record) != RECORD_BYTES:
        return REC_ERR_LENGTH, 0, b"", b""
    if record[OFF_MAGIC : OFF_MAGIC + 4] != MAGIC_BYTES:
        return REC_ERR_MAGIC, 0, b"", b""
    if record[OFF_RECORD_VERSION] != RECORD_VERSION:
        return REC_ERR_RECORD_VERSION, 0, b"", b""
    if record[OFF_PROTOCOL_VERSION] != PROTOCOL_VERSION:
        return REC_ERR_PROTOCOL_VERSION, 0, b"", b""
    if record[OFF_PROFILE] != expected_profile:
        return REC_ERR_PROFILE, 0, b"", b""
    if record[OFF_FE_PARAM] != expected_fe_param:
        return REC_ERR_FE_PARAM, 0, b"", b""
    if record[OFF_RESERVED] != RESERVED:
        return REC_ERR_RESERVED, 0, b"", b""
    if (
        record[OFF_MAPPING_LEN_BYTES] != expected_mapping_len_bytes
        or struct.unpack_from("<H", record, OFF_MAPPING_TAG)[0]
        != expected_mapping_tag
    ):
        return REC_ERR_MAPPING, 0, b"", b""
    expected_crc = struct.unpack_from("<H", record, OFF_CRC)[0]
    actual_crc = crc16_ccitt_false(record[:OFF_CRC])
    if expected_crc != actual_crc:
        return REC_ERR_CRC, 0, b"", b""
    ctx = kcv_context(
        record_version=record[OFF_RECORD_VERSION],
        protocol_version=record[OFF_PROTOCOL_VERSION],
        profile_id=record[OFF_PROFILE],
        fe_param_id=record[OFF_FE_PARAM],
        mapping_tag=struct.unpack_from("<H", record, OFF_MAPPING_TAG)[0],
        generation=record[OFF_GENERATION],
    )
    return (
        REC_OK,
        ctx,
        record[OFF_HELPER : OFF_HELPER + HELPER_BYTES],
        record[OFF_KCV : OFF_KCV + KCV_BYTES],
    )


# --- synthetic KAT values used by RTL/firmware/host cross tests -------------
TEST_ROOT_KEY = bytes(
    [
        0xEF,
        0xBE,
        0xAD,
        0xDE,
        0xA5,
        0x5A,
        0x5A,
        0xA5,
        0x10,
        0x32,
        0x54,
        0x76,
        0x98,
        0xBA,
        0xDC,
        0xFE,
        0xEF,
        0xCD,
        0xAB,
        0x89,
        0x67,
        0x45,
        0x23,
        0x01,
    ]
)
TEST_HELPER = bytes(range(HELPER_BYTES))
TEST_CTX = kcv_context()
TEST_KCV = kcv(TEST_ROOT_KEY, TEST_CTX)
TEST_RECORD = serialize_record(TEST_HELPER, TEST_KCV)

# CRC-valid record whose helper differs: the parser must accept it (integrity
# only) while the KCV gate later rejects the wrong root.  Proves the parser
# is not silently acting as a same-root check.
_TEST_ALT_HELPER = bytes([TEST_HELPER[0] ^ 0x01]) + TEST_HELPER[1:]
TEST_RECORD_ALT = serialize_record(_TEST_ALT_HELPER, TEST_KCV)


def _leh(v: int) -> str:
    return ", ".join("8'h%02x" % ((v >> (8 * i)) & 0xFF) for i in range(4))


def _emit_vh() -> str:
    lines = [
        "// AUTO-GENERATED by scripts/helper_record_spec.py --emit. Do not edit.",
        "// No include guard: localparams are module scoped and each module that",
        "// needs them includes this file exactly once.",
        "",
        "localparam [31:0] HREC_MAGIC            = 32'h%08x;" % MAGIC,
        "localparam [7:0]  HREC_RECORD_VERSION   = 8'h%02x;" % RECORD_VERSION,
        "localparam [7:0]  HREC_PROTOCOL_VERSION = 8'h%02x;" % PROTOCOL_VERSION,
        "localparam integer HREC_BYTES          = %d;" % RECORD_BYTES,
        "localparam integer HREC_HELPER_BYTES   = %d;" % HELPER_BYTES,
        "localparam integer HREC_KCV_BYTES      = %d;" % KCV_BYTES,
        "localparam integer HREC_OFF_RECORD_VERSION   = %d;" % OFF_RECORD_VERSION,
        "localparam integer HREC_OFF_PROTOCOL_VERSION = %d;" % OFF_PROTOCOL_VERSION,
        "localparam integer HREC_OFF_PROFILE          = %d;" % OFF_PROFILE,
        "localparam integer HREC_OFF_FE_PARAM         = %d;" % OFF_FE_PARAM,
        "localparam integer HREC_OFF_MAPPING_LEN_BYTES = %d;" % OFF_MAPPING_LEN_BYTES,
        "localparam integer HREC_OFF_MAPPING_TAG      = %d;" % OFF_MAPPING_TAG,
        "localparam integer HREC_OFF_GENERATION       = %d;" % OFF_GENERATION,
        "localparam integer HREC_OFF_RESERVED         = %d;" % OFF_RESERVED,
        "localparam integer HREC_OFF_HELPER           = %d;" % OFF_HELPER,
        "localparam integer HREC_OFF_KCV              = %d;" % OFF_KCV,
        "localparam integer HREC_OFF_CRC              = %d;" % OFF_CRC,
        "localparam [3:0]  HREC_OK               = 4'd%d;" % REC_OK,
        "localparam [3:0]  HREC_ERR_MAGIC        = 4'd%d;" % REC_ERR_MAGIC,
        "localparam [3:0]  HREC_ERR_RECORD_VER   = 4'd%d;" % REC_ERR_RECORD_VERSION,
        "localparam [3:0]  HREC_ERR_PROTOCOL_VER = 4'd%d;" % REC_ERR_PROTOCOL_VERSION,
        "localparam [3:0]  HREC_ERR_PROFILE      = 4'd%d;" % REC_ERR_PROFILE,
        "localparam [3:0]  HREC_ERR_FE_PARAM     = 4'd%d;" % REC_ERR_FE_PARAM,
        "localparam [3:0]  HREC_ERR_MAPPING      = 4'd%d;" % REC_ERR_MAPPING,
        "localparam [3:0]  HREC_ERR_RESERVED     = 4'd%d;" % REC_ERR_RESERVED,
        "localparam [3:0]  HREC_ERR_CRC          = 4'd%d;" % REC_ERR_CRC,
        "localparam [3:0]  HREC_ERR_LENGTH       = 4'd%d;" % REC_ERR_LENGTH,
        "",
        "// CRC-16/CCITT-FALSE over bytes 0..HREC_OFF_CRC-1.",
        "// hrec_crc16_step is the synthesizable per-byte form: the transport",
        "// advances one byte per received/sent UART byte, so the datapath never",
        "// contains a 592-stage combinational cone (security review finding).",
        "// hrec_crc16 is a test/reference-only convenience and MUST NOT be used",
        "// on a synthesizable datapath.",
        "function automatic [15:0] hrec_crc16_step;",
        "    input [15:0] crc;",
        "    input [7:0]  din;",
        "    integer m;",
        "    reg [15:0] c;",
        "    begin",
        "        c = crc ^ {din, 8'h00};",
        "        for (m = 0; m < 8; m = m + 1) begin",
        "            if (c[15])",
        "                c = {c[14:0], 1'b0} ^ 16'h1021;",
        "            else",
        "                c = {c[14:0], 1'b0};",
        "        end",
        "        hrec_crc16_step = c;",
        "    end",
        "endfunction",
        "",
        "function automatic [15:0] hrec_crc16;",
        "    input [8*HREC_BYTES-1:0] raw;",
        "    integer k;",
        "    integer m;",
        "    reg [15:0] crc;",
        "    begin",
        "        crc = 16'hFFFF;",
        "        for (k = 0; k < HREC_OFF_CRC; k = k + 1) begin",
        "            crc = crc ^ {raw[8*k +: 8], 8'h00};",
        "            for (m = 0; m < 8; m = m + 1) begin",
        "                if (crc[15])",
        "                    crc = {crc[14:0], 1'b0} ^ 16'h1021;",
        "                else",
        "                    crc = {crc[14:0], 1'b0};",
        "            end",
        "        end",
        "        hrec_crc16 = crc;",
        "    end",
        "endfunction",
        "",
    ]
    return "\n".join(lines)


def _emit_h() -> str:
    return "\n".join(
        [
            "/* AUTO-GENERATED by scripts/helper_record_spec.py --emit. Do not edit. */",
            "#ifndef HELPER_RECORD_SPEC_H",
            "#define HELPER_RECORD_SPEC_H",
            "",
            "#define HREC_MAGIC            0x%08xu" % MAGIC,
            "#define HREC_RECORD_VERSION   0x%02xu" % RECORD_VERSION,
            "#define HREC_PROTOCOL_VERSION 0x%02xu" % PROTOCOL_VERSION,
            "#define HREC_BYTES            %du" % RECORD_BYTES,
            "#define HREC_HELPER_BYTES     %du" % HELPER_BYTES,
            "#define HREC_KCV_BYTES        %du" % KCV_BYTES,
            "",
            "#define HREC_OFF_MAGIC            %du" % OFF_MAGIC,
            "#define HREC_OFF_RECORD_VERSION   %du" % OFF_RECORD_VERSION,
            "#define HREC_OFF_PROTOCOL_VERSION %du" % OFF_PROTOCOL_VERSION,
            "#define HREC_OFF_PROFILE          %du" % OFF_PROFILE,
            "#define HREC_OFF_FE_PARAM         %du" % OFF_FE_PARAM,
            "#define HREC_OFF_MAPPING_LEN_BYTES %du" % OFF_MAPPING_LEN_BYTES,
            "#define HREC_OFF_MAPPING_TAG      %du" % OFF_MAPPING_TAG,
            "#define HREC_OFF_GENERATION       %du" % OFF_GENERATION,
            "#define HREC_OFF_RESERVED         %du" % OFF_RESERVED,
            "#define HREC_OFF_HELPER           %du" % OFF_HELPER,
            "#define HREC_OFF_KCV              %du" % OFF_KCV,
            "#define HREC_OFF_CRC              %du" % OFF_CRC,
            "",
            "#define HREC_OK                  0u",
            "#define HREC_ERR_MAGIC           %du" % REC_ERR_MAGIC,
            "#define HREC_ERR_RECORD_VERSION  %du" % REC_ERR_RECORD_VERSION,
            "#define HREC_ERR_PROTOCOL_VERSION %du" % REC_ERR_PROTOCOL_VERSION,
            "#define HREC_ERR_PROFILE         %du" % REC_ERR_PROFILE,
            "#define HREC_ERR_FE_PARAM        %du" % REC_ERR_FE_PARAM,
            "#define HREC_ERR_MAPPING         %du" % REC_ERR_MAPPING,
            "#define HREC_ERR_RESERVED        %du" % REC_ERR_RESERVED,
            "#define HREC_ERR_CRC             %du" % REC_ERR_CRC,
            "#define HREC_ERR_LENGTH          %du" % REC_ERR_LENGTH,
            "",
            "#endif",
            "",
        ]
    )


EMIT_TARGETS = {
    "rtl/top/helper_record_spec.vh": _emit_vh,
    "firmware/helper_record_spec.h": _emit_h,
}


def _emit_kat_vh() -> str:
    lines = [
        "// AUTO-GENERATED by scripts/helper_record_spec.py --emit. Do not edit.",
        "// Synthetic helper-record KAT shared by the RTL parser and firmware",
        "// mirror cross tests. Values are not board secrets.",
        "// No include guard: localparams are module scoped.",
        "",
        "localparam [607:0] HREC_KAT_RAW = {",
    ]
    words = []
    for i in range(RECORD_BYTES // 4):
        chunk = TEST_RECORD[i * 4 : i * 4 + 4]
        words.append("32'h%08x" % int.from_bytes(chunk, "little"))
    for idx in range(len(words) - 1, -1, -1):
        comma = "," if idx > 0 else ""
        lines.append("    %s%s" % (words[idx], comma))
    lines += [
        "};",
        "localparam [607:0] HREC_KAT_RAW_ALT = {",
    ]
    alt_words = []
    for i in range(RECORD_BYTES // 4):
        chunk = TEST_RECORD_ALT[i * 4 : i * 4 + 4]
        alt_words.append("32'h%08x" % int.from_bytes(chunk, "little"))
    for idx in range(len(alt_words) - 1, -1, -1):
        comma = "," if idx > 0 else ""
        lines.append("    %s%s" % (alt_words[idx], comma))
    lines += [
        "};",
        "localparam [263:0] HREC_KAT_HELPER = 264'h%s;" % TEST_HELPER[::-1].hex(),
        "localparam [223:0] HREC_KAT_KCV    = 224'h%s;" % TEST_KCV[::-1].hex(),
        "localparam [55:0]  HREC_KAT_CTX    = 56'h%014x;" % TEST_CTX,
        "localparam [7:0]   HREC_KAT_GEN    = 8'h%02x;" % DEFAULT_GENERATION,
        "localparam [7:0]   HREC_KAT_PROFILE = 8'h%02x;" % DEFAULT_PROFILE,
        "localparam [7:0]   HREC_KAT_FE     = 8'h%02x;" % DEFAULT_FE_PARAM,
        "localparam [7:0]   HREC_KAT_MAPLEN_BYTES = 8'h%02x;" % DEFAULT_MAPPING_LEN_BYTES,
        "localparam integer HREC_KAT_MAPLEN_BITS  = %d;" % DEFAULT_MAPPING_LEN_BITS,
        "localparam [15:0]  HREC_KAT_MAPTAG = 16'h%04x;" % DEFAULT_MAPPING_TAG,
        "",
    ]
    return "\n".join(lines)


EMIT_TARGETS["sim/helper_record_kat.vh"] = _emit_kat_vh


def emit(root: Path) -> None:
    for rel, builder in EMIT_TARGETS.items():
        path = root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(builder())
        print("wrote %s" % rel)


def check(root: Path) -> int:
    failed = False
    for rel, builder in EMIT_TARGETS.items():
        path = root / rel
        expected = builder()
        if not path.exists() or path.read_text() != expected:
            print("STALE: %s" % rel, file=sys.stderr)
            failed = True
    if failed:
        print("run: python3 scripts/helper_record_spec.py --emit", file=sys.stderr)
        return 1
    print("helper_record_spec: headers in sync")
    return 0


def selftest() -> int:
    status, ctx, helper, kcv_bytes = validate_record(TEST_RECORD)
    assert status == REC_OK, ERROR_NAMES[status]
    assert ctx == TEST_CTX
    assert helper == TEST_HELPER
    assert kcv_bytes == TEST_KCV
    # Every single-byte mutation must be rejected before KCV is even computed.
    for i in range(len(TEST_RECORD)):
        mutated = bytearray(TEST_RECORD)
        mutated[i] ^= 0x01
        status, _, _, _ = validate_record(bytes(mutated))
        assert status != REC_OK, "mutation at %d accepted" % i
    # A valid record from a different mapping must be rejected.
    other = serialize_record(
        TEST_HELPER, TEST_KCV, mapping_len_bytes=32, mapping_tag=0xBEEF
    )
    status, _, _, _ = validate_record(other)
    assert status == REC_ERR_MAPPING, ERROR_NAMES[status]
    # Record v1 (the pre-mapping layout) must be rejected in the v2 spec.
    legacy = bytearray(TEST_RECORD)
    legacy[OFF_RECORD_VERSION] = 0x01
    crc = crc16_ccitt_false(bytes(legacy[:OFF_CRC]))
    legacy[OFF_CRC] = crc & 0xFF
    legacy[OFF_CRC + 1] = (crc >> 8) & 0xFF
    status, _, _, _ = validate_record(bytes(legacy))
    assert status == REC_ERR_RECORD_VERSION, ERROR_NAMES[status]
    # Only mapping_len_bytes=33 with tag=0xD501 is accepted for this profile.
    for bad_len in (0, 1, 32, 34, 255):
        bad = serialize_record(TEST_HELPER, TEST_KCV,
                               mapping_len_bytes=bad_len)
        status, _, _, _ = validate_record(bad)
        assert status == REC_ERR_MAPPING, (bad_len, ERROR_NAMES[status])
    for bad_tag in (0x0000, 0x00D5, 0x01D5, 0xD500, 0xFFFF):
        bad = serialize_record(TEST_HELPER, TEST_KCV, mapping_tag=bad_tag)
        status, _, _, _ = validate_record(bad)
        assert status == REC_ERR_MAPPING, (hex(bad_tag), ERROR_NAMES[status])
    assert DEFAULT_MAPPING_LEN_BITS == 264
    assert TEST_KCV == kcv(TEST_ROOT_KEY, TEST_CTX)
    # A CRC-valid record with a different helper must still parse: the parser
    # is integrity-only and the KCV gate owns the same-root decision.
    status, _, helper_alt, _ = validate_record(TEST_RECORD_ALT)
    assert status == REC_OK, ERROR_NAMES[status]
    assert helper_alt != TEST_HELPER
    print("helper_record_spec: selftest passed (%d bytes)" % len(TEST_RECORD))
    return 0


def kat() -> int:
    print("magic        = %s" % MAGIC_BYTES.hex())
    print("record       = %s" % TEST_RECORD.hex())
    print("ctx          = %014x" % TEST_CTX)
    print("kcv          = %s" % TEST_KCV.hex())
    words = kcv_words(TEST_ROOT_KEY, TEST_CTX)
    print("kcv_words_hex= " + " ".join("%08x" % w for w in reversed(words)))
    for i in range(0, RECORD_BYTES, 4):
        chunk = TEST_RECORD[i : i + 4]
        value = int.from_bytes(chunk, "little")
        print("raw[%06d +: 32] = 32'h%08x;" % (8 * i, value))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--emit", action="store_true")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--kat", action="store_true")
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    if args.emit:
        emit(root)
    if args.check:
        return check(root)
    if args.selftest:
        return selftest()
    if args.kat:
        return kat()
    parser.print_help()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
