#!/usr/bin/env python3
"""Fail closed if an I3.7 operational boundary exposes secret/diagnostic ports."""

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
FILES = [
    ROOT / "rtl/top/edge_puf64_operational_chain.sv",
    ROOT / "rtl/top/edge_puf64_operational_uart.sv",
]
FORBIDDEN_OUTPUTS = re.compile(
    r"\boutput\b[^;,)\n]*(raw_pair|raw_count|mapped_response|fe_key|fe_kcv|kcv_out|"
    r"shared_secret|helper_out)", re.IGNORECASE
)


def module_header(text: str) -> str:
    start = text.index("module ")
    end = text.index(");", start)
    return text[start:end]


def main() -> int:
    errors: list[str] = []
    for path in FILES:
        text = path.read_text(encoding="utf-8")
        match = FORBIDDEN_OUTPUTS.search(module_header(text))
        if match:
            errors.append(f"{path.name}: forbidden output: {match.group(0).strip()}")

    chain = FILES[0].read_text(encoding="utf-8")
    uart = FILES[1].read_text(encoding="utf-8")
    required_chain = [
        ".ALLOW_ENROLL(1'b0)",
        ".enroll(1'b0)",
        ".downstream_key_internal(fe_key_internal)",
        ".shared_secret(shared_secret_internal)",
    ]
    required_uart = [
        ".LEGACY_HELPER_ENABLE(1'b0)",
        ".ALLOW_ENROLL(1'b0)",
        ".EXTERNAL_RESULT_TAG(1'b1)",
        ".shared_secret(256'd0)",
    ]
    for token in required_chain:
        if token not in chain:
            errors.append(f"chain: missing structural invariant {token}")
    for token in required_uart:
        if token not in uart:
            errors.append(f"uart: missing structural invariant {token}")

    if errors:
        print("I3.7 operational boundary audit FAILED", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1
    print("I3_7_OPERATIONAL_BOUNDARY_AUDIT_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
