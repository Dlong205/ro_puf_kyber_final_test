#!/usr/bin/env python3
"""V2 project-image report gate, per-image profiles (char + operational).

Checks DRC + methodology + timing + runme 0-critical + bitstream presence,
with EXACT allow-lists.  Anything outside the profile fails closed.

Profiles:
- char: DRC {LUTLP-2:64, PDRC-153:1152, PLHOLDVIO-2:1152, ZPS7-1:1};
  methodology {TIMING-17:1000 ripple-C, TIMING-18:{LED0,LED1},
  TIMING-23:64, ULMTCS-1:1}; <clock> WNS >= 0.
- operational: char DRC plus {DPOP-2:2 M0/M1 mults (golden ML-KEM RTL),
  RTSTAT-10:1 (14 documented unconnected macro nets)}; methodology plus
  {TIMING-4:2, TIMING-6:2, TIMING-27:1 (macro_clk import, dual-clock
  conservative pass), LUTAR-1:4, SYNTH-6:9, TIMING-30:1, XDCC-4:2} with
  TIMING-18:0; WNS >= 0 on clk_sys, macro_clk intra and both inter pairs.
  The macro_clk dual-clock finding is a known limitation with an R5-final
  single-clock task; STA passes conservatively on all pairs.

Usage:
  python3 scripts/check_v2_image_reports.py <runs> <reports> <clock> <hier>
      [--profile char|operational]   (default char)
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


def summary_table(text: str) -> dict:
    out = {}
    for m in re.finditer(
            r"^\|\s*([A-Z]+[A-Z0-9-]*)\s*\|\s*(Warning|Critical Warning|Error)\s*\|[^\|]*\|\s*(\d+)\s*\|",
            text, re.MULTILINE):
        out[m.group(1)] = (m.group(2), int(m.group(3)))
    return out


def check_drc_base(dtxt, hier):
    want = {"LUTLP-2": ("Warning", 64), "PDRC-153": ("Warning", 1152),
            "PLHOLDVIO-2": ("Warning", 1152), "ZPS7-1": ("Warning", 1)}
    summary = summary_table(dtxt)
    for rule, spec in want.items():
        if summary.get(rule) != spec:
            fail(f"DRC {rule} summary unexpected: {summary.get(rule)}")
    ro_seen: set[int] = set()
    for body in section_entries(dtxt, "LUTLP-2"):
        idxs = {int(m.group(1)) for m in re.finditer(r"ro\[(\d+)\]", body)}
        if len(idxs) != 1:
            fail("LUTLP-2 entry spans != 1 RO");
            break
        ro_seen |= idxs
        for ln in body.splitlines():
            if "ro[" in ln and hier not in ln:
                fail(f"LUTLP-2 line outside {hier}: {ln[:120]}")
                break
    if ro_seen != set(range(64)):
        fail(f"LUTLP-2 RO set != 0..63 (got {len(ro_seen)})")
    hp = re.escape(hier)
    for rule, pat, what in (
            ("PDRC-153", r"Net (\S+) is a gated clock",
             rf"{hp}ro\[\d+\]\.(counter/(n_presc|n_qq\[\d+\])|ro_cell/u_backend/t3)$"),
            ("PLHOLDVIO-2", r"A LUT (\S+) is driving clock pin",
             rf"{hp}ro\[\d+\]\.(counter/(inv_presc|stage\[\d+\]\.inv)|ro_cell/u_backend/LUT6_INV2)$")):
        got = set()
        ok = True
        for body in section_entries(dtxt, rule):
            m = re.search(pat, body)
            if not m:
                fail(f"{rule} entry without target");
                ok = False;
                break
            got.add(m.group(1))
        if ok and (len(got) != 1152 or any(not re.search(what, n) for n in got)):
            fail(f"{rule} set unexpected (n={len(got)})")


def check_meth_base(mtxt, hier):
    ro23 = set()
    for body in section_entries(mtxt, "TIMING-23"):
        for m in re.finditer(r"ro\[(\d+)\]", body):
            ro23.add(int(m.group(1)))
        if hier not in body:
            fail(f"TIMING-23 outside {hier}");
            break
    if ro23 != set(range(64)):
        fail(f"TIMING-23 RO set != 0..63 (got {len(ro23)})")
    pat17 = re.escape(hier) + r"ro\[\d+\]\.counter/(presc_fdce|stage\[\d+\]\.ff)/C"
    for body in section_entries(mtxt, "TIMING-17"):
        if not re.search(pat17, body):
            fail(f"TIMING-17 not a ripple C pin: {body[:120]}");
            break


def check_clock_import_forms(mtxt, hier_pin, other_clocks):
    """macro_clk OOC-import footprint: TIMING-4 x2 (macro_clk downstream of
    each clock in other_clocks), TIMING-6 x2 (dual-clock), TIMING-27 x1
    (primary on the macro hier pin).  STA passes conservatively on all pairs;
    the R5-final single-clock cleanup is tracked separately."""
    for body in section_entries(mtxt, "TIMING-4"):
        if "macro_clk" not in body or \
                not any(c in body for c in other_clocks):
            fail(f"TIMING-4 not the macro_clk import form: {body[:140]}");
            break
    for body in section_entries(mtxt, "TIMING-6"):
        if "clk_sys_100mhz" not in body or "macro_clk" not in body or \
                "no common primary" not in body.lower():
            fail(f"TIMING-6 not the dual-clock form: {body[:140]}");
            break
    for body in section_entries(mtxt, "TIMING-27"):
        if "macro_clk" not in body or hier_pin not in body:
            fail(f"TIMING-27 not the hier-pin form: {body[:140]}");
            break


def xdcc_kinds(mtxt, rule):
    kinds = set()
    for body in section_entries(mtxt, rule):
        if "create_clock" in body and "clk_in_50mhz" in body:
            kinds.add("create_clock:clk_in_50mhz")
        elif "create_generated_clock" in body and "clk_sys_100mhz" in body:
            kinds.add("generated:clk_sys_100mhz")
        else:
            fail(f"{rule} unexpected form: {body[:140]}");
            break
    return kinds


def check_xdcc_duplicates(mtxt):
    """Top XDC re-read at synth+impl: identical duplicate definitions only."""
    for body in section_entries(mtxt, "XDCC-4"):
        if "overrides a previous" not in body:
            fail(f"XDCC-4 not a duplicate form: {body[:140]}");
            break
    if xdcc_kinds(mtxt, "XDCC-4") != {"create_clock:clk_in_50mhz",
                                      "generated:clk_sys_100mhz"}:
        fail("XDCC-4 kind set unexpected")
    for body in section_entries(mtxt, "XDCC-8"):
        if "overwritten on the same source" not in body:
            fail(f"XDCC-8 not a same-source form: {body[:140]}");
            break
    if xdcc_kinds(mtxt, "XDCC-8") != {"create_clock:clk_in_50mhz",
                                      "generated:clk_sys_100mhz"}:
        fail("XDCC-8 kind set unexpected")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("runs_dir")
    ap.add_argument("report_dir")
    ap.add_argument("clock")
    ap.add_argument("hier")
    ap.add_argument("--profile", choices=["char", "operational"], default="char")
    args = ap.parse_args()
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
        check_drc_base(dtxt, hier)
        rules_seen = {m.group(1) for m in re.finditer(
            r"^([A-Z]+[A-Z0-9-]*)#\d+ (?:Warning|Critical Warning|Error)\s*$",
            dtxt, re.MULTILINE)}
        if args.profile == "char":
            if rules_seen != {"LUTLP-2", "PDRC-153", "PLHOLDVIO-2", "ZPS7-1",
                              "CHECK-3", "REQP-1839"}:
                fail(f"DRC rule set unexpected: {sorted(rules_seen)}")
            dsum = summary_table(dtxt)
            for rule, spec in (("CHECK-3", ("Warning", 1)),
                               ("LUTLP-2", ("Warning", 64)),
                               ("PDRC-153", ("Warning", 1152)),
                               ("PLHOLDVIO-2", ("Warning", 1152)),
                               ("REQP-1839", ("Warning", 20)),
                               ("ZPS7-1", ("Warning", 1))):
                if dsum.get(rule) != spec:
                    fail(f"DRC {rule} summary unexpected: {dsum.get(rule)}")
            for b in section_entries(dtxt, "CHECK-3"):
                if "REQP-1839" not in b:
                    fail("CHECK-3 not tied to REQP-1839 cap")
            for b in section_entries(dtxt, "REQP-1839"):
                mb = re.search(r"RAMB36E1 (\S+)", b)
                md = re.search(r"register \((\S+)\)", b)
                if not mb or not mb.group(1).startswith("u_uart/telemetry_mem_reg_"):
                    fail(f"REQP-1839 not uart telemetry BRAM: {b[:140]}");
                    break
                if not md or not md.group(1).startswith("u_macro/u_bench/"):
                    fail(f"REQP-1839 driver outside macro: {b[:140]}");
                    break
        else:
            if rules_seen != {"LUTLP-2", "PDRC-153", "PLHOLDVIO-2", "ZPS7-1",
                              "DPOP-2", "RTSTAT-10"}:
                fail(f"DRC rule set unexpected: {sorted(rules_seen)}")
            dsum = summary_table(dtxt)
            for rule, spec in (("LUTLP-2", ("Warning", 64)),
                               ("PDRC-153", ("Warning", 1152)),
                               ("PLHOLDVIO-2", ("Warning", 1152)),
                               ("ZPS7-1", ("Warning", 1)),
                               ("DPOP-2", ("Warning", 2)),
                               ("RTSTAT-10", ("Warning", 1))):
                if dsum.get(rule) != spec:
                    fail(f"DRC {rule} summary unexpected: {dsum.get(rule)}")
            mults = set()
            for body in section_entries(dtxt, "DPOP-2"):
                m = re.search(r"u_mlkem/(?:.*/)?u_mult/product_reg_reg", body)
                if not m:
                    fail(f"DPOP-2 outside ML-KEM mult: {body[:140]}");
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
                        fail(f"RTSTAT-10 missing documented net: {frag}");
                        break

    if not ERRORS:
        mtxt = mth.read_text(encoding="utf-8", errors="replace")
        mrules = {m.group(1) for m in re.finditer(
            r"^([A-Z]+[A-Z0-9-]*)#\d+ (?:Warning|Critical Warning|Error)\s*$",
            mtxt, re.MULTILINE)}
        check_meth_base(mtxt, hier)
        if args.profile == "char":
            if mrules != {"TIMING-4", "TIMING-6", "TIMING-17", "TIMING-27",
                          "SYNTH-6", "TIMING-18", "TIMING-23", "TIMING-30",
                          "ULMTCS-1", "XDCC-4", "XDCC-8"}:
                fail(f"methodology rule set unexpected: {sorted(mrules)}")
            msum = summary_table(mtxt)
            for rule, spec in (("TIMING-4", ("Critical Warning", 2)),
                               ("TIMING-6", ("Critical Warning", 2)),
                               ("TIMING-17", ("Critical Warning", 1000)),
                               ("TIMING-27", ("Critical Warning", 1)),
                               ("SYNTH-6", ("Warning", 4)),
                               ("TIMING-23", ("Warning", 64)),
                               ("TIMING-30", ("Warning", 1)),
                               ("ULMTCS-1", ("Warning", 1)),
                               ("XDCC-4", ("Warning", 2)),
                               ("XDCC-8", ("Warning", 2))):
                if msum.get(rule) != spec:
                    fail(f"methodology {rule} summary unexpected: {msum.get(rule)}")
            check_clock_import_forms(mtxt, "u_macro/clk", {"clk_in_50mhz", "clk_sys_pre"})
            for body in section_entries(mtxt, "SYNTH-6"):
                if "telemetry_mem" not in body or "u_uart" not in body:
                    fail(f"SYNTH-6 not uart telemetry RAM: {body[:140]}");
                    break
            for body in section_entries(mtxt, "TIMING-30"):
                if "clk_sys_100mhz" not in body:
                    fail(f"TIMING-30 not the sys clock form: {body[:140]}");
                    break
            check_xdcc_duplicates(mtxt)
            m18 = section_entries(mtxt, "TIMING-18")
            if len(m18) != 2:
                fail(f"TIMING-18 count != 2 (got {len(m18)})")
            else:
                ports18 = set()
                for body in m18:
                    m = re.search(r"delay is missing on (\S+)", body)
                    if not m or "/" in m.group(1):
                        fail(f"TIMING-18 not a top port: {body[:120]}");
                        break
                    ports18.add(m.group(1))
                if ports18 != {"LED[0]", "LED[1]"}:
                    fail(f"TIMING-18 ports unexpected: {sorted(ports18)}")
            msum = summary_table(mtxt)
            for rule, spec in (("TIMING-17", ("Critical Warning", 1000)),
                               ("TIMING-23", ("Warning", 64)),
                               ("ULMTCS-1", ("Warning", 1))):
                if msum.get(rule) != spec:
                    fail(f"methodology {rule} summary unexpected: {msum.get(rule)}")
        else:
            if mrules != {"TIMING-4", "TIMING-6", "TIMING-17", "TIMING-27",
                          "LUTAR-1", "SYNTH-6", "TIMING-23", "TIMING-30",
                          "ULMTCS-1", "XDCC-4", "XDCC-8"}:
                fail(f"methodology rule set unexpected: {sorted(mrules)}")
            msum = summary_table(mtxt)
            for rule, spec in (("TIMING-4", ("Critical Warning", 2)),
                               ("TIMING-6", ("Critical Warning", 2)),
                               ("TIMING-17", ("Critical Warning", 1000)),
                               ("LUTAR-1", ("Warning", 4)),
                               ("SYNTH-6", ("Warning", 9)),
                               ("TIMING-23", ("Warning", 64)),
                               ("TIMING-30", ("Warning", 1)),
                               ("ULMTCS-1", ("Warning", 1)),
                               ("XDCC-4", ("Warning", 2)),
                               ("XDCC-8", ("Warning", 2))):
                if msum.get(rule) != spec:
                    fail(f"methodology {rule} summary unexpected: {msum.get(rule)}")
            check_clock_import_forms(mtxt, "u_macro/clk", {"clk_100_raw", "clk_in_50mhz"})
            for body in section_entries(mtxt, "LUTAR-1"):
                cells = re.findall(r"u_operational_uart/\S+", body)
                if not cells or any(
                        not ("/u_mlkem/" in c or "/u_kcv/" in c or
                             re.search(r"/u_macro/u_bench/(done_r|FSM_sequential_state_r)", c))
                        for c in cells):
                    fail(f"LUTAR-1 outside documented cones: {body[:160]}");
                    break
            for body in section_entries(mtxt, "SYNTH-6"):
                if "mem_reg" not in body or "u_mlkem" not in body:
                    fail(f"SYNTH-6 not an ML-KEM RAM: {body[:140]}");
                    break
            for body in section_entries(mtxt, "TIMING-30"):
                if "clk_sys_100mhz" not in body:
                    fail(f"TIMING-30 not the sys clock form: {body[:140]}");
                    break
            check_xdcc_duplicates(mtxt)

    if not ERRORS:
        ttxt = tmr.read_text(encoding="utf-8", errors="replace")
        if re.search(r"VIOLATED|Timing constraints are not met", ttxt):
            fail("timing violations present")
        m = re.search(rf"^\s*{re.escape(clock)}\s+([-\d.]+)\s+([-\d.]+)", ttxt, re.MULTILINE)
        if not m or float(m.group(1)) < 0:
            fail(f"{clock} WNS unexpected")
        if args.profile == "operational":
            for pat, label in (
                    (r"^\s*macro_clk\s+([-\d.]+)", "macro_clk intra"),
                    (r"^macro_clk\s+clk_sys_100mhz\s+([-\d.]+)", "macro_clk->clk_sys"),
                    (r"^clk_sys_100mhz\s+macro_clk\s+([-\d.]+)", "clk_sys->macro_clk")):
                mm = re.search(pat, ttxt, re.MULTILINE)
                if not mm or float(mm.group(1)) < 0:
                    fail(f"{label} WNS unexpected")

    if ERRORS:
        print("V2_IMAGE_REPORT_GATE_FAIL", file=sys.stderr)
        for e in ERRORS:
            print(f"- {e}", file=sys.stderr)
        return 1
    h = hashlib.sha256()
    with open(bits[0], "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    print("V2_IMAGE_REPORT_GATE_PASS")
    print(f"profile={args.profile}")
    print(f"bitstream_sha256={h.hexdigest()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
