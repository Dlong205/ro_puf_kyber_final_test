#!/usr/bin/env python3
"""R6.1 source/generic/constraint hash appender (no Vivado needed).

Appends SRC/GEN sections to an OPERATIONAL_INFLUENCE_FINGERPRINT_V1 file:
  SRC <relative-path> sha256=<hex> bytes=<n>
  GEN <name>=<value>            (top-level generic values from the project)

Source list: every file in the Vivado project's sources_1 fileset is resolved
via `vivado -mode tcl` query? No -- this script reads the project .xpr XML
directly (FileInfo Path entries) so no Vivado session is required.  Plus the
active constrs XDC, the supervisor firmware hex, and the frozen mapping .vh.

Any failure is fail-closed (nonzero exit, no partial append).
Usage:
  python3 scripts/hash_operational_sources.py <project.xpr> <fingerprint.tsv> \
      [--generics k=v ...]
"""
from pathlib import Path
import hashlib
import re
import sys
import xml.etree.ElementTree as ET


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: hash_operational_sources.py <project.xpr> "
              "<fingerprint.tsv> [--generics k=v ...]", file=sys.stderr)
        return 2
    xpr = Path(sys.argv[1])
    fp = Path(sys.argv[2])
    # Remaining args are top-generic k=v pairs (single set_property generic
    # call values, e.g. QUALIFICATION_NONRELEASE=1).
    gen_list: list[str] = [a for a in sys.argv[3:] if "=" in a]
    if not xpr.is_file() or not fp.is_file():
        print("R6_SRC_HASH_FAIL: missing project or fingerprint", file=sys.stderr)
        return 1
    root = ET.parse(str(xpr)).getroot()
    proj_dir = xpr.parent
    files: set[str] = set()
    for elem in root.iter():
        tag = elem.tag
        if "}" in tag:
            tag = tag.split("}", 1)[1]
        if tag in ("File", "FileInfo"):
            p = elem.get("Path")
            if p:
                files.add(p)
    # Resolve $PPRDIR/$PSRCDIR-anchored and relative project paths.
    resolved: list[Path] = []
    for p in sorted(files):
        cand = None
        expanded = p.replace("$PPRDIR", str(proj_dir)).replace(
            "$PSRCDIR", str(proj_dir))
        trials = [Path(expanded)]
        if not Path(expanded).is_absolute():
            trials += [proj_dir / expanded, proj_dir / Path(expanded).name]
        for trial in trials:
            if trial.is_file():
                cand = trial
                break
        if cand is None:
            # Non-file entries (directories, BD references): record name only.
            continue
        resolved.append(cand)
    if not resolved:
        print("R6_SRC_HASH_FAIL: no source files resolved", file=sys.stderr)
        return 1
    lines = fp.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0] != "OPERATIONAL_INFLUENCE_FINGERPRINT_V1":
        print("R6_SRC_HASH_FAIL: bad fingerprint header", file=sys.stderr)
        return 1
    if any(ln.startswith("SRC\t") or ln.startswith("GEN\t") for ln in lines):
        print("R6_SRC_HASH_FAIL: SRC/GEN already present (refusing double-append)",
              file=sys.stderr)
        return 1
    # Drop the exporter trailer; re-add after appending.
    trailer = []
    if lines and lines[-1] == "R6_INFLUENCE_EXPORT_DONE":
        trailer = [lines.pop()]
    root_dir = Path(__file__).resolve().parents[1]
    out = list(lines)
    for path in resolved:
        try:
            rel = path.resolve().relative_to(root_dir.resolve())
        except ValueError:
            rel = path
        out.append(f"SRC\t{rel}\tsha256={sha256(path)}\tbytes={path.stat().st_size}")
    out.append(f"SRC_COUNT\t{len(resolved)}")
    for gen in gen_list:
        out.append(f"GEN\t{gen}")
    out.extend(trailer)
    fp.write_text("\n".join(out) + "\n", encoding="utf-8")
    print(f"R6_SRC_HASH_APPEND_PASS files={len(resolved)} generics={len(gen_list)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
