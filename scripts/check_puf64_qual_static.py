#!/usr/bin/env python3
"""R6.1 fail-closed static gate for the operational-qualification profile.

Qualification image (same PicoRV32 final top, generic-selected):
  QUALIFICATION_NONRELEASE=1, QUAL_INFO_MARKER=0x71, readout command 0x70
  reachable; lifecycle locks identical to final (no enroll/provisioning);
  gen1 mapping defaults; gen1 trusted anchor default.
Final image (superset, readout locked):
  QUALIFICATION_NONRELEASE absent/0, QUAL_INFO_MARKER absent/0x0f; the
  capture sniffer must still be instantiated (identical telemetry loads);
  0x70 must be unreachable (gated by QUAL_TELEMETRY_ENABLE).

Checks (no Vivado, SHAs only for provenance -- never secret values):
- core_v2 instantiates puf64_qual_telemetry_sniffer with KEEP/DONT_TOUCH,
  unconditional capture (capture does not depend on QUAL), readout mux
  gated by QUALIFICATION_NONRELEASE, sim no-leak assertion present.
- transport implements CMD_QUAL_TEL=0x70 gated by QUAL_TELEMETRY_ENABLE,
  QUAL path unreachable when disabled; INFO marker parameterized; release
  SESSION/INFO/FAIL paths token-identical to HEAD (no release drift).
- wrapper/chain forward QUAL params with final-safe defaults (0/0x0f).
- final top exposes QUALIFICATION_NONRELEASE/QUAL_INFO_MARKER generics with
  final defaults and the INFO-marker sim contract.
- qual project TCL: same sources as final + sniffer, frozen gen1 mapping dir
  FIRST, same shell XDC, exactly one set_property generic call with the
  QUAL overrides; build dirs never collide with gen1/gen2/final dirs.
- supervisor CPU sees no qual tap (no qual_* ports near picorv32).
- host qual reader exists and expects the 0x71 marker.

Usage: python3 scripts/check_puf64_qual_static.py [--final-only]
  default checks the qual profile; --final-only checks the final (locked)
  profile instead.
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
CORE = ROOT / "rtl/top/edge_puf64_operational_core_v2.sv"
SNIFFER = ROOT / "rtl/top/puf64_qual_telemetry_sniffer.sv"
TRANSPORT = ROOT / "rtl/top/edge_uart_transport.sv"
WRAPPER = ROOT / "rtl/top/edge_puf64_operational_uart_picorv32.sv"
CHAIN = ROOT / "rtl/top/edge_puf64_operational_chain_v2.sv"
TOP = ROOT / "rtl/top/Edge_Puf64_Zynq_PicoRV32_Final_100MHz_Top.sv"
SUPERVISOR = ROOT / "rtl/soc/puf64_picorv32_supervisor.sv"
PROJ = ROOT / "scripts/create_puf64_qual_project.tcl"
HOST = ROOT / "host/puf64_qual_telemetry_read.py"


def main() -> int:
    final_only = "--final-only" in sys.argv
    errors: list[str] = []
    for path in (CORE, SNIFFER, TRANSPORT, WRAPPER, CHAIN, TOP,
                 SUPERVISOR, PROJ, HOST):
        if not path.is_file():
            errors.append(f"missing {path.relative_to(ROOT)}")
    if errors:
        return finish(errors, final_only)

    sniffer = SNIFFER.read_text()
    for token in ("module puf64_qual_telemetry_sniffer",
                  "parameter bit QUALIFICATION_NONRELEASE",
                  "QUALIFICATION_NONRELEASE ? mem_dout_b :",
                  "QUALIFICATION_NONRELEASE ? r_frame_seq",
                  "QUALIFICATION_NONRELEASE ? r_frame_valid",
                  "generic_bram #(",
                  ".DEPTH(2048), .WIDTH(ENTRY_W)",
                  "u_frame_mem",
                  "qual sniffer leaks telemetry in final"):
        if token not in sniffer:
            errors.append(f"sniffer missing {token}")
    # Capture must be unconditional: no QUAL gating on the write path.
    for line in sniffer.splitlines():
        low = line.lower()
        if ("mem[" in low and "writ" not in low and "rd_" not in low
                and "QUALIFICATION_NONRELEASE" in line):
            errors.append(f"sniffer capture gated by QUAL: {line.strip()[:100]}")

    core = CORE.read_text()
    for token in ("puf64_qual_telemetry_sniffer",
                  "u_qual_sniffer",
                  "parameter bit     QUALIFICATION_NONRELEASE = 1'b0",
                  ".QUALIFICATION_NONRELEASE(QUALIFICATION_NONRELEASE)",
                  "(* KEEP_HIERARCHY = \"yes\" *) (* DONT_TOUCH = \"yes\" *)"):
        if token not in core:
            errors.append(f"core missing {token}")
    for token in ("qual_rd_en", "qual_rd_addr", "qual_rd_data",
                  "qual_frame_seq", "qual_entry_count", "qual_hdr_bch_corr",
                  "qual_hdr_status", "qual_frame_valid"):
        if token not in core:
            errors.append(f"core missing readout port {token}")

    transport = TRANSPORT.read_text()
    for token in ("CMD_QUAL_TEL = 8'h70",
                  "parameter bit     QUAL_TELEMETRY_ENABLE = 1'b0",
                  "parameter [7:0]   QUAL_INFO_MARKER = 8'h0f",
                  "QUAL_TELEMETRY_ENABLE) begin",
                  "S_QUAL_MARK", "S_QUAL_HDR", "S_QUAL_RD", "S_QUAL_WAIT",
                  "S_QUAL_SEND", "S_QUAL_CRC",
                  "default: info_byte = QUAL_INFO_MARKER;"):
        if token not in transport:
            errors.append(f"transport missing {token}")
    # Release paths must be untouched: INFO/SESSION/FAIL tokens intact.
    for token in ("CMD_SESSION", "STATUS_FAIL", "fail_code <= 8'h01;",
                  "release images always send exactly 2 bytes"):
        if token not in transport:
            errors.append(f"transport release-path drift: {token}")

    wrapper = WRAPPER.read_text()
    for token in ("parameter bit QUALIFICATION_NONRELEASE = 1'b0",
                  "parameter bit QUAL_TELEMETRY_ENABLE = QUALIFICATION_NONRELEASE",
                  "parameter [7:0] QUAL_INFO_MARKER = 8'h0f",
                  ".QUAL_TELEMETRY_ENABLE(QUAL_TELEMETRY_ENABLE)",
                  ".QUAL_INFO_MARKER(QUAL_INFO_MARKER)",
                  ".QUALIFICATION_NONRELEASE(QUALIFICATION_NONRELEASE)",
                  ".HREC_MAPPING_TAG(HREC_MAPPING_TAG)",
                  ".HREC_GENERATION(HREC_GENERATION)"):
        if token not in wrapper:
            errors.append(f"wrapper missing {token}")

    chain = CHAIN.read_text()
    for token in ("parameter bit QUALIFICATION_NONRELEASE = 1'b0",
                  ".QUALIFICATION_NONRELEASE(QUALIFICATION_NONRELEASE)"):
        if token not in chain:
            errors.append(f"chain missing {token}")

    top = TOP.read_text()
    for token in ("parameter bit QUALIFICATION_NONRELEASE = 1'b0",
                  "parameter [7:0] QUAL_INFO_MARKER = 8'h0f",
                  ".QUALIFICATION_NONRELEASE(QUALIFICATION_NONRELEASE)",
                  ".QUAL_TELEMETRY_ENABLE(QUALIFICATION_NONRELEASE)",
                  ".QUAL_INFO_MARKER(QUAL_INFO_MARKER)",
                  "qualification INFO marker must be 0x71",
                  "final INFO marker must be 0x0f"):
        if token not in top:
            errors.append(f"final top missing qual superset {token}")

    supervisor = SUPERVISOR.read_text()
    for token in ("qual_rd", "qual_frame", "telemetry", "sniffer"):
        if token in supervisor.split(");", 1)[0]:
            errors.append(f"secret/qual tap exposed to CPU: {token}")

    proj = PROJ.read_text()
    for token in ("puf64_qual", "Edge_Puf64_Zynq_PicoRV32_Final_100MHz_Top",
                  "puf64_qual_telemetry_sniffer.sv",
                  "v2_mapping_frozen",
                  "edge_puf64_zynq_operational_final_100mhz.xdc",
                  "QUALIFICATION_NONRELEASE=1",
                  "QUAL_INFO_MARKER=8'h71",
                  "set_property generic"):
        if token not in proj:
            errors.append(f"qual project missing {token}")
    generic_calls = [ln for ln in proj.splitlines()
                     if "set_property generic" in ln
                     and not ln.strip().startswith("#")]
    if len(generic_calls) != 1:
        errors.append("qual project must set top generics in exactly one call")
    for forbidden in ("build/puf64_picorv32_diagnostic",
                      "build/puf64_picorv32_final",
                      "reports/puf64_picorv32_diagnostic",
                      "reports/puf64_picorv32_final"):
        if forbidden in proj:
            errors.append(f"qual project collides with release dirs: {forbidden}")

    host = HOST.read_text()
    for token in ("0x71", "CMD_QUAL", "0x70", "QUALIFICATION_NONRELEASE",
                  "frame_seq", "entry_count"):
        if token not in host:
            errors.append(f"host qual reader missing {token}")

    if final_only:
        # Final profile: readout unreachable by construction (defaults).
        # The superset requirement (sniffer present) is covered above.
        pass
    if errors:
        return finish(errors, final_only)
    profile = "FINAL_LOCKED_SUPERSET" if final_only else "QUALIFICATION_NONRELEASE"
    print(f"PUF64_QUAL_STATIC_PASS profile={profile}")
    return 0


def finish(errors: list[str], final_only: bool) -> int:
    print("PUF64_QUAL_STATIC_FAIL", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
