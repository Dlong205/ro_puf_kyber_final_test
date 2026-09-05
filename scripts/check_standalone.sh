#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

required=(
  rtl/top/Kyber_System_Top.sv
  rtl/top/Puf_Characterization_Top.sv
  rtl/top/puf_characterization_uart.sv
  rtl/puf/kp_puf_top.sv
  rtl/puf/kp_ro_cell.sv
  rtl/puf/kp_ro_cell_model.sv
  rtl/puf/kp_ro_cell_xilinx.sv
  rtl/puf/kp_ro_cell_asic.sv
  rtl/asic/kp_asic_ro_macro_blackbox.sv
  rtl/fuzzy_extractor/fuzzy_extractor.sv
  rtl/hash_core/fips202_sponge.sv
  rtl/top/kdf_keccak.sv
  rtl/kyber/kyber_axi_wrapper.v
  rtl/kyber/ref/Kyber_Server.v
  rtl/kyber/ref/Kyber_Client.v
  rtl/soc/riscv_soc.sv
  firmware/main.c
  firmware/firmware.hex
  constraints/kp_zynq_7020.xdc
  constraints/ro_placement_rc1_zynq7020.xdc
  host/puf_raw_characterize.py
  scripts/create_puf_characterization_project.tcl
  scripts/build_puf_characterization.tcl
  scripts/program_puf_characterization.tcl
  sim/system/system_uart_main.cpp
  docs/board_pin_mapping.xls
)

for relative_path in "${required[@]}"; do
  test -f "$root_dir/$relative_path" || {
    echo "MISSING: $relative_path" >&2
    exit 1
  }
done

if find "$root_dir" -type l -print -quit | grep -q .; then
  echo "ERROR: standalone folder contains symbolic links" >&2
  exit 1
fi

if find "$root_dir" -type f -name '*.xci' -print -quit | grep -q .; then
  echo "ERROR: generated Xilinx IP (.xci) found" >&2
  exit 1
fi

if grep -R -n -F '/home/donglong/Documents/Duy_prj/KECCAK_OPTIMIZE_POWER/OPTIMIZE_POWER' \
    "$root_dir" \
    --exclude-dir=.git \
    --exclude-dir=.Xil \
    --exclude-dir=build \
    --exclude-dir=release \
    --exclude-dir=reports \
    --exclude-dir=obj_dir \
    --exclude-dir=obj_dir_axi \
    --exclude-dir=__pycache__ \
    --exclude-dir=rtl_tcq0 \
    --exclude='*.jou' \
    --exclude='*.log' \
    --exclude='*.pb' \
    --exclude='*.wdb' \
    --exclude='*.vcd' \
    --exclude=check_standalone.sh; then
  echo "ERROR: dependency on the original project path found" >&2
  exit 1
fi

echo "PASS: required files are present"
echo "PASS: no symbolic links"
echo "PASS: no XCI generated IP"
echo "PASS: no dependency on the original project path"
echo "INFO: generated Vivado reports are excluded because their headers record the generation path"
