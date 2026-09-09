#!/usr/bin/env python3
"""Verify/package the author-verified v4 baseline; never promote a release.

Firmware, constraints and source come from pinned Git objects, not the current
worktree. Only explicitly listed build artifacts are copied: no helper data,
hardware logs or root RC1 bitstream. --check-snapshot requires neither Vivado,
the original build directory nor Git. Checksums detect corruption; they are not
a digital signature or independent security sign-off.
"""

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = ROOT / "manifests/fpga_v4_baseline.json"


class BaselineError(Exception):
    pass


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def relative_path(value):
    path = PurePosixPath(value)
    if not value or path.is_absolute() or ".." in path.parts or str(path) != value:
        raise BaselineError(f"Unsafe relative path: {value!r}")
    return path


def load_manifest(path):
    raw = Path(path).read_bytes()
    manifest = json.loads(raw)
    if manifest.get("schema_version") != 1:
        raise BaselineError("Unsupported baseline schema")
    for key in ("source_commit", "evidence_commit"):
        if not re.fullmatch(r"[0-9a-f]{40}", manifest[key]):
            raise BaselineError(f"Expected full Git commit for {key}")
    names = {"baseline.json", "snapshot.json", "source.tar"}
    for entry in manifest["artifacts"]:
        name = str(relative_path(entry["path"]))
        relative_path(entry["source_path"])
        if name in names:
            raise BaselineError(f"Duplicate/reserved artifact path: {name}")
        names.add(name)
        if entry["origin"] not in ("build", "source_git", "evidence_git"):
            raise BaselineError(f"Unknown artifact origin: {entry['origin']}")
    for entry in [*manifest["artifacts"], manifest["source_archive"]]:
        if not re.fullmatch(r"[0-9a-f]{64}", entry["sha256"]):
            raise BaselineError("Invalid SHA-256 in manifest")
        if not isinstance(entry["size"], int) or entry["size"] < 0:
            raise BaselineError("Invalid size in manifest")
    for path in manifest["source_archive"]["paths"]:
        relative_path(path)
    return manifest, raw


def checked(data, entry, label):
    if len(data) != entry["size"] or sha256(data) != entry["sha256"]:
        raise BaselineError(f"Checksum/size mismatch: {label}")
    return data


def git_bytes(root, *args):
    result = subprocess.run(
        ["git", "-C", str(root), *args], capture_output=True, check=False
    )
    if result.returncode:
        raise BaselineError(f"Git failed: {result.stderr.decode(errors='replace').strip()}")
    return result.stdout


def regular_file(root, name):
    path = Path(root) / relative_path(name)
    # Reject symlinks at every level to prevent a snapshot depending on files
    # outside itself (and to avoid copying a mutable symlink target).
    cursor = Path(root)
    for part in relative_path(name).parts:
        cursor /= part
        if cursor.is_symlink():
            raise BaselineError(f"Symlink not permitted: {cursor}")
    if not path.is_file():
        raise BaselineError(f"Missing regular file: {path}")
    return path


def verify_inputs(root, manifest):
    """Return already-verified payloads, so later copies cannot race a rebuild."""
    payloads = {}
    for entry in manifest["artifacts"]:
        if entry["origin"] == "build":
            data = regular_file(root, entry["source_path"]).read_bytes()
        else:
            key = "source_commit" if entry["origin"] == "source_git" else "evidence_commit"
            data = git_bytes(root, "show", f"{manifest[key]}:{entry['source_path']}")
        payloads[entry["path"]] = checked(data, entry, entry["source_path"])
    archive = manifest["source_archive"]
    data = git_bytes(
        root, "archive", "--format=tar", "--prefix=source/",
        manifest["source_commit"], *archive["paths"]
    )
    payloads["source.tar"] = checked(data, archive, "source.tar from pinned Git source")
    return payloads


def create_snapshot(root, destination, manifest, manifest_raw):
    destination = Path(destination)
    if destination.exists() or destination.is_symlink():
        raise BaselineError(f"Snapshot destination already exists: {destination}")
    payloads = verify_inputs(root, manifest)
    payloads["baseline.json"] = manifest_raw
    # No overwrite, merging or deleting an earlier snapshot. A partial copy
    # has no final snapshot.json and cannot pass verification.
    destination.mkdir(parents=True, exist_ok=False)
    records = []
    for name, data in sorted(payloads.items()):
        output = destination / name
        output.parent.mkdir(parents=True, exist_ok=True)
        with output.open("xb") as handle:
            handle.write(data)
        records.append({"path": name, "size": len(data), "sha256": sha256(data)})
    snapshot = {
        "schema_version": 1,
        "baseline_id": manifest["baseline_id"],
        "source_commit": manifest["source_commit"],
        "evidence_commit": manifest["evidence_commit"],
        "files": records,
    }
    with (destination / "snapshot.json").open("x", encoding="utf-8") as handle:
        handle.write(json.dumps(snapshot, indent=2, sort_keys=True) + "\n")
    check_snapshot(destination, manifest, manifest_raw)
    return len(records)


def check_snapshot(directory, manifest, manifest_raw):
    """Check against the trusted baseline descriptor, without original inputs."""
    directory = Path(directory)
    snapshot = json.loads(regular_file(directory, "snapshot.json").read_bytes())
    if snapshot.get("schema_version") != 1:
        raise BaselineError("Unsupported snapshot schema")
    for key in ("baseline_id", "source_commit", "evidence_commit"):
        if snapshot.get(key) != manifest[key]:
            raise BaselineError(f"Snapshot identity mismatch: {key}")
    expected = {entry["path"]: entry for entry in manifest["artifacts"]}
    expected["source.tar"] = manifest["source_archive"]
    expected["baseline.json"] = {"size": len(manifest_raw), "sha256": sha256(manifest_raw)}
    records = {}
    for entry in snapshot["files"]:
        name = str(relative_path(entry["path"]))
        if name in records:
            raise BaselineError(f"Duplicate snapshot file: {name}")
        records[name] = entry
    if records.keys() != expected.keys():
        raise BaselineError("Snapshot file inventory does not match baseline")
    for name, entry in expected.items():
        for field in ("sha256", "size"):
            if records[name].get(field) != entry[field]:
                raise BaselineError(f"Snapshot manifest differs from baseline: {name}")
        checked(regular_file(directory, name).read_bytes(), entry, name)
    found = {str(path.relative_to(directory)) for path in directory.rglob("*")
             if not path.is_dir() or path.is_symlink()}
    if found != set(expected) | {"snapshot.json"}:
        raise BaselineError("Snapshot contains unlisted files/symlinks")
    return len(expected)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--snapshot", type=Path, metavar="NEW_DIRECTORY")
    mode.add_argument("--check-snapshot", type=Path, metavar="DIRECTORY")
    args = parser.parse_args(argv)
    try:
        manifest, raw = load_manifest(args.manifest)
        if args.check:
            count = len(verify_inputs(args.root, manifest))
            operation = "INPUTS"
        elif args.snapshot:
            count = create_snapshot(args.root, args.snapshot, manifest, raw)
            operation = "SNAPSHOT"
        else:
            count = check_snapshot(args.check_snapshot, manifest, raw)
            operation = "SNAPSHOT_CHECK"
        print(f"FPGA_V4_BASELINE_{operation}=PASS files={count} baseline={manifest['baseline_id']}")
        print("Scope: author-verified functional reference; independent review/PUF qualification remain open.")
        return 0
    except (BaselineError, OSError, ValueError, KeyError, TypeError) as exc:
        print(f"FPGA_V4_BASELINE=FAIL: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
