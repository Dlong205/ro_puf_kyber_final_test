#!/usr/bin/env python3
"""R2 macro-V2 freeze gate: session log + DRC + methodology + timing + manifest.

Reads build/puf64_macro_v2/ evidence (no Vivado needed) and fails closed unless:
- session log: 0 CRITICAL WARNING (TCL echo lines starting with '#' excluded)
- DRC report: exactly {LUTLP-2:64, PDRC-153:1152, PLHOLDVIO-2:1152, ZPS7-1:1},
  all Warning; LUTLP-2 entries single-RO with set 0..63 under u_bench/;
  PDRC/PLHOLD entries on the 1152 INV-output nets under u_bench/
- methodology: exactly {TIMING-17 Critical, TIMING-18 Warning, TIMING-23:64
  Warning, ULMTCS-1:1 Warning}; TIMING-17 details (1000, display cap) all
  u_bench presc/stage C pins; TIMING-18 details (1000, cap) all top ports;
  TIMING-23 details RO set 0..63
- timing: no VIOLATED, macro_clk WNS >= 0
- fingerprint: R2 header, CELL 2560 / TAP 64 / RIPPLE 1088
On PASS writes r2_freeze_manifest.tsv (DCP/fingerprint SHAs + gate record).

Usage: python3 scripts/check_macro_v2_freeze.py [build/puf64_macro_v2]
"""
from pathlib import Path
import hashlib
import re
import sys

ERRORS: list[str] = []


def fail(msg: str) -> None:
    ERRORS.append(msg)


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def section_entries(text: str, rule: str) -> list[str]:
    """Split 'RULE#N <sev>' detail blocks; return bodies."""
    bodies, cur = [], None
    for ln in text.splitlines():
        m = re.match(rf"^{re.escape(rule)}#\d+ (Warning|Critical Warning|Error)\s*$", ln)
        if m:
            if cur is not None:
                bodies.append(cur)
            cur = ""
        elif cur is not None:
            if re.match(r"^[A-Z]+[A-Z0-9-]*#\d+ ", ln):
                bodies.append(cur)
                cur = None
            else:
                cur += ln + "\n"
    if cur is not None:
        bodies.append(cur)
    return bodies


