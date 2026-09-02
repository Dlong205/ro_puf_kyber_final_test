#!/usr/bin/env python3
"""Extract a compact byte-oriented KAT subset from NIST CAVP SHA-3 zips."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
from zipfile import ZipFile


SHA3_URL = (
    "https://csrc.nist.gov/CSRC/media/Projects/Cryptographic-Algorithm-"
    "Validation-Program/documents/sha3/sha-3bytetestvectors.zip"
)
SHAKE_URL = (
    "https://csrc.nist.gov/CSRC/media/Projects/Cryptographic-Algorithm-"
    "Validation-Program/documents/sha3/shakebytetestvectors.zip"
)


def parse_records(text: str, result_field: str) -> list[dict[str, str]]:
    records: list[dict[str, str]] = []
    current: dict[str, str] = {}

    def finish_record() -> None:
        nonlocal current
        if "Msg" in current and result_field in current:
            records.append(current)
        current = {}

    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line:
            finish_record()
            continue
        if line.startswith("#") or line.startswith("[") or "=" not in line:
            continue
        key, value = (part.strip() for part in line.split("=", 1))
        current[key] = value
    finish_record()
    return records


def digest(mode: int, message: bytes, output_length: int) -> bytes:
    if mode == 0:
        return hashlib.sha3_512(message).digest()
    if mode == 1:
        return hashlib.shake_256(message).digest(output_length)
    if mode == 2:
        return hashlib.shake_128(message).digest(output_length)
    if mode == 3:
        return hashlib.sha3_256(message).digest()
    raise ValueError(f"unsupported mode {mode}")


def record_to_line(name: str, mode: int, record: dict[str, str], result: str) -> str:
    bit_length = int(record.get("Len", str(len(record["Msg"]) * 4)))
    if (bit_length % 8) != 0:
        raise ValueError(f"{name}: selected record is not byte-oriented")
    message = b"" if bit_length == 0 else bytes.fromhex(record["Msg"])
    expected = bytes.fromhex(record[result])
    reference = digest(mode, message, len(expected))
    if reference != expected:
        raise ValueError(f"{name}: NIST record failed independent hashlib check")
    message_hex = message.hex() if message else "-"
    return f"{name}|{mode}|{message_hex}|{len(expected)}|{expected.hex()}"


def select_length(records: list[dict[str, str]], bit_length: int) -> dict[str, str]:
    for record in records:
        if int(record.get("Len", "-1")) == bit_length:
            return record
    raise ValueError(f"CAVP record Len={bit_length} not found")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sha3-zip", type=Path, required=True)
    parser.add_argument("--shake-zip", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=Path("nist_cavp_vectors.txt"))
    args = parser.parse_args()

    specifications = (
        (args.sha3_zip, "SHA3_512ShortMsg.rsp", "MD", "sha3_512", 0, 72),
        (args.shake_zip, "SHAKE256ShortMsg.rsp", "Output", "shake256", 1, 136),
        (args.shake_zip, "SHAKE128ShortMsg.rsp", "Output", "shake128", 2, 168),
        (args.sha3_zip, "SHA3_256ShortMsg.rsp", "MD", "sha3_256", 3, 136),
    )

    lines = [
        "# NIST CAVP FIPS 202 byte-oriented subset (CAVS 19.0, 2016-01-28)",
        f"# SHA3 source: {SHA3_URL}",
        "# SHA3 zip SHA-256: cd07701af2e47f5cc889d642528b4bf11f8b6eb55797c7307a96828ed8d8fc8c",
        f"# SHAKE source: {SHAKE_URL}",
        "# SHAKE zip SHA-256: debfebc3157b3ceea002b84ca38476420389a3bf7e97dc5f53ea4689a16de4c7",
        "# name|mode|message_hex (- means empty)|output_bytes|expected_hex",
    ]

    for archive_path, member, result_field, prefix, mode, rate in specifications:
        with ZipFile(archive_path) as archive:
            records = parse_records(archive.read(member).decode("ascii"), result_field)
        available_lengths = {int(record["Len"]) for record in records if "Len" in record}
        for byte_length in (0, 1, rate - 1, rate, rate + 1):
            if (byte_length * 8) not in available_lengths:
                continue
            selected = select_length(records, byte_length * 8)
            lines.append(
                record_to_line(
                    f"nist_{prefix}_len_{byte_length}", mode, selected, result_field
                )
            )

    # Variable-output records exercise XOF lengths independently from the
    # locally generated boundary suite.  Select the largest response in each
    # official file to keep this checked-in subset compact.
    for member, prefix, mode in (
        ("SHAKE256VariableOut.rsp", "shake256_variable_max", 1),
        ("SHAKE128VariableOut.rsp", "shake128_variable_max", 2),
    ):
        with ZipFile(args.shake_zip) as archive:
            records = parse_records(archive.read(member).decode("ascii"), "Output")
        selected = max(records, key=lambda record: int(record["Outputlen"]))
        lines.append(record_to_line(f"nist_{prefix}", mode, selected, "Output"))

    args.output.write_text("\n".join(lines) + "\n", encoding="ascii")


if __name__ == "__main__":
    main()
