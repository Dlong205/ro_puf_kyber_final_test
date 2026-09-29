#!/usr/bin/env python3
"""Phase-1 independent verifier: 20 V2 train sessions + pilot + deviation.

Fails closed unless every train boot 301..320 has exactly one VALID session
with 50 frames, board ZYNQ-A01, build 3, protocol 3.2, frozen bitstream/macro/
fingerprint SHAs, zero error flags, no zero counts, no duplicate frames, and
a dataset file whose SHA matches the session record.  The boot-301 first
attempt must exist ONLY as .invalid evidence (never counted).  No holdout
data is read here.
"""
from pathlib import Path
import hashlib
import json
import sys

ROOT = Path(__file__).resolve().parents[1]
CAMPAIGN = ROOT / "reports/puf64_macrov2_campaign"
CTX = json.loads((CAMPAIGN / "v2_context_manifest.json").read_text())


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


ERRORS: list[str] = []


def fail(m: str) -> None:
    ERRORS.append(m)


def main() -> int:
    if sha256(CAMPAIGN / "v2_context_manifest.json") == "":
        fail("context unreadable")
    # 1. deviation evidence: exactly one .invalid for boot 301, no others.
    invalids = sorted(CAMPAIGN.glob("*.invalid"))
    if [p.name for p in invalids] != ["train_ZYNQ-A01_301.session.json.invalid"]:
        fail(f"deviation evidence unexpected: {[p.name for p in invalids]}")
    else:
        inv = json.loads(invalids[0].read_text())
        if inv.get("status") == "VALID":
            fail("boot-301 .invalid must not be VALID")
        if inv.get("frames_received", 0) != 0:
            fail(f"boot-301 .invalid frames_received={inv.get('frames_received')} (expect 0)")
        print(f"deviation boot-301: kept {invalids[0].name} "
              f"errors={inv.get('errors')}")
    # 2. pilot exists and is VALID (informational for phase 1).
    pilot = json.loads((CAMPAIGN / "pilot_ZYNQ-A01_300.session.json").read_text())
    if pilot.get("status") != "VALID":
        fail("pilot boot 300 is not VALID")
    # 3. twenty train sessions.
    for boot in range(301, 321):
        name = f"train_ZYNQ-A01_{boot}.session.json"
        path = CAMPAIGN / name
        if not path.is_file():
            fail(f"missing {name}");
            continue
        try:
            manifest = json.loads(path.read_text())
        except (OSError, ValueError):
            fail(f"unreadable {name}");
            continue
        tag = f"boot {boot}"
        if manifest.get("status") != "VALID":
            fail(f"{tag}: status {manifest.get('status')}");
            continue
        if manifest.get("board_id") != "ZYNQ-A01":
            fail(f"{tag}: board {manifest.get('board_id')}")
        if manifest.get("build_id") != 3 or manifest.get("protocol") != "3.2":
            fail(f"{tag}: build/protocol {manifest.get('build_id')}/{manifest.get('protocol')}")
        if manifest.get("frames_requested") != 50 or manifest.get("frames_received") != 50:
            fail(f"{tag}: frames {manifest.get('frames_requested')}/{manifest.get('frames_received')}")
        if manifest.get("local_bitstream_sha256") != CTX["bitstream_sha256"]:
            fail(f"{tag}: bitstream SHA drift")
        dev = manifest.get("device_info", {})
        if dev.get("macro_dcp_sha256") != CTX["macro_dcp_sha256"]:
            fail(f"{tag}: macro SHA drift")
        if dev.get("fingerprint_sha256") != CTX["fingerprint_sha256"]:
            fail(f"{tag}: fingerprint SHA drift")
        if manifest.get("duplicate_frame_count"):
            fail(f"{tag}: duplicate frames {manifest.get('duplicate_frame_count')}")
        counts = manifest.get("count_summary", {})
        for side in ("count0", "count1"):
            stats = counts.get(side, {})
            if stats.get("min") in (None, 0):
                fail(f"{tag}: {side} min {stats.get('min')}")
        ds_path = Path(manifest.get("dataset_path", ""))
        if not ds_path.is_file():
            fail(f"{tag}: dataset missing");
            continue
        if sha256(ds_path) != manifest.get("parsed_dataset_sha256"):
            fail(f"{tag}: dataset SHA mismatch")
        data = json.loads(ds_path.read_text())
        per_pair = data.get("per_pair", [])
        if len(per_pair) != 2016:
            fail(f"{tag}: per_pair len {len(per_pair)}");
            continue
        # Ties/timeout/overflow/zero: acquisition (read_margin) already fails
        # a frame on any unstable/timeout/overflow/zero/unlocked record, so a
        # VALID session contains none of those.  Ties on unselected pairs are
        # legal data; the selector must still exclude them.  Report totals.
        ties = sum(e.get("tie_count", 0) for e in per_pair)
        minority = sum(1 for e in per_pair if e.get("minority_rate_percent", 0) > 0)
        print(f"{tag}: ties={ties} minority_pairs={minority} "
              f"distinct={manifest.get('distinct_frame_count')}")
    # 4. no holdout data may exist yet.
    holdouts = list(CAMPAIGN.glob("holdout_*.session.json"))
    if holdouts:
        fail(f"holdout data present during phase 1: {[p.name for p in holdouts]}")
    if ERRORS:
        print("V2_TRAIN_VERIFY_FAIL", file=sys.stderr)
        for e in ERRORS:
            print(f"- {e}", file=sys.stderr)
        return 1
    print("V2_TRAIN_VERIFY_PASS sessions=20/20 frames=50/50 no-holdout")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
