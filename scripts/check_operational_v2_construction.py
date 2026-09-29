#!/usr/bin/env python3
"""R5-shell construction gate (static, no Vivado).

Verifies the operational-V2 construction shell is correctly isolated:
- _v2 modules reference only _v2 submodules + black-box macro (code, not comments)
- placeholder mapping carries TAG 0x0000 + NON-RELEASE markers
- golden mapping vh still carries TAG 0xd501 (proves no overwrite)
- shell project: placeholder include dir FIRST, stub in sources, no real
  macro RTL / golden bench / golden tops
- no program_*.tcl script references the shell bitstream (never programmable)
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
TOP = ROOT / "rtl/top/Edge_Puf64_Zynq_Operational_V2_100MHz_Top.sv"
CORE = ROOT / "rtl/top/edge_puf64_operational_core_v2.sv"
CHAIN = ROOT / "rtl/top/edge_puf64_operational_chain_v2.sv"
UART = ROOT / "rtl/top/edge_puf64_operational_uart_v2.sv"
PH = ROOT / "rtl/puf/v2_construction_placeholder/puf64_mapping_data.vh"
GOLD = ROOT / "rtl/top/puf64_mapping_data.vh"
PROJ = ROOT / "scripts/create_puf64_operational_v2_project.tcl"
SHELL_BIT = "Edge_Puf64_Zynq_Operational_V2_100MHz_Top.bit"

ERRORS: list[str] = []


def code(path: Path) -> str:
    return "\n".join(ln.split("//")[0] for ln in path.read_text(encoding="utf-8").splitlines())


def main() -> int:
    c, ch, u, t = (code(p) for p in (CORE, CHAIN, UART, TOP))
    if "module edge_puf64_operational_core_v2" not in c:
        ERRORS.append("core_v2 module name")
    if "kp_puf64_macro_v2 u_macro" not in c:
        ERRORS.append("core_v2 must instantiate black-box macro as u_macro")
    if "kp_puf64_macro_v2 #(" in c:
        ERRORS.append("macro instance must not carry parameter overrides")
    if "kp_puf64_physical" in c or "u_puf64_physical" in c:
        ERRORS.append("core_v2 references golden physical wrapper")
    if "module edge_puf64_operational_chain_v2" not in ch:
        ERRORS.append("chain_v2 module name")
    if "edge_puf64_operational_core_v2" not in ch or "edge_puf64_operational_core #(" in ch:
        ERRORS.append("chain_v2 must use core_v2 only")
    if "module edge_puf64_operational_uart_v2" not in u:
        ERRORS.append("uart_v2 module name")
    if "edge_puf64_operational_chain_v2" not in u or "edge_puf64_operational_chain #(" in u:
        ERRORS.append("uart_v2 must use chain_v2 only")
    if "module Edge_Puf64_Zynq_Operational_V2_100MHz_Top" not in t:
        ERRORS.append("top_v2 module name")
    if "edge_puf64_operational_uart_v2" not in t or "edge_puf64_operational_uart #(" in t:
        ERRORS.append("top_v2 must use uart_v2 only")
    for tok in ("ALLOW_ENROLL         = 1'b0", "LEGACY_HELPER_ENABLE = 1'b0",
                "DIAGNOSTIC_ANCHOR    = 1'b0", ".provision(1'b0)"):
        if tok not in t:
            ERRORS.append(f"top_v2 missing lifecycle lock: {tok}")

    ph = PH.read_text(encoding="utf-8")
    if "16'h0000" not in ph or "NON-RELEASE" not in ph or "NEVER PROGRAM" not in ph:
        ERRORS.append("placeholder mapping lacks NON-RELEASE markings/tag 0x0000")
    gold = GOLD.read_text(encoding="utf-8")
    if "16'hd501" not in gold:
        ERRORS.append("golden mapping vh overwritten (tag 0xd501 missing)")

    proj = PROJ.read_text(encoding="utf-8")
    for tok in ("Edge_Puf64_Zynq_Operational_V2_100MHz_Top",
                "kp_puf64_macro_v2_bb.sv",
                "v2_construction_placeholder",
                "edge_puf64_zynq_operational_v2_100mhz.xdc"):
        if tok not in proj:
            ERRORS.append(f"shell project missing: {tok}")
    import re
    forbidden = {"Puf_AllPairs64_Characterization_Top.sv", "Kyber_System_Top.sv",
                 "kp_puf64_macro_v2.sv", "puf64_ro_bench_v2.sv",
                 "kp_ripple_counter_v2.sv", "kp_puf64_physical.sv",
                 "puf64_ro_bench.sv", "kp_ripple_counter.sv"}
    for ln in proj.splitlines():
        if "file join" not in ln:
            continue
        m = re.search(r"(\S+\.s?v)\s*\]?\s*$", ln.strip())
        base = m.group(1).split("/")[-1] if m else ""
        if base in forbidden:
            ERRORS.append(f"shell project adds forbidden source: {base}")
    for prog in (ROOT / "scripts").glob("program_*.tcl"):
        if SHELL_BIT in prog.read_text(encoding="utf-8"):
            ERRORS.append(f"{prog.name} references shell bitstream (never programmable)")

    if ERRORS:
        print("R5_SHELL_CONSTRUCTION_GATE_FAIL", file=sys.stderr)
        for e in ERRORS:
            print(f"- {e}", file=sys.stderr)
        return 1
    print("R5_SHELL_CONSTRUCTION_GATE_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
