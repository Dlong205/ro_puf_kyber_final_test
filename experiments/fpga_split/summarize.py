#!/usr/bin/env python3
"""Export completed, source-verified OOC reports. Does not assert board fit."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def resources(report):
    labels = {"Slice LUTs": "lut", "Slice Registers": "registers",
              "Block RAM Tile": "bram36_tiles", "DSPs": "dsp"}
    result = {}
    for line in report.splitlines():
        cells = [x.strip() for x in line.split("|")]
        if len(cells) < 6:
            continue
        label = cells[1].rstrip("*")
        if label in labels:
            result[labels[label]] = {"used": float(cells[2]),
                                     "available": float(cells[4])}
    if result.keys() != set(labels.values()):
        raise ValueError("Missing expected resource rows")
    return result


def export(run, destination):
    if destination.exists():
        raise ValueError("Output exists: choose a fresh directory")
    blocks = []
    payloads = []
    for block in ("server", "client", "edgecore", "edgefull", "kdf", "seedctl", "fe", "puf"):
        folder = run / block
        if not (folder / "COMPLETE").is_file():
            continue
        for line in (folder / "source_manifest.sha256").read_text().splitlines():
            expected, name = line.split("  ", 1)
            if digest(Path(name)) != expected:
                raise ValueError(f"Source changed since run: {name}")
        meta = dict(line.split("\t", 1) for line in
                    (folder / "metadata.tsv").read_text().splitlines())
        if meta["block"] != block or meta["flow"] != "synthesis_out_of_context_only":
            raise ValueError("Unexpected metadata")
        entry = {"block": block, "metadata": meta,
                 "resources": resources((folder / "utilization.rpt").read_text()),
                 "report_sha256": {}}
        log = (folder / "console.log").read_text(errors="replace").splitlines()
        entry["diagnostics"] = {
            "warning_lines": sum(line.startswith("WARNING:") for line in log),
            "critical_warnings": [line for line in log if line.startswith("CRITICAL WARNING:")],
            "errors": [line for line in log if line.startswith("ERROR:")]}
        if entry["diagnostics"]["errors"]:
            raise ValueError(f"Errors in completed run: {folder}")
        for name in ("COMPLETE", "metadata.tsv", "source_manifest.sha256",
                     "source_commit.txt", "source_worktree_status.txt", "inputs.txt",
                     "utilization.rpt", "hierarchy.rpt", "timing_preliminary.rpt",
                     "check_timing.rpt"):
            source = folder / name
            entry["report_sha256"][name] = digest(source)
            payloads.append((source, Path(block) / name))
        blocks.append(entry)
    if not blocks:
        raise ValueError("No completed measurements")
    destination.mkdir(parents=True, exist_ok=False)
    for source, relative in payloads:
        output = destination / relative
        output.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, output)
    summary = {"scope": "OOC synthesis only; not routed, board tested or proof of board fit",
               "run": run.name, "blocks": blocks}
    (destination / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    export(args.run, args.destination)
