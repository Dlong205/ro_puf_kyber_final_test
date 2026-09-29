#!/usr/bin/env python3
"""Static FINAL gate (no Vivado, no secrets in logs).

Checks the operational-final shell before any build:
- final top: DEVICE_TRUSTED_KCV 56-hex non-zero, ROM_VALID=1, ROM_REF bound,
  lifecycle locks ALLOW_ENROLL/LEGACY_HELPER/DIAGNOSTIC=0, provision tied 0,
  no PRESERVATION token, no placeholder/nonrelease paths
- project: frozen v2_mapping_frozen FIRST, correct top/XDC, no placeholder or
  real-macro RTL, no forbidden tops
- XDC: single-clock shell (clk_in_50mhz + clk_sys_100mhz, no macro_clk
  create_clock, no FIXED_ROUTE, no LOC/BEL locks)
- mapping: frozen tag 0x81b5 digest provenance + generator --check in sync
- anchor provenance: SHAs only (never KCV/reference/helper values)
- no program_*.tcl references the final bitstream (never programmed here)

Any failure is fail-closed with no build.
"""
from pathlib import Path
import hashlib
import json
import os
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
# R8 cutover: PUF64_MAPPING_R7=1 retargets mapping/anchor checks to the
# holdout-qualified R7 generation (tag 0x81B7). Default (unset) checks gen1.
R7 = os.environ.get("PUF64_MAPPING_R7") == "1"
TOP = ROOT / "rtl/top/Edge_Puf64_Zynq_Operational_Final_100MHz_Top.sv"
PROJ = ROOT / "scripts/create_puf64_operational_final_project.tcl"
XDC = ROOT / "constraints/edge_puf64_zynq_operational_final_100mhz.xdc"
FROZEN_VH = ROOT / "rtl/puf/v2_mapping_frozen/puf64_mapping_data.vh"
R7_VH = ROOT / "rtl/puf/v2_mapping_r7/puf64_mapping_data.vh"
R7_MANIFEST = ROOT / "constraints/puf64_r7_mapping_manifest.json"
PLACEHOLDER = ROOT / "rtl/puf/v2_construction_placeholder/puf64_mapping_data.vh"
ANCHOR = ROOT / "reports/puf64_macrov2_campaign/private_device_anchor.json"
HELPER = ROOT / "reports/puf64_macrov2_campaign/private_enrollment_helper.record"
R7_ANCHOR = ROOT / "reports/puf64_finalchar_campaign/r7_anchor.json"
R7_HELPER = ROOT / "reports/puf64_finalchar_campaign/r7_helper.record"
R7_TAG_HEX = "0x81b7"
R7_DIGEST = "95186338708b34c4fdb4ed653e2264592fc9321c6c381ced66d45bfe785c3aab"
R7_SELECTION = "b1b2b076d7059bd95f5a2e9c6783e9fe7248bbdfc13eccda0ee66abe7d56bf5b"
R7_KCV_CTX = "0x0181b701010102"
FINAL_BIT = "Edge_Puf64_Zynq_Operational_Final_100MHz_Top.bit"

