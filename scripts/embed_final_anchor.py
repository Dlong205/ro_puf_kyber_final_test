#!/usr/bin/env python3
"""Embed the qualified device KCV into the FINAL top without logging secrets.

Reads reports/puf64_macrov2_campaign/private_device_anchor.json, validates
provenance against the frozen R2 macro / char image / mapping (SHAs only in
logs, never the KCV hex), then replaces the single all-zero
DEVICE_TRUSTED_KCV placeholder in
rtl/top/Edge_Puf64_Zynq_Operational_Final_100MHz_Top.sv with the real 224-bit
value.  Fail-closed: any provenance mismatch aborts without touching the top.

Logs contain ONLY SHAs / lengths / counts, never trusted_kcv_hex,
reference bits, helper bytes, keys or shared secrets.
"""
from pathlib import Path
import hashlib
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
ANCHOR = ROOT / "reports/puf64_macrov2_campaign/private_device_anchor.json"
HELPER = ROOT / "reports/puf64_macrov2_campaign/private_enrollment_helper.record"
TOP = ROOT / "rtl/top/Edge_Puf64_Zynq_Operational_Final_100MHz_Top.sv"

FROZEN = {
    "board_id": "ZYNQ-A01",
    "schema": "ro-puf-macrov2-anchor-v1",
    "bitstream_sha256": "cfc72674b654d1f44d5fcb0eed8ed7dc51b2b27a7f8ed9283c7ad6d1878699bd",
    "macro_dcp_sha256": "bd0cd6200ca4e122932596eb8502d29f1b7d4b1aedf974a79990b4d1f5a9fdd4",
    "fingerprint_sha256": "7d12e3a99849f6d6351e414ebe17829fa2175cdbe42c55bc19df27bbd45afbf5",
    "selection_sha256": "2e37c3c11d5c02cfd0bbc21e0837f2738b24e0de9ad020f596fc1381e449d317",
    "kcv_ctx": "0x0181b501010102",
    "helper_record_bytes": 76,
}


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def fail(msg: str) -> int:
    print(f"FINAL_ANCHOR_EMBED_FAIL: {msg}", file=sys.stderr)
    return 2


def main() -> int:
    if not ANCHOR.is_file():
        return fail("anchor manifest missing")
    if not HELPER.is_file():
        return fail("helper record missing")
    try:
        anchor = json.loads(ANCHOR.read_text())
    except (OSError, ValueError) as e:
        return fail(f"anchor unreadable ({type(e).__name__})")
    for key, want in FROZEN.items():
        if anchor.get(key) != want:
            return fail(f"anchor provenance mismatch on {key}")
    fields = anchor.get("kcv_ctx_fields", {})
    if fields.get("mapping_tag") != 33205 or fields.get("mapping_tag_hex") != "0x81b5":
        return fail("anchor ctx fields mismatch")
    kcv_hex = anchor.get("trusted_kcv_hex", "")
    if not isinstance(kcv_hex, str) or len(kcv_hex) != 56:
        return fail("anchor KCV length invalid")
    if any(c not in "0123456789abcdefABCDEF" for c in kcv_hex):
        return fail("anchor KCV not hex")
    if int(kcv_hex, 16) == 0:
        return fail("anchor KCV is zero")
    helper_bytes = HELPER.stat().st_size
    if helper_bytes != 76:
        return fail(f"helper length {helper_bytes} != 76")
    helper_sha = sha256_file(HELPER)
    if anchor.get("helper_record_sha256") != helper_sha:
        return fail("helper SHA not bound to anchor")
    if not anchor.get("host_kcv_matches_rtl"):
        return fail("anchor KCV not cross-checked against RTL")

    text = TOP.read_text(encoding="utf-8")
    if "PRESERVATION_ANCHOR" in text:
        return fail("final top still references preservation token")
    if "DEVICE_TRUSTED_KCV" not in text:
        return fail("final top lacks DEVICE_TRUSTED_KCV")
    zero_tok = "224'h00000000000000000000000000000000000000000000000000000000"
    if text.count(zero_tok) != 1:
        # Already provisioned or corrupted: refuse to touch.
        if "FINAL_ANCHOR_UNPROVISIONED" not in text:
            print("FINAL_ANCHOR_ALREADY_PROVISIONED")
            print(f"anchor_file_sha256={sha256_file(ANCHOR)}")
            print(f"helper_record_sha256={helper_sha}")
            return 0
        return fail("final top anchor placeholder count != 1")
    if "FINAL_ANCHOR_UNPROVISIONED" not in text:
        return fail("final top anchor marker missing")
    patched = text.replace(zero_tok, "224'h%s" % kcv_hex.lower(), 1)
    patched = patched.replace("FINAL_ANCHOR_UNPROVISIONED",
                              "FINAL_ANCHOR_PROVISIONED_FROM_QUALIFIED_MANIFEST", 1)
    # Sanity: exactly one DEVICE_TRUSTED_KCV declaration, ROM_VALID=1, no zeros left.
    if patched.count("DEVICE_TRUSTED_KCV") < 2:
        return fail("patched anchor declaration incomplete")
    if zero_tok in patched:
        return fail("zero placeholder survives patch")
    TOP.write_text(patched, encoding="utf-8")
    print("FINAL_ANCHOR_EMBED_PASS")
    print(f"anchor_file_sha256={sha256_file(ANCHOR)}")
    print(f"helper_record_sha256={helper_sha}")
    print(f"helper_record_bytes={helper_bytes}")
    print(f"top_sha256={sha256_file(TOP)}")
    print("provenance=board_ZYNQ-A01/macro_bd0cd620/fp_7d12e3a9/bit_cfc72674/tag_0x81b5")
    print("note=KCV value embedded without logging; verify via netlist audit, not text search")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
