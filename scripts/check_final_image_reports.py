#!/usr/bin/env python3
"""FINAL single-clock image report gate (strict, no gate lowering).

Requires, for reports/puf64_operational_final:
- DRC rule set EXACTLY {LUTLP-2:64, PDRC-153:1152, PLHOLDVIO-2:1152,
  ZPS7-1:1, DPOP-2:2 (M0/M1 ML-KEM mults), RTSTAT-10:1 (14 documented
  unconnected macro nets)} with the documented macro-hier forms.
- Methodology has NO TIMING-4/6/27 (single-clock proof: stale macro_clk
  removed) and the documented rule set. SYNTH-6 is content-allowlisted as an
  EXACT instance set: 8 ML-KEM RAM advisories (hash ififo/ofifo/ofifo1 +
  NTT RAM0-4, all "no output register merged into the block", none under
  the PUF macro hier). Rationale 2026-09-22: post tie-policy/corr-latch
  rebuilds deterministically emit this set (whole-design synthesis
  inference drift; the touched blocks are scheduler/core/transport only
  and contain no RAMs). Any instance outside the set, a missing instance,
  or a count change fails closed. Verified by --selftest (foreign/missing
  instances rejected) and by identical sets in clean builds A/B.
  TIMING-30:1, ULMTCS-1:1, XDCC-4:2, XDCC-8:2} with documented forms.
  Any occurrence of macro_clk in methodology fails closed.
- Timing has no VIOLATED, clk_sys_100mhz WNS >= 0, and NO macro_clk clocks.
- synth_1/runme.log + impl_1/runme.log contain 0 CRITICAL WARNING.
- Bitstream present and non-empty.

Usage:
  python3 scripts/check_final_image_reports.py <runs> <reports> <clock> <hier> [--profile final|picorv32]
"""
from pathlib import Path
import argparse
import hashlib
import re
import sys

ERRORS: list[str] = []


def fail(m: str) -> None:
    ERRORS.append(m)


def section_entries(text: str, rule: str) -> list[str]:
    bodies, cur = [], None
    for ln in text.splitlines():
        if re.match(rf"^{re.escape(rule)}#\d+ (Warning|Critical Warning|Error)\s*$", ln):
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


PICORV32_SYNTH6_ALLOW = frozenset({
    "u_operational_uart/u_chain/u_mlkem/u_server/hash/ififo_inst/inst/mem_reg",
    "u_operational_uart/u_chain/u_mlkem/u_server/hash/ofifo1_inst/inst/mem_reg",
    "u_operational_uart/u_chain/u_mlkem/u_server/hash/ofifo_inst/inst/mem_reg_1",
    "u_operational_uart/u_chain/u_mlkem/u_server/ntt/RAM0/inst/mem_reg",
    "u_operational_uart/u_chain/u_mlkem/u_server/ntt/RAM1/inst/mem_reg",
    "u_operational_uart/u_chain/u_mlkem/u_server/ntt/RAM2/inst/mem_reg",
    "u_operational_uart/u_chain/u_mlkem/u_server/ntt/RAM3/inst/mem_reg",
    "u_operational_uart/u_chain/u_mlkem/u_server/ntt/RAM4/inst/mem_reg_1",
})

SYNTH6_MSG = ("Timing of a RAM block might be sub-optimal",
              "no output register was merged into the block")


def validate_synth6_set(mtxt: str, hier: str, summary_count) -> str | None:
    """Exact-set SYNTH-6 validation shared by the gate and --selftest."""
    insts = re.findall(
        r"SYNTH-6#\d+ Warning\s+Timing of a RAM block might be sub-optimal\s+"
        r"The timing for the instance (\S+),", mtxt)
    if len(insts) != summary_count or set(insts) != PICORV32_SYNTH6_ALLOW:
        return f"instance set unexpected: {insts}"
    if any(hier in inst for inst in insts):
        return "instance under PUF macro hier"
    if not all(m in mtxt for m in SYNTH6_MSG):
        return "message text drifted"
    return None


def selftest() -> int:
    def entry(n: int, inst: str) -> str:
        return (f"SYNTH-6#{n} Warning\nTiming of a RAM block might be "
                f"sub-optimal  \nThe timing for the instance {inst}, "
                f"implemented as a RAM block, might be sub-optimal as no "
                f"output register was merged into the block.\n"
                f"Related violations: <none>\n\n")
    ok = "".join(entry(n + 1, inst)
                 for n, inst in enumerate(sorted(PICORV32_SYNTH6_ALLOW)))
    if validate_synth6_set(ok, "u_puf64_core/u_macro", 8) is not None:
        print("SELFTEST_FAIL: exact allowlist rejected")
        return 1
    foreign = ok.replace(sorted(PICORV32_SYNTH6_ALLOW)[0],
                         "u_operational_uart/u_chain/u_mlkem/u_server/ntt/RAM9/inst/mem_reg")
    if validate_synth6_set(foreign, "u_puf64_core/u_macro", 8) is None:
        print("SELFTEST_FAIL: foreign instance accepted")
        return 1
    missing = "".join(entry(n + 1, inst)
                      for n, inst in enumerate(sorted(PICORV32_SYNTH6_ALLOW)[:7]))
    if validate_synth6_set(missing, "u_puf64_core/u_macro", 7) is None:
        print("SELFTEST_FAIL: missing instance accepted")
        return 1
    if any("u_macro" in p or "u_bench" in p or "ro[" in p
           for p in PICORV32_SYNTH6_ALLOW):
        print("SELFTEST_FAIL: allowlist touches PUF macro hier")
        return 1
    print("SYNTH6_SELFTEST_PASS")
    return 0


