#!/usr/bin/env python3
"""R7 holdout authorization: frozen BEFORE any holdout collection.

Derives the private 264-bit selected reference solely from the frozen R7
train data (pilot 703 + train 704-723). Authorizes exactly 10 cold boots
801-810 x 50 frames on the char image. Rerun must reproduce the same SHA.
Private, git-ignored.
"""
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CAMPAIGN = ROOT / "reports/puf64_finalchar_campaign"
FREEZE = CAMPAIGN / "r7_train_input_703_723.frozen.json"
MAPPING = CAMPAIGN / "r7_mapping_candidate.json"
REFERENCE = CAMPAIGN / "r7_reference_private.json"
OUTPUT = CAMPAIGN / "r7_holdout_authorization.json"

HOLDOUT_BOOTS = list(range(801, 811))
FRAMES_PER_BOOT = 50
CHAR_BIT_SHA = "3e7ef33229395d76eee324510bae164775c198471609b8a5f5036e3c75606bca"


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def build():
    freeze = json.loads(FREEZE.read_text())
    mapping = json.loads(MAPPING.read_text())
    reference = json.loads(REFERENCE.read_text())
    if mapping["selection_sha256"] != reference["selection_sha256"]:
        raise RuntimeError("mapping/reference selection mismatch")
    if mapping["train_freeze_sha256"] != freeze["aggregate_sha256"]:
        raise RuntimeError("mapping/freeze mismatch")
    if mapping["mapping_tag"] != "0x81B7":
        raise RuntimeError("unexpected mapping tag")
    if len(reference["reference_bits"]) != 264:
        raise RuntimeError("reference is not 264 bits")
    return {
        "schema": "r7-holdout-authorization-v1",
        "board_id": "ZYNQ-A01",
        "mapping_tag": "0x81B7",
        "selection_sha256": mapping["selection_sha256"],
        "train_freeze_sha256": freeze["aggregate_sha256"],
        "bitstream_sha256": CHAR_BIT_SHA,
        "holdout_boot_indices": HOLDOUT_BOOTS,
        "frames_per_boot": FRAMES_PER_BOOT,
        "reference_bits": reference["reference_bits"],
        "mapping_ordered_pairs": mapping["pairs"],
        "acceptance": {
            "valid_cold_boots": 10,
            "valid_frames": 500,
            "fe_kcv_failures": 0,
            "public_key_mismatches": 0,
            "selected_ties": 0,
            "invalid_timeout_overflow_countzero": 0,
            "max_selected_bit_errors_per_frame": 8,
            "max_selected_bit_errors_per_boot_majority": 8,
            "p95_selected_bit_errors": 4,
            "max_bch_corrections": 8,
        },
        "note": "Authorization for independent holdout collection on the "
                "char image, not a release qualification.",
    }


def main() -> int:
    auth = build()
    payload = json.dumps(auth, indent=1, sort_keys=True) + "\n"
    digest = hashlib.sha256(payload.encode()).hexdigest()
    if OUTPUT.exists():
        current = OUTPUT.read_bytes()
        if hashlib.sha256(current).hexdigest() != digest:
            print("R7_HOLDOUT_AUTHORIZATION_MISMATCH", file=sys.stderr)
            return 1
        print(f"R7_HOLDOUT_AUTHORIZATION_RECHECK_PASS {digest}")
        return 0
    OUTPUT.write_text(payload)
    # Second computation reproduces it (determinism gate).
    auth2 = build()
    payload2 = json.dumps(auth2, indent=1, sort_keys=True) + "\n"
    if hashlib.sha256(payload2.encode()).hexdigest() != digest:
        print("R7_HOLDOUT_AUTHORIZATION_NONDETERMINISTIC", file=sys.stderr)
        OUTPUT.unlink()
        return 1
    print(f"R7_HOLDOUT_AUTHORIZED {digest} boots=801-810 frames=500")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
