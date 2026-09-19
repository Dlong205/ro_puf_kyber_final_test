#!/usr/bin/env python3
"""Semi-automatic PUF64 train boot batch runner.

Drives one cold-boot session per boot index (default train 105..120): it prompts
the operator for a real power-cycle, waits for the UART/JTAG device to come
back, verifies the golden bitstream SHA, programs build 2, then delegates the
strict acquisition to the already-tested ``puf64_campaign.py`` (INFO tuple
enforcement + per-record status/CRC + frame validation + private raw/session/
dataset).  It stops at the first failure and never retries, overwrites, reuses a
boot index, runs the selector, runs holdout, or lowers a threshold.

This module intentionally imports neither the selector nor the holdout
evaluator: those are separate review-gated steps.
"""

import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

HOST_DIR = Path(__file__).resolve().parent


class BatchError(RuntimeError):
    """A fail-closed batch stop."""


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as source:
        for block in iter(lambda: source.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def now_utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def session_path(outdir, campaign, board_id, boot_index):
    return Path(outdir) / f"{campaign}_{board_id}_{boot_index}.session.json"


def session_siblings(session_file):
    session_file = Path(session_file)
    stem = session_file.name[: -len(".session.json")]
    base = session_file.parent / stem
    return {
        "session": session_file,
        "dataset": Path(str(base) + ".dataset.json"),
        "raw": Path(str(base) + ".raw.json"),
    }


def quarantine_session(session_file):
    """Rename a failed session (+ dataset/raw) to ``.invalid`` for evidence.

    The exact session name is freed only for evidence naming; the batch still
    refuses to reuse the boot index afterwards.
    """
    renamed = []
    for path in session_siblings(session_file).values():
        if path.is_file():
            target = Path(str(path) + ".invalid")
            path.rename(target)
            renamed.append(str(target))
    return renamed


def valid_session_boots(outdir, campaign, board_id, start_boot, end_boot):
    """Return {boot: manifest} for exact-name VALID sessions in range.

    ``.invalid``/``.superseded`` files are never matched because only the exact
    ``{campaign}_{board}_{boot}.session.json`` names are inspected.
    """
    found = {}
    for boot in range(start_boot, end_boot + 1):
        path = session_path(outdir, campaign, board_id, boot)
        if not path.is_file():
            continue
        try:
            manifest = json.loads(path.read_text())
        except (OSError, json.JSONDecodeError):
            continue
        if manifest.get("status") != "VALID":
            continue
        found[boot] = manifest
    return found


def first_missing_boot(start_boot, end_boot, valid_boots):
    for boot in range(start_boot, end_boot + 1):
        if boot not in valid_boots:
            return boot
    return None


def confirm_power_cycle(boot_index, min_seconds, input_fn=..., monotonic=...,
                        out=...):
    """Prompt once and refuse a power-off shorter than ``min_seconds``.

    Returns ``(prompt_time, confirm_time)``.  Early Enter presses are rejected
    and re-prompted; no session is ever started on an under-wait cycle.
    """
    prompt = (
        f"[boot {boot_index}] Rút toàn bộ nguồn/back-power, chờ LED tắt, "
        f"sau ít nhất {min_seconds:g} giây bật lại rồi nhấn Enter"
    )
    out.write(prompt + "\n")
    out.flush()
    prompt_time = monotonic()
    while True:
        input_fn()
        confirm_time = monotonic()
        elapsed = confirm_time - prompt_time
        if elapsed >= min_seconds:
            return prompt_time, confirm_time
        remaining = min_seconds - elapsed
        out.write(
            f"  power-off mới {elapsed:.1f}s < {min_seconds:g}s; "
            f"chờ thêm {remaining:.1f}s rồi nhấn Enter\n"
        )
        out.flush()


def wait_for_device(device, timeout, *, exists=None, monotonic=..., sleep=...,
                    out=...):
    if exists is None:
        exists = lambda p: Path(p).exists()  # noqa: E731
    deadline = monotonic() + timeout
    while monotonic() < deadline:
        if exists(device):
            return True
        sleep(0.5)
    out.write(f"  ERROR: device {device} did not return within {timeout:g}s\n")
    return False


def identity_snapshot(golden_manifest, bitstream, device, board_id, campaign,
                      build_id):
    golden = json.loads(Path(golden_manifest).read_text())
    if golden.get("board_id") != board_id:
        raise BatchError(
            f"golden board {golden.get('board_id')} != --board-id {board_id}")
    if golden.get("build_id") != build_id:
        raise BatchError(
            f"golden build_id {golden.get('build_id')} != --build-id {build_id}")
    if campaign == "train":
        if not golden.get("train_eligible"):
            raise BatchError("golden manifest train_eligible is not true")
    elif campaign == "holdout":
        if not golden.get("holdout_eligible"):
            raise BatchError("golden manifest holdout_eligible is not true")
    if golden.get("protocol") != "3.1":
        raise BatchError(f"unexpected protocol {golden.get('protocol')}")
    bitstream_sha = sha256_file(bitstream)
    if bitstream_sha != golden["bitstream_sha256"]:
        raise BatchError(
            f"local bitstream {bitstream_sha} != golden {golden['bitstream_sha256']}")
    return {
        "golden_manifest": str(Path(golden_manifest).resolve()),
        "golden_sha256": sha256_file(golden_manifest),
        "bitstream_sha256": bitstream_sha,
        "build_id": golden["build_id"],
        "protocol": golden["protocol"],
        "board_id": board_id,
        "campaign": campaign,
        "device": device,
    }


def check_identity_unchanged(snapshot, golden_manifest, bitstream):
    try:
        current = identity_snapshot(
            golden_manifest, bitstream, snapshot["device"], snapshot["board_id"],
            snapshot["campaign"], snapshot["build_id"])
    except BatchError as error:
        raise BatchError(
            f"golden manifest/bitstream identity changed mid-batch: {error}"
        ) from error
    if current != snapshot:
        raise BatchError("golden manifest/bitstream identity changed mid-batch")
    return current


def program_golden(config, snapshot, out, run=subprocess.run):
    if sha256_file(config["bitstream"]) != snapshot["bitstream_sha256"]:
        raise BatchError("bitstream SHA changed before programming")
    cmd = [
        config["vivado"], "-mode", "batch", "-nolog", "-nojournal",
        "-source", str(config["program_script"]),
    ]
    out.write(f"  programming golden build {snapshot['build_id']} via Vivado...\n")
    out.flush()
    try:
        proc = run(cmd, capture_output=True, text=True, timeout=900)
    except (OSError, subprocess.SubprocessError) as error:
        raise BatchError(f"Vivado program failed to run: {error}") from error
    output = (proc.stdout or "") + (proc.stderr or "")
    if proc.returncode != 0 or "PROGRAM_PASS" not in output:
        raise BatchError("Vivado program did not report PROGRAM_PASS")
    return output


def run_campaign_boot(config, boot_index, out, run=subprocess.run):
    cmd = [
        sys.executable, "-u", str(HOST_DIR / "puf64_campaign.py"),
        "--campaign", config["campaign"],
        "--board-id", config["board_id"],
        "--boot-index", str(boot_index),
        "--port", config["device"],
        "--bitstream", config["bitstream"],
        "--golden-manifest", config["golden_manifest"],
        "--frames", str(config["frames"]),
        "--outdir", config["outdir"],
        "--operator-power-cycle",
        "--power-off-wait", str(config["power_off_min_seconds"]),
        "--warmup", str(config["warmup_seconds"]),
        "--condition-id", f"room-coldboot-{config['campaign']}-{boot_index}",
    ]
    out.write(f"  acquiring {config['frames']} frames for boot {boot_index}...\n")
    out.flush()
    proc = run(cmd, capture_output=True, text=True, timeout=1800)
    path = session_path(config["outdir"], config["campaign"], config["board_id"],
                        boot_index)
    if not path.is_file():
        return {
            "status": "FAILED",
            "boot_index": boot_index,
            "reason": "no session file written",
            "returncode": proc.returncode,
            "stdout_tail": (proc.stdout or "")[-2000:],
            "stderr_tail": (proc.stderr or "")[-2000:],
        }
    manifest = json.loads(path.read_text())
    return {
        "status": manifest.get("status"),
        "boot_index": boot_index,
        "session": str(path),
        "manifest": manifest,
        "returncode": proc.returncode,
        "stdout_tail": (proc.stdout or "")[-2000:],
        "stderr_tail": (proc.stderr or "")[-2000:],
    }


def per_boot_summary(config, boot_index, manifest):
    dataset_path = Path(manifest.get("dataset_path") or "")
    ties = minority_pairs = worst = None
    if dataset_path.is_file():
        per_pair = json.loads(dataset_path.read_text())["per_pair"]
        ties = sum(entry["tie_count"] for entry in per_pair)
        minority_pairs = sum(
            1 for entry in per_pair if entry["minority_rate_percent"] > 0)
        worst = max(entry["minority_rate_percent"] for entry in per_pair)
    return {
        "boot_index": boot_index,
        "frames_received": manifest.get("frames_received"),
        "distinct_frame_count": manifest.get("distinct_frame_count"),
        "duplicate_frame_count": manifest.get("duplicate_frame_count"),
        "count_summary": manifest.get("count_summary"),
        "tie_events": ties,
        "pairs_nonzero_minority": minority_pairs,
        "worst_minority_percent": worst,
        "warnings": manifest.get("warnings"),
    }


def cross_boot_report(config, boots, out):
    """Pairwise consensus HD and count p50 drift over the valid boot set."""
    datasets = {}
    for boot in boots:
        manifest = json.loads(
            session_path(config["outdir"], config["campaign"],
                         config["board_id"], boot).read_text())
        dataset = Path(manifest["dataset_path"])
        if dataset.is_file():
            datasets[boot] = json.loads(dataset.read_text())
    if len(datasets) < 2:
        return None
    consensus = {}
    for boot, data in datasets.items():
        value = 0
        for index, entry in enumerate(data["per_pair"]):
            if entry["consensus_winner"]:
                value |= (1 << index)
        consensus[boot] = value
    ordered = sorted(datasets)
    pair_hd = {}
    for i, a in enumerate(ordered):
        for b in ordered[i + 1:]:
            pair_hd[f"{a}-{b}"] = (consensus[a] ^ consensus[b]).bit_count()
    spread = []
    for index in range(len(datasets[ordered[0]]["per_pair"])):
        p50 = [datasets[b]["per_pair"][index]["count0"]["p50"] for b in ordered]
        spread.append(max(p50) - min(p50))
    return {
        "pairwise_consensus_hd": pair_hd,
        "max_count0_p50_span": max(spread) if spread else None,
    }


def final_report(config, out):
    ordered = list(range(config["start_boot"], config["end_boot"] + 1))
    out.write("\n=== BATCH FINAL REPORT ===\n")
    valid = []
    for boot in ordered:
        path = session_path(config["outdir"], config["campaign"],
                            config["board_id"], boot)
        if not path.is_file():
            out.write(f"boot {boot}: MISSING\n")
            continue
        manifest = json.loads(path.read_text())
        if manifest.get("status") != "VALID":
            out.write(f"boot {boot}: {manifest.get('status')} "
                      f"{manifest.get('errors')}\n")
            continue
        valid.append(boot)
        summary = per_boot_summary(config, boot, manifest)
        out.write(
            f"boot {boot}: VALID frames={summary['frames_received']} "
            f"distinct={summary['distinct_frame_count']} "
            f"dup={summary['duplicate_frame_count']} "
            f"ties={summary['tie_events']} "
            f"minority_pairs={summary['pairs_nonzero_minority']} "
            f"worst%={summary['worst_minority_percent']} "
            f"count={json.dumps(summary['count_summary'], sort_keys=True)}\n"
            + (f"    warnings={summary['warnings']}\n"
               if summary["warnings"] else "")
        )
    cross = cross_boot_report(config, valid, out)
    if cross:
        out.write(f"cross-boot: {json.dumps(cross, sort_keys=True)}\n")
    out.write(f"valid_boots={len(valid)}/{len(ordered)}\n")
    out.write("selector/holdout NOT run; awaiting review.\n")
    return valid


def _fail(out, message):
    out.write(f"\nBATCH STOP: {message}\n")
    out.flush()
    return 1


def run_batch(config, *, input_fn=None, monotonic=None, sleep=None,
              exists=None, program_fn=None, acquire_fn=None, out=None):
    input_fn = input if input_fn is None else input_fn
    monotonic = time.monotonic if monotonic is None else monotonic
    sleep = time.sleep if sleep is None else sleep
    out = sys.stdout if out is None else out
    program_fn = program_golden if program_fn is None else program_fn
    acquire_fn = run_campaign_boot if acquire_fn is None else acquire_fn

    try:
        snapshot = identity_snapshot(
            config["golden_manifest"], config["bitstream"], config["device"],
            config["board_id"], config["campaign"], config["build_id"])
    except BatchError as error:
        return _fail(out, str(error))

    start, end = config["start_boot"], config["end_boot"]
    if start > end:
        return _fail(out, f"start_boot {start} > end_boot {end}")
    if start < 1:
        return _fail(out, "start_boot must be positive")

    scan_start = config.get("resume_from", start) if config.get("resume") else start
    valid = valid_session_boots(
        config["outdir"], config["campaign"], config["board_id"],
        scan_start, end)

    if config.get("resume"):
        resume_from = config.get("resume_from", 1)
        for boot in range(resume_from, start):
            if boot not in valid:
                return _fail(
                    out, f"--resume requires a VALID session for boot {boot} "
                         f"before start_boot {start}")
        to_run = []
        for boot in range(start, end + 1):
            if boot in valid:
                out.write(f"boot {boot}: already VALID, skipping\n")
                continue
            if session_path(config["outdir"], config["campaign"],
                            config["board_id"], boot).exists():
                return _fail(out, f"boot {boot} has a non-VALID/superseded "
                                  f"session; refusing to reuse the index")
            to_run.append(boot)
    else:
        to_run = list(range(start, end + 1))
        for boot in to_run:
            if session_path(config["outdir"], config["campaign"],
                            config["board_id"], boot).exists():
                return _fail(out, f"boot {boot} already has a session; use "
                                  f"--resume to skip VALID boots")

    out.write(
        f"batch {config['campaign']} build {snapshot['build_id']} "
        f"board {snapshot['board_id']} boots {start}..{end} "
        f"frames={config['frames']} to_run={to_run}\n")
    out.write(f"golden_sha256={snapshot['golden_sha256']}\n")
    out.write(f"bitstream_sha256={snapshot['bitstream_sha256']}\n")
    out.flush()

    for position, boot in enumerate(to_run):
        try:
            check_identity_unchanged(
                snapshot, config["golden_manifest"], config["bitstream"])
            if session_path(config["outdir"], config["campaign"],
                            config["board_id"], boot).exists():
                raise BatchError(f"boot {boot} session appeared mid-batch")

            prompt_time, confirm_time = confirm_power_cycle(
                boot, config["power_off_min_seconds"], input_fn, monotonic, out)
            out.write(
                f"  power-off confirmed at {now_utc()} "
                f"(waited {confirm_time - prompt_time:.1f}s)\n")
            out.flush()

            if not wait_for_device(
                    config["device"], config["device_timeout_seconds"],
                    exists=exists, monotonic=monotonic, sleep=sleep, out=out):
                raise BatchError(
                    f"UART/JTAG device {config['device']} did not reconnect "
                    f"within {config['device_timeout_seconds']:g}s")

            if config["warmup_seconds"] > 0:
                out.write(f"  warm-up {config['warmup_seconds']:g}s...\n")
                out.flush()
                sleep(config["warmup_seconds"])

            program_fn(config, snapshot, out)
            result = acquire_fn(config, boot, out)
            if result.get("status") != "VALID":
                path = session_path(config["outdir"], config["campaign"],
                                    config["board_id"], boot)
                quarantined = quarantine_session(path) if path.exists() else []
                reason = result.get("reason") or result.get("manifest", {}).get(
                    "errors") or result.get("status")
                raise BatchError(
                    f"boot {boot} session {result.get('status')}: {reason} "
                    f"(quarantined={quarantined})")

            summary = per_boot_summary(config, boot, result["manifest"])
            out.write(
                f"boot {boot}: VALID frames={summary['frames_received']} "
                f"distinct={summary['distinct_frame_count']} "
                f"dup={summary['duplicate_frame_count']} "
                f"ties={summary['tie_events']} "
                f"minority_pairs={summary['pairs_nonzero_minority']} "
                f"worst%={summary['worst_minority_percent']} "
                f"count={json.dumps(summary['count_summary'], sort_keys=True)} "
                f"warnings={summary['warnings']}\n")
            out.flush()
        except BatchError as error:
            return _fail(out, str(error))

        if position != len(to_run) - 1:
            out.write(
                "Nhấn Enter khi bạn đã sẵn sàng power-cycle cho boot kế tiếp\n")
            out.flush()
            input_fn()

    valid_boots = final_report(config, out)
    if len(valid_boots) != len(range(start, end + 1)):
        return _fail(out, "not all requested boots are VALID")
    return 0


def make_config(args):
    return {
        "board_id": args.board_id,
        "campaign": args.campaign,
        "build_id": args.build_id,
        "start_boot": args.start_boot,
        "end_boot": args.end_boot,
        "frames": args.frames,
        "golden_manifest": str(args.golden_manifest),
        "bitstream": str(args.bitstream),
        "device": args.device,
        "outdir": str(args.outdir),
        "power_off_min_seconds": args.power_off_min,
        "warmup_seconds": args.warmup,
        "device_timeout_seconds": args.device_timeout,
        "resume": args.resume,
        "resume_from": args.resume_from,
        "vivado": args.vivado,
        "program_script": str(args.program_script),
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--board-id", required=True)
    parser.add_argument("--campaign", default="train",
                        choices=["train", "holdout"])
    parser.add_argument("--build-id", type=int, required=True)
    parser.add_argument("--start-boot", type=int, required=True)
    parser.add_argument("--end-boot", type=int, required=True)
    parser.add_argument("--frames", type=int, default=50)
    parser.add_argument("--golden-manifest", required=True)
    parser.add_argument("--bitstream", required=True)
    parser.add_argument("--device", required=True,
                        help="stable /dev/serial/by-id/... path")
    parser.add_argument("--outdir", required=True)
    parser.add_argument("--power-off-min", type=float, default=10.0)
    parser.add_argument("--warmup", type=float, default=30.0)
    parser.add_argument("--device-timeout", type=float, default=60.0)
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--resume-from", type=int, default=101,
                        help="first boot index that must already be VALID "
                             "when --resume is used (default 101)")
    parser.add_argument("--vivado", default=os.environ.get("VIVADO", "vivado"))
    parser.add_argument("--program-script", default=str(
        Path(__file__).resolve().parent.parent
        / "scripts" / "program_puf_allpairs64.tcl"))
    args = parser.parse_args(argv)
    return run_batch(make_config(args))


if __name__ == "__main__":
    sys.exit(main())