def summary_table(text: str) -> dict:
    out = {}
    for m in re.finditer(
            r"^\|\s*([A-Z]+[A-Z0-9-]*)\s*\|\s*(Warning|Critical Warning|Error)\s*\|[^\|]*\|\s*(\d+)\s*\|",
            text, re.MULTILINE):
        out[m.group(1)] = (m.group(2), int(m.group(3)))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("runs_dir", nargs="?")
    ap.add_argument("report_dir", nargs="?")
    ap.add_argument("clock", nargs="?")
    ap.add_argument("hier", nargs="?")
    ap.add_argument("--profile", choices=("final", "picorv32"), default="final")
    ap.add_argument("--selftest", action="store_true",
                    help="negative self-test of the SYNTH-6 exact-set gate")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    if not all((args.runs_dir, args.report_dir, args.clock, args.hier)):
        ap.error("runs_dir report_dir clock hier are required without --selftest")
    runs, rep, clock, hier = (Path(args.runs_dir), Path(args.report_dir),
                              args.clock, args.hier)
    slog = runs / "synth_1/runme.log"
    ilog = runs / "impl_1/runme.log"
    drc = rep / "post_route_drc.rpt"
    mth = rep / "post_route_methodology.rpt"
    tmr = rep / "post_route_timing.rpt"
    for p in (slog, ilog, drc, mth, tmr):
        if not p.is_file():
            fail(f"missing evidence: {p}")
    bits = list((runs / "impl_1").glob("*.bit"))
    if not bits or bits[0].stat().st_size == 0:
        fail("bitstream missing or empty")

    if not ERRORS:
        for lp in (slog, ilog):
            crits = [ln for ln in lp.read_text(encoding="utf-8", errors="replace").splitlines()
                     if "CRITICAL WARNING" in ln and not ln.startswith("#")]
            if crits:
                fail(f"{lp.parent.name}: {len(crits)} CRITICAL, first: {crits[0][:160]}")

    if not ERRORS:
        dtxt = drc.read_text(encoding="utf-8", errors="replace")
        rules_seen = {m.group(1) for m in re.finditer(
            r"^([A-Z]+[A-Z0-9-]*)#\d+ (?:Warning|Critical Warning|Error)\s*$",
            dtxt, re.MULTILINE)}
        if rules_seen != {"LUTLP-2", "PDRC-153", "PLHOLDVIO-2", "ZPS7-1",
                          "DPOP-2", "RTSTAT-10"}:
            fail(f"DRC rule set unexpected: {sorted(rules_seen)}")
        else:
            dsum = summary_table(dtxt)
            for rule, spec in (("LUTLP-2", ("Warning", 64)),
                               ("PDRC-153", ("Warning", 1152)),
                               ("PLHOLDVIO-2", ("Warning", 1152)),
                               ("ZPS7-1", ("Warning", 1)),
                               ("DPOP-2", ("Warning", 2)),
                               ("RTSTAT-10", ("Warning", 1))):
                if dsum.get(rule) != spec:
                    fail(f"DRC {rule} summary unexpected: {dsum.get(rule)}")
            ro_seen: set[int] = set()
            for body in section_entries(dtxt, "LUTLP-2"):
                idxs = {int(m.group(1)) for m in re.finditer(r"ro\[(\d+)\]", body)}
                if len(idxs) != 1:
                    fail("LUTLP-2 entry spans != 1 RO")
                    break
                ro_seen |= idxs
            if ro_seen != set(range(64)):
                fail(f"LUTLP-2 RO set != 0..63 (got {len(ro_seen)})")
            mults = set()
            for body in section_entries(dtxt, "DPOP-2"):
                if "u_mlkem" not in body or "u_mult/product_reg_reg" not in body:
                    fail(f"DPOP-2 outside ML-KEM mult: {body[:140]}")
                    break
                mm = re.search(r"/BU/(M\d+)/", body)
                if mm:
                    mults.add(mm.group(1))
            if mults != {"M0", "M1"}:
                fail(f"DPOP-2 mult set unexpected: {sorted(mults)}")
            rbodies = section_entries(dtxt, "RTSTAT-10")
            if len(rbodies) != 1:
                fail(f"RTSTAT-10 count != 1 (got {len(rbodies)})")
            else:
                rb = rbodies[0]
                if "14 net(s) have no routable loads" not in rb:
                    fail("RTSTAT-10 not the 14-net form")
                for frag in ("response[2015]", "telemetry_pair_a[5:0]",
                             "telemetry_pair_b[5:0]", "telemetry_winner"):
                    if frag not in rb or hier not in rb:
                        fail(f"RTSTAT-10 missing documented net: {frag}")
                        break

    if not ERRORS:
        mtxt = mth.read_text(encoding="utf-8", errors="replace")
        if "macro_clk" in mtxt:
            fail("methodology still references macro_clk (single-clock cleanup incomplete)")
        mrules = {m.group(1) for m in re.finditer(
            r"^([A-Z]+[A-Z0-9-]*)#\d+ (?:Warning|Critical Warning|Error)\s*$",
            mtxt, re.MULTILINE)}
        if mrules != {"TIMING-17", "TIMING-23", "LUTAR-1", "SYNTH-6",
                      "TIMING-30", "ULMTCS-1", "XDCC-4", "XDCC-8"}:
            fail(f"methodology rule set unexpected: {sorted(mrules)}")
        else:
            msum = summary_table(mtxt)
            synth6_spec = (("Warning", 8),) if args.profile == "picorv32" else (("Warning", 1),)
            for rule, spec in (("TIMING-17", ("Critical Warning", 1000)),
                               ("TIMING-23", ("Warning", 64)),
                               ("LUTAR-1", ("Warning", 4)),
                               ("TIMING-30", ("Warning", 1)),
                               ("ULMTCS-1", ("Warning", 1)),
                               ("XDCC-4", ("Warning", 2)),
                               ("XDCC-8", ("Warning", 2))):
                if msum.get(rule) != spec:
                    fail(f"methodology {rule} summary unexpected: {msum.get(rule)}")
            if msum.get("SYNTH-6") not in synth6_spec:
                fail(f"methodology SYNTH-6 summary unexpected: {msum.get('SYNTH-6')}")
            synth6_instances = re.findall(
                r"SYNTH-6#\d+ Warning\s+Timing of a RAM block might be sub-optimal\s+"
                r"The timing for the instance (\S+),", mtxt)
            allowed_synth6 = {
                "u_operational_uart/u_chain/u_mlkem/u_server/hash/ififo_inst/inst/mem_reg",
                "u_operational_uart/u_chain/u_mlkem/u_server/hash/ofifo1_inst/inst/mem_reg",
                "u_operational_uart/u_chain/u_mlkem/u_server/hash/ofifo_inst/inst/mem_reg_1",
                "u_operational_uart/u_chain/u_mlkem/u_server/ntt/RAM0/inst/mem_reg",
                "u_operational_uart/u_chain/u_mlkem/u_server/ntt/RAM1/inst/mem_reg",
                "u_operational_uart/u_chain/u_mlkem/u_server/ntt/RAM2/inst/mem_reg",
                "u_operational_uart/u_chain/u_mlkem/u_server/ntt/RAM3/inst/mem_reg",
                "u_operational_uart/u_chain/u_mlkem/u_server/ntt/RAM4/inst/mem_reg_1",
            }
            # Exact-set equality: also rejects reappearing firmware-BRAM or
            # any foreign/latch/truncation warning masquerading as SYNTH-6.
            # None of the 8 may sit under the PUF macro hier.
            if (len(synth6_instances) != msum.get("SYNTH-6", (None, 0))[1]
                    or set(synth6_instances) != allowed_synth6
                    or any(hier in inst for inst in synth6_instances)):
                fail(f"methodology SYNTH-6 instance set unexpected: {synth6_instances}")
            # TIMING-17 must be ripple C pins under the macro hier.
            pat17 = re.escape(hier) + r"ro\[\d+\]\.counter/(presc_fdce|stage\[\d+\]\.ff)/C"
            for body in section_entries(mtxt, "TIMING-17"):
                if not re.search(pat17, body):
                    fail(f"TIMING-17 not a ripple C pin: {body[:120]}")
                    break
            # TIMING-23 must cover all 64 ROs under hier.
            ro23 = set()
            for body in section_entries(mtxt, "TIMING-23"):
                for m in re.finditer(r"ro\[(\d+)\]", body):
                    ro23.add(int(m.group(1)))
                if hier not in body:
                    fail(f"TIMING-23 outside {hier}")
                    break
            if ro23 != set(range(64)):
                fail(f"TIMING-23 RO set != 0..63 (got {len(ro23)})")

    if not ERRORS:
        ttxt = tmr.read_text(encoding="utf-8", errors="replace")
        if re.search(r"VIOLATED|Timing constraints are not met", ttxt):
            fail("timing violations present")
        if "macro_clk" in ttxt:
            fail("timing still contains macro_clk (single-clock cleanup incomplete)")
        m = re.search(rf"^\s*{re.escape(clock)}\s+([-\d.]+)\s+([-\d.]+)", ttxt, re.MULTILINE)
        if not m or float(m.group(1)) < 0:
            fail(f"{clock} WNS unexpected")

    if ERRORS:
        print("FINAL_IMAGE_REPORT_GATE_FAIL", file=sys.stderr)
        for e in ERRORS:
            print(f"- {e}", file=sys.stderr)
        return 1
    h = hashlib.sha256()
    with open(bits[0], "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    print("FINAL_IMAGE_REPORT_GATE_PASS")
    print(f"profile={args.profile}-single-clock")
    print(f"bitstream_sha256={h.hexdigest()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
