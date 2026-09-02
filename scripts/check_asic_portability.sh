#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
verilator_bin="${VERILATOR:-verilator}"
elab_dir="$(mktemp -d)"
trap 'rm -rf "$elab_dir"' EXIT

require_only_file() {
  local pattern="$1"
  local expected="$2"
  local label="$3"
  local -a matches=()

  mapfile -t matches < <(rg -l "$pattern" "$root_dir/rtl" \
    --glob '*.v' --glob '*.sv' || true)
  if [[ ${#matches[@]} -ne 1 || "${matches[0]}" != "$root_dir/$expected" ]]; then
    echo "ERROR: $label must exist only in $expected" >&2
    printf 'Found: %s\n' "${matches[@]:-<none>}" >&2
    exit 1
  fi
  echo "PASS: $label isolated in $expected"
}

require_only_file '\bLUT6_L\b' 'rtl/puf/kp_ro_cell_xilinx.sv' 'LUT6_L'
require_only_file '\bCARRY4\b' 'rtl/fuzzy_extractor/compare_cla_xilinx.v' 'CARRY4'

if rg -n '^[[:space:]]*DSP48[A-Za-z0-9_]*[[:space:]]*(#|[A-Za-z_])' \
    "$root_dir/rtl" --glob '*.v' --glob '*.sv'; then
  echo "ERROR: direct DSP48 primitive instantiation found" >&2
  exit 1
fi
echo "PASS: no direct DSP48 primitive instantiation"

if rg -n '\bmult_gen_0\b' "$root_dir/rtl" --glob '*.v' --glob '*.sv'; then
  echo "ERROR: legacy Xilinx-style multiplier wrapper name remains" >&2
  exit 1
fi
echo "PASS: NTT multiplier uses a target-neutral module name"

make -C "$root_dir/sim/fuzzy_extractor" -j1 rtl_tcq0/.stamp >/dev/null
fe_dir="$root_dir/sim/fuzzy_extractor/rtl_tcq0"

common_sources=(
  "$root_dir/rtl/common/generic_blk_mem_wrapper.sv"
  "$root_dir/rtl/common/generic_c_shift_ram_wrapper.sv"
  "$root_dir/rtl/common/generic_dist_mem_wrapper.sv"
  "$root_dir/rtl/common/generic_bram.sv"
  "$root_dir/rtl/common/generic_mult.sv"
  "$root_dir/rtl/common/generic_fifo.sv"
)

hash_sources=(
  "$root_dir/rtl/hash_core/ALGORITHM.v"
  "$root_dir/rtl/hash_core/THETA1.v"
  "$root_dir/rtl/hash_core/THETA2_RHO_PI.v"
  "$root_dir/rtl/hash_core/CHI1.v"
  "$root_dir/rtl/hash_core/CHI2.v"
  "$root_dir/rtl/hash_core/Chi_3_Iota.v"
  "$root_dir/rtl/hash_core/IOTA.v"
  "$root_dir/rtl/hash_core/RC.v"
  "$root_dir/rtl/hash_core/ADDER.v"
)

kyber_sources=(
  "$root_dir/rtl/kyber/ref/Kyber_Server.v"
  "$root_dir/rtl/kyber/ref/Kyber_Client.v"
  "$root_dir/rtl/kyber/ref/NTT_core_Server.v"
  "$root_dir/rtl/kyber/ref/NTT_core_Client.v"
  "$root_dir/rtl/kyber/ref/butterfly_Server.v"
  "$root_dir/rtl/kyber/ref/butterfly_Client.v"
  "$root_dir/rtl/kyber/ref/hash_core_Server.v"
  "$root_dir/rtl/kyber/ref/hash_core_Client.v"
  "$root_dir/rtl/kyber/ref/sha3_shake_core.v"
  "$root_dir/rtl/kyber/ref/keccak_f1600_server.v"
  "$root_dir/rtl/kyber/ref/keccak_f1600_client.v"
  "$root_dir/rtl/kyber/ref/encode_Server.v"
  "$root_dir/rtl/kyber/ref/encode_Client.v"
  "$root_dir/rtl/kyber/ref/decode_Server.v"
  "$root_dir/rtl/kyber/ref/decode_Client.v"
  "$root_dir/rtl/kyber/ref/decode_keccak.v"
  "$root_dir/rtl/kyber/ref/fifo_wrappers.v"
  "$root_dir/rtl/kyber/ref/LUT.v"
  "$root_dir/rtl/kyber/ref/mux4to2.v"
  "$root_dir/rtl/kyber/ref/pattern.v"
  "$root_dir/rtl/kyber/ref/reduc.v"
  "$root_dir/rtl/kyber/kyber_axi_wrapper.v"
)

fe_sources=(
  "$fe_dir/bch_blank_ecc.v"
  "$fe_dir/bch_chien.v"
  "$fe_dir/bch_encode.v"
  "$fe_dir/bch_error_tmec.v"
  "$fe_dir/bch_math.v"
  "$fe_dir/bch_sigma_bma_serial.v"
  "$fe_dir/bch_syndrome.v"
  "$fe_dir/bch_syndrome_method1.v"
  "$fe_dir/bch_syndrome_method2.v"
  "$fe_dir/buff.v"
  "$fe_dir/compare_cla.v"
  "$fe_dir/fifo.v"
  "$fe_dir/matrix.v"
  "$fe_dir/util.v"
  "$fe_dir/xilinx_decoder.v"
  "$fe_dir/xilinx_encode.v"
  "$fe_dir/fuzzy_extractor.sv"
)

puf_sources=(
  "$root_dir/rtl/puf/kp_ro_cell.sv"
  "$root_dir/rtl/puf/kp_ro_cell_asic.sv"
  "$root_dir/rtl/asic/kp_asic_ro_macro_blackbox.sv"
  "$root_dir/rtl/puf/kp_puf_cells.sv"
  "$root_dir/rtl/puf/kp_puf_control.sv"
  "$root_dir/rtl/puf/kp_puf_top.sv"
  "$root_dir/rtl/puf/uart_rx.v"
  "$root_dir/rtl/puf/uart_tx.v"
)

soc_sources=(
  "$root_dir/rtl/soc/picorv32.v"
  "$root_dir/rtl/soc/soc_bram.v"
  "$root_dir/rtl/soc/soc_peripherals.sv"
  "$root_dir/rtl/soc/riscv_soc.sv"
  "$root_dir/rtl/top/kdf_keccak.sv"
  "$root_dir/rtl/top/Kyber_System_Top.sv"
)

"$verilator_bin" --cc --timing --top-module Kyber_System_Top \
  --Mdir "$elab_dir" -DKP_TARGET_ASIC \
  -I"$root_dir/rtl/kyber/ref" -I"$root_dir/rtl/common" \
  -I"$root_dir/rtl/hash_core" -I"$fe_dir" -I"$root_dir/rtl/puf" \
  -Wno-WIDTH -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL \
  -Wno-CASEINCOMPLETE -Wno-MULTITOP -Wno-MULTIDRIVEN \
  -Wno-UNSIGNED -Wno-EOFNEWLINE -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND \
  -Wno-MODDUP -Wno-TIMESCALEMOD -Wno-BLKANDNBLK -Wno-IMPLICIT \
  -Wno-IMPLICITSTATIC -Wno-CASEOVERLAP -Wno-CASEX -Wno-fatal \
  "${common_sources[@]}" "${hash_sources[@]}" "${kyber_sources[@]}" \
  "${fe_sources[@]}" "${puf_sources[@]}" "${soc_sources[@]}"

echo "PASS: full Kyber_System_Top elaborates with KP_TARGET_ASIC"
echo "PASS: ASIC source list excludes LUT6_L, CARRY4 and direct DSP48 primitives"
