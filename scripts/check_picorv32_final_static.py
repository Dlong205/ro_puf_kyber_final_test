#!/usr/bin/env python3
"""Fail-closed static gate for the PicoRV32 operational-final profile."""

from pathlib import Path
import hashlib
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
TOP = ROOT / "rtl/top/Edge_Puf64_Zynq_PicoRV32_Final_100MHz_Top.sv"
WRAPPER = ROOT / "rtl/top/edge_puf64_operational_uart_picorv32.sv"
SUPERVISOR = ROOT / "rtl/soc/puf64_picorv32_supervisor.sv"
FW_SRC = ROOT / "firmware/puf64_supervisor.c"
FW_HEX = ROOT / "firmware/puf64_supervisor.hex"
PROJECT = ROOT / "scripts/create_puf64_operational_final_project.tcl"
PROGRAM = ROOT / "scripts/program_puf64_picorv32_final.tcl"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    errors: list[str] = []
    for path in (TOP, WRAPPER, SUPERVISOR, FW_SRC, FW_HEX, PROJECT, PROGRAM):
        if not path.is_file():
            errors.append(f"missing {path.relative_to(ROOT)}")
    if errors:
        return finish(errors)

    top = TOP.read_text()
    for token in (
        "module Edge_Puf64_Zynq_PicoRV32_Final_100MHz_Top",
        "localparam bit ALLOW_ENROLL         = 1'b0;",
        "localparam bit LEGACY_HELPER_ENABLE = 1'b0;",
        "localparam bit DIAGNOSTIC_ANCHOR    = 1'b0;",
        "edge_puf64_operational_uart_picorv32",
        ".ROM_VALID(1'b1)",
        ".provision(1'b0)",
    ):
        if token not in top:
            errors.append(f"top missing {token}")
    match = re.search(r"DEVICE_TRUSTED_KCV\s*=\s*\n?\s*224'h([0-9a-fA-F]{56})", top)
    if not match or int(match.group(1), 16) == 0:
        errors.append("trusted anchor missing or zero")

    wrapper = WRAPPER.read_text()
    for token in ("puf64_picorv32_supervisor", ".start(authorized_start)",
                  ".transport_start(transport_start)",
                  ".LEGACY_HELPER_ENABLE(1'b0)", ".ALLOW_ENROLL(1'b0)",
                  ".HREC_PROFILE(8'h01)", ".HREC_FE_PARAM(8'h01)",
                  ".HREC_MAPPING_LEN_BYTES(8'd33)"):
        if token not in wrapper:
            errors.append(f"wrapper missing {token}")
    # Mapping tag/generation flow as top-level parameters (gen1 defaults);
    # literals here would silently pin gen1 and break gen2 builds.
    for token in (".HREC_MAPPING_TAG(HREC_MAPPING_TAG)",
                  ".HREC_GENERATION(HREC_GENERATION)",
                  "parameter [15:0] HREC_MAPPING_TAG = 16'h81B5",
                  "parameter [7:0]  HREC_GENERATION = 8'h01"):
        if token not in wrapper:
            errors.append(f"wrapper missing {token}")
    for token in ("parameter [15:0] HREC_MAPPING_TAG = 16'h81B5",
                  "parameter [7:0]  HREC_GENERATION = 8'h01"):
        if token not in top:
            errors.append(f"top missing default {token}")

    supervisor = SUPERVISOR.read_text()
    ports = supervisor.split(");", 1)[0]
    for forbidden in ("puf_response", "fe_key", "kcv_out", "kdf_seed",
                      "shared_secret", "stream_in_data", "stream_out_data"):
        if forbidden in ports:
            errors.append(f"secret/data port exposed to CPU supervisor: {forbidden}")
    for token in ("picorv32 #(", ".ENABLE_MUL(0)", ".ENABLE_DIV(0)",
                  ".MEM_WORDS(1024)", "request_pending && command_ok",
                  "trusted_kcv_valid && mmcm_locked && core_idle"):
        if token not in supervisor:
            errors.append(f"supervisor missing {token}")

    project = PROJECT.read_text()
    for token in ("PUF64_PICORV32_FINAL", "puf64_picorv32_final_zynq7020",
                  "Edge_Puf64_Zynq_PicoRV32_Final_100MHz_Top",
                  "puf64_supervisor.hex"):
        if token not in project:
            errors.append(f"project profile missing {token}")
    # set_property generic replaces the whole list: more than one call would
    # silently drop DIAGNOSTIC_FAILURE_CODES (seen as release 0x03 once).
    generic_calls = [ln for ln in project.splitlines()
                     if "set_property generic" in ln
                     and not ln.strip().startswith("#")]
    if len(generic_calls) != 1:
        errors.append("project must set top generics in exactly one call")

    run = subprocess.run(["make", "-C", "firmware", "supervisor"], cwd=ROOT,
                         text=True, capture_output=True)
    if run.returncode != 0:
        errors.append("supervisor firmware rebuild failed")
    words = [line for line in FW_HEX.read_text().splitlines() if line.strip()]
    if not words or len(words) > 1024 or any(not re.fullmatch(r"[0-9a-fA-F]{8}", w)
                                             for w in words):
        errors.append("supervisor firmware hex malformed or oversized")

    program = PROGRAM.read_text()
    for token in ("expected-bitstream-sha256", "ro_sha256_file $bit_file",
                  "Expected exactly one JTAG target",
                  "Expected exactly one XC7Z020",
                  "PICORV32_FINAL_PROGRAM_PASS"):
        if token not in program:
            errors.append(f"program gate missing {token}")

    if errors:
        return finish(errors)
    print("PUF64_PICORV32_FINAL_STATIC_PASS")
    print(f"firmware_words={len(words)} firmware_sha256={sha256(FW_HEX)}")
    print(f"top_sha256={sha256(TOP)} supervisor_sha256={sha256(SUPERVISOR)}")
    return 0


def finish(errors: list[str]) -> int:
    print("PUF64_PICORV32_FINAL_STATIC_FAIL", file=sys.stderr)
    for error in errors:
        print(f"- {error}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