def main() -> int:
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else \
        Path(__file__).resolve().parents[1] / "build/puf64_macro_v2"
    slog = out / "route_session.log"
    drc = out / "ooc_drc.rpt"
    mth = out / "ooc_methodology.rpt"
    tmr = out / "ooc_timing.rpt"
    fp = out / "macro_v2_fingerprint.tsv"
    dcp = out / "macro_v2_routed_ooc.dcp"
    for p in (slog, drc, mth, tmr, fp, dcp):
        if not p.is_file():
            fail(f"missing evidence: {p}")

    if not ERRORS:
        crits = [ln for ln in slog.read_text(encoding="utf-8", errors="replace").splitlines()
                 if "CRITICAL WARNING" in ln and not ln.startswith("#")]
        if crits:
            fail(f"session log has {len(crits)} CRITICAL, first: {crits[0][:160]}")

    if not ERRORS:
        dtxt = drc.read_text(encoding="utf-8", errors="replace")
        counts = {r: len(section_entries(dtxt, r))
                  for r in ("LUTLP-2", "PDRC-153", "PLHOLDVIO-2", "ZPS7-1")}
        if counts != {"LUTLP-2": 64, "PDRC-153": 1152, "PLHOLDVIO-2": 1152, "ZPS7-1": 1}:
            fail(f"DRC rule partition unexpected: {counts}")
        ro_seen: set[int] = set()
        for body in section_entries(dtxt, "LUTLP-2"):
            idxs = {int(m.group(1)) for m in re.finditer(r"ro\[(\d+)\]", body)}
            if len(idxs) != 1:
                fail("LUTLP-2 entry spans != 1 RO");
                break
            ro_seen |= idxs
            for ln in body.splitlines():
                if "ro[" in ln and "u_bench/" not in ln:
                    fail(f"LUTLP-2 line outside u_bench: {ln[:120]}")
                    break
        if ro_seen != set(range(64)):
            fail(f"LUTLP-2 RO set != 0..63 (got {len(ro_seen)})")
        nets_p, nets_h = set(), set()
        for body in section_entries(dtxt, "PDRC-153"):
            m = re.search(r"Net (\S+) is a gated clock", body)
            if not m:
                fail("PDRC-153 entry without gated net");
                break
            nets_p.add(m.group(1))
        for body in section_entries(dtxt, "PLHOLDVIO-2"):
            m = re.search(r"A LUT (\S+) is driving clock pin", body)
            if not m:
                fail("PLHOLDVIO-2 entry without driving LUT");
                break
            nets_h.add(m.group(1))
        # 1088 ripple nets (INV outputs) + 64 TAP nets (RO LUT6 outputs).
        exp_net = re.compile(r"^u_bench/ro\[\d+\]\.(counter/(n_presc|n_qq\[\d+\])|ro_cell/u_backend/t3)$")
        exp_lut = re.compile(r"^u_bench/ro\[\d+\]\.(counter/(inv_presc|stage\[\d+\]\.inv)|ro_cell/u_backend/LUT6_INV2)$")
        if len(nets_p) != 1152 or any(not exp_net.match(n) for n in nets_p):
            fail(f"PDRC-153 net set unexpected (n={len(nets_p)})")
        if len(nets_h) != 1152 or any(not exp_lut.match(n) for n in nets_h):
            fail(f"PLHOLDVIO-2 LUT set unexpected (n={len(nets_h)})")
        if re.search(r"Severity\s*:\s*(Error|Critical)", dtxt, re.IGNORECASE):
            fail("DRC report contains Error/Critical severity")

    if not ERRORS:
        mtxt = mth.read_text(encoding="utf-8", errors="replace")
        mcounts = {r: len(section_entries(mtxt, r))
                   for r in ("TIMING-17", "TIMING-18", "TIMING-23", "ULMTCS-1")}
        if mcounts != {"TIMING-17": 1000, "TIMING-18": 1000, "TIMING-23": 64, "ULMTCS-1": 1}:
            fail(f"methodology partition unexpected: {mcounts}")
        for body in section_entries(mtxt, "TIMING-17"):
            if not re.search(r"u_bench/ro\[\d+\]\.counter/(presc_fdce|stage\[\d+\]\.ff)/C", body):
                fail(f"TIMING-17 not a ripple C pin: {body[:120]}");
                break
        for body in section_entries(mtxt, "TIMING-18"):
            m = re.search(r"delay is missing on (\S+)", body)
            if not m or "/" in m.group(1):
                fail(f"TIMING-18 not a top port: {body[:120]}");
                break
        ro23 = set()
        for body in section_entries(mtxt, "TIMING-23"):
            for m in re.finditer(r"ro\[(\d+)\]", body):
                ro23.add(int(m.group(1)))
            if "u_bench/" not in body:
                fail("TIMING-23 outside u_bench");
                break
        if ro23 != set(range(64)):
            fail(f"TIMING-23 RO set != 0..63 (got {len(ro23)})")

    if not ERRORS:
        ttxt = tmr.read_text(encoding="utf-8", errors="replace")
        if re.search(r"VIOLATED|Timing constraints are not met", ttxt):
            fail("timing violations present")
        m = re.search(r"^macro_clk\s+([-\d.]+)\s+([-\d.]+)", ttxt, re.MULTILINE)
        if not m or float(m.group(1)) < 0:
            fail(f"macro_clk WNS unexpected: {m.group(0) if m else 'missing'}")

    if not ERRORS:
        flines = [ln for ln in fp.read_text(encoding="utf-8").splitlines() if ln.strip()]
        if not flines or flines[0] != "R2_MACRO_FINGERPRINT_V1":
            fail("fingerprint bad header")
        else:
            kinds: dict[str, int] = {}
            for ln in flines[2:]:
                kinds[ln.split("\t")[0]] = kinds.get(ln.split("\t")[0], 0) + 1
            if kinds != {"SUMMARY": 1, "CELL": 2560, "TAP": 64, "RIPPLE": 1088}:
                fail(f"fingerprint partition unexpected: {kinds}")

    if ERRORS:
        print("R2_MACRO_FREEZE_GATE_FAIL", file=sys.stderr)
        for e in ERRORS:
            print(f"- {e}", file=sys.stderr)
        return 1
    dcp_sha, fp_sha = sha256(dcp), sha256(fp)
    man = out / "r2_freeze_manifest.tsv"
    man.write_text(
        "R2_MACRO_FREEZE_MANIFEST_V1\n"
        f"routed_dcp\t{dcp.name}\trouted_dcp_sha256\t{dcp_sha}\n"
        f"fingerprint\t{fp.name}\tfingerprint_sha256\t{fp_sha}\n"
        "part\txc7z020clg400-2\nvivado\t2020.1\n"
        "critical_session\t0\n"
        "drc\tLUTLP-2:64+PDRC-153:1152+PLHOLDVIO-2:1152+ZPS7-1:1\n"
        "methodology\tTIMING-23:64\ntiming\tmacro_clk PASS\n",
        encoding="utf-8")
    print("R2_MACRO_FREEZE_GATE_PASS")
    print(f"routed_dcp_sha256={dcp_sha}")
    print(f"fingerprint_sha256={fp_sha}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