ERRORS: list[str] = []


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main() -> int:
    if not TOP.is_file():
        ERRORS.append("final top missing")
        print("FINAL_STATIC_GATE_FAIL", file=sys.stderr)
        for e in ERRORS:
            print(f"- {e}", file=sys.stderr)
        return 1
    top = TOP.read_text(encoding="utf-8")
    for tok in ("module Edge_Puf64_Zynq_Operational_Final_100MHz_Top",
                "localparam bit ALLOW_ENROLL         = 1'b0;",
                "localparam bit LEGACY_HELPER_ENABLE = 1'b0;",
                "localparam bit DIAGNOSTIC_ANCHOR    = 1'b0;",
                ".DIAGNOSTIC(DIAGNOSTIC_ANCHOR)",
                ".ROM_REF(DEVICE_TRUSTED_KCV)",
                ".ROM_VALID(1'b1)",
                ".provision(1'b0),",
                ".provision_ref(224'd0),",
                ".provision_valid(1'b0),",
                "edge_puf64_operational_uart_v2"):
        if tok not in top:
            ERRORS.append(f"top missing: {tok}")
    for bad in ("PRESERVATION_ANCHOR", "49345f505245534552564154494f4e",
                "NEVER PROGRAM",
                "PLACEHOLDER", "v2_construction_placeholder"):
        if bad in top:
            ERRORS.append(f"top carries nonrelease path: {bad}")
    # R7 characterize-through-final: the top may carry the parameterized
    # qual path, but release defaults must hold in SOURCE (char builds
    # override via project generics, never by editing RTL).
    for tok in ("parameter bit     QUALIFICATION_NONRELEASE = 1'b0,",
                "parameter bit     QUAL_TELEMETRY_ENABLE = 1'b0,",
                "parameter [7:0]   QUAL_INFO_MARKER = 8'h0f"):
        if tok not in top:
            ERRORS.append(f"top R7 default drift (must stay release): {tok}")
    m = re.search(r"DEVICE_TRUSTED_KCV\s*=\s*224'h([0-9a-fA-F]{56})", top)
    if not m:
        ERRORS.append("anchor declaration missing or malformed")
    elif int(m.group(1), 16) == 0:
        ERRORS.append("anchor unprovisioned (all zeros); run embed_final_anchor.py")
    if "FINAL_ANCHOR_UNPROVISIONED" in top:
        ERRORS.append("anchor marker still unprovisioned")

    proj = PROJ.read_text(encoding="utf-8") if PROJ.is_file() else ""
    if not PROJ.is_file():
        ERRORS.append("final project script missing")
    else:
        for tok in ("Edge_Puf64_Zynq_Operational_Final_100MHz_Top",
                    "kp_puf64_macro_v2_bb.sv",
                    "v2_mapping_frozen",
                    "edge_puf64_zynq_operational_final_100mhz.xdc",
                    "FINAL_MAPPING=FROZEN_0x81b5"):
            if tok not in proj:
                ERRORS.append(f"project missing: {tok}")
        if R7 and ("v2_mapping_r7" not in proj
                   or "FINAL_MAPPING=R7_0x81b7" not in proj):
            ERRORS.append("project missing R7 mapping selection")
        # Only flag real inclusions, not fail-closed guard strings inside the
        # `foreach bad` block. Track guard membership precisely.
        in_guard = False
        for ln in proj.splitlines():
            s = ln.strip()
            if s.startswith("#"):
                continue
            if "foreach bad" in ln:
                in_guard = True
                continue
            if in_guard:
                if "forbidden source in project" in ln:
                    in_guard = False
                continue
            if "v2_construction_placeholder" in ln:
                ERRORS.append("project references placeholder dir")
                break
        for ln in proj.splitlines():
            s = ln.strip()
            if s.startswith("#"):
                continue
            if "Edge_Puf64_Zynq_Operational_V2_100MHz_Top.sv" in ln and "add_files" in ln:
                ERRORS.append("project references construction top")
                break

    xdc = XDC.read_text(encoding="utf-8") if XDC.is_file() else ""
    if not XDC.is_file():
        ERRORS.append("final XDC missing")
    else:
        for tok in ("create_clock -name clk_in_50mhz",
                    "create_generated_clock -name clk_sys_100mhz"):
            if tok not in xdc:
                ERRORS.append(f"XDC missing: {tok}")
        code_lines = [ln for ln in xdc.splitlines()
                      if not ln.strip().startswith("#")]
        code_text = "\n".join(code_lines)
        if re.search(r"create_(generated_)?clock.*macro_clk", code_text):
            ERRORS.append("XDC defines macro_clk (must be removed post-import only)")
        if "set_property FIXED_ROUTE" in code_text or "FIXED_ROUTE true" in code_text:
            ERRORS.append("XDC carries FIXED_ROUTE locks (macro via DCP only)")
        if "IS_LOC_FIXED" in code_text or "IS_BEL_FIXED" in code_text \
                or "IS_ROUTE_FIXED" in code_text:
            ERRORS.append("XDC carries placement/route locks (macro via DCP only)")

    vh_path = R7_VH if R7 else FROZEN_VH
    vh = vh_path.read_text(encoding="utf-8") if vh_path.is_file() else ""
    if R7:
        if "16'h81b7" not in vh or R7_DIGEST not in vh \
                or R7_SELECTION not in vh:
            ERRORS.append("R7 mapping tag/digest/selection mismatch")
        try:
            r = subprocess.run(
                [sys.executable, "host/puf64_r7_emit_mapping.py"],
                cwd=str(ROOT), capture_output=True, text=True, timeout=120)
            if r.returncode != 0 or "R7_EMIT_PASS" not in (r.stdout or ""):
                ERRORS.append(f"R7 mapping emitter drift: {(r.stderr or r.stdout).strip()[:200]}")
        except (OSError, subprocess.SubprocessError) as e:
            ERRORS.append(f"R7 mapping check failed: {type(e).__name__}")
    else:
        if "16'h81b5" not in vh or \
                "b581f44f7c36b451e1ae4e9afc53bab7b2646ed7414ba70514f3354b88cc1ae1" not in vh:
            ERRORS.append("frozen mapping tag/digest mismatch")
        try:
            r = subprocess.run(
                [sys.executable, "host/puf64_macrov2_generate_mapping.py", "--check"],
                cwd=str(ROOT), capture_output=True, text=True, timeout=120)
            if r.returncode != 0:
                ERRORS.append(f"mapping generator drift: {(r.stderr or r.stdout).strip()[:200]}")
        except (OSError, subprocess.SubprocessError) as e:
            ERRORS.append(f"mapping check failed: {type(e).__name__}")

    anchor_path = R7_ANCHOR if R7 else ANCHOR
    helper_path = R7_HELPER if R7 else HELPER
    if not anchor_path.is_file() or not helper_path.is_file():
        ERRORS.append("anchor/helper provenance files missing")
    else:
        try:
            anchor = json.loads(anchor_path.read_text())
        except (OSError, ValueError):
            anchor = {}
            ERRORS.append("anchor manifest unreadable")
        for key, want in (
                ("board_id", "ZYNQ-A01"),
                ("selection_sha256", R7_SELECTION if R7 else "2e37c3c11d5c02cfd0bbc21e0837f2738b24e0de9ad020f596fc1381e449d317")):
            if anchor.get(key) != want:
                ERRORS.append(f"anchor provenance mismatch: {key}")
        if not R7:
            for key, want in (
                    ("bitstream_sha256", "cfc72674b654d1f44d5fcb0eed8ed7dc51b2b27a7f8ed9283c7ad6d1878699bd"),
                    ("macro_dcp_sha256", "bd0cd6200ca4e122932596eb8502d29f1b7d4b1aedf974a79990b4d1f5a9fdd4"),
                    ("fingerprint_sha256", "7d12e3a99849f6d6351e414ebe17829fa2175cdbe42c55bc19df27bbd45afbf5")):
                if anchor.get(key) != want:
                    ERRORS.append(f"anchor provenance mismatch: {key}")
        if anchor.get("kcv_ctx") != (R7_KCV_CTX if R7 else "0x0181b501010102"):
            ERRORS.append("anchor kcv_ctx mismatch")
        # Never log KCV/reference/helper values; SHAs only.
        if helper_path.is_file():
            hsha = sha256_file(helper_path)
            if anchor.get("helper_record_sha256") != hsha:
                ERRORS.append("helper SHA not bound to anchor")

    # program_puf64_operational_final.tcl is the authorized SHA-gated E2E
    # program path (single target/device, exact-SHA, volatile PL only);
    # program_puf64_operational_final_char.tcl is the authorized SHA-gated
    # bench-characterization path (char dir only, never release);
    # program_puf64_operational_final_r7.tcl is the authorized SHA-gated
    # R7 release path (R7 dir only).
    # Every other program script must stay off the final bitstream.
    for prog in (ROOT / "scripts").glob("program_*.tcl"):
        if prog.name in ("program_puf64_operational_final.tcl",
                         "program_puf64_operational_final_char.tcl",
                         "program_puf64_operational_final_r7.tcl"):
            continue
        try:
            if FINAL_BIT in prog.read_text(encoding="utf-8"):
                ERRORS.append(f"{prog.name} references final bitstream (no program in this phase)")
        except OSError:
            pass

    if ERRORS:
        print("FINAL_STATIC_GATE_FAIL", file=sys.stderr)
        for e in ERRORS:
            print(f"- {e}", file=sys.stderr)
        return 1
    print("FINAL_STATIC_GATE_PASS" + (" [R7]" if R7 else ""))
    print(f"mapping_tag={'0x81b7' if R7 else '0x81b5'} "
          f"digest={R7_DIGEST[:8] + '..' if R7 else 'b581f44f..'}")
    print(f"mapping_vh_sha256={sha256_file(vh_path)}")
    print(f"anchor_file_sha256={sha256_file(anchor_path)}")
    print(f"helper_record_sha256={sha256_file(helper_path)}")
    print(f"top_sha256={sha256_file(TOP)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
