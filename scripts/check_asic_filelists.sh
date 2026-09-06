#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
filelist_dir="$root_dir/asic/filelists"
include_files="$filelist_dir/include_files.txt"
filelists=(
  "$filelist_dir/system_asic.f"
  "$filelist_dir/mlkem_accelerator.f"
  "$filelist_dir/fips202_core.f"
)

for filelist in "${filelists[@]}"; do
  test -s "$filelist" || {
    echo "ERROR: missing or empty filelist: $filelist" >&2
    exit 1
  }

  duplicate_lines="$(awk 'NF && $1 !~ /^#/ {seen[$0]++; if (seen[$0] == 2) print}' "$filelist")"
  if [[ -n "$duplicate_lines" ]]; then
    echo "ERROR: duplicate source in ${filelist#$root_dir/}:" >&2
    echo "$duplicate_lines" >&2
    exit 1
  fi

  while IFS= read -r relative_path || [[ -n "$relative_path" ]]; do
    [[ -z "$relative_path" || "$relative_path" == \#* ]] && continue
    if [[ "$relative_path" == /* || "$relative_path" == *..* ||
          "$relative_path" == *'*'* || "$relative_path" == *'?'* ||
          "$relative_path" == *'['* ]]; then
      echo "ERROR: filelist path must be explicit and repository-relative: $relative_path" >&2
      exit 1
    fi
    case "$relative_path" in
      *.v|*.sv) ;;
      *)
        echo "ERROR: unsupported source suffix in $relative_path" >&2
        exit 1
        ;;
    esac
    test -f "$root_dir/$relative_path" || {
      echo "ERROR: source does not exist: $relative_path" >&2
      exit 1
    }
  done < "$filelist"
done

test -s "$include_files" || {
  echo "ERROR: missing or empty include dependency list: $include_files" >&2
  exit 1
}
duplicate_headers="$(awk 'NF && $1 !~ /^#/ {seen[$0]++; if (seen[$0] == 2) print}' \
  "$include_files")"
if [[ -n "$duplicate_headers" ]]; then
  echo "ERROR: duplicate header in ${include_files#$root_dir/}:" >&2
  echo "$duplicate_headers" >&2
  exit 1
fi
while IFS= read -r relative_path || [[ -n "$relative_path" ]]; do
  [[ -z "$relative_path" || "$relative_path" == \#* ]] && continue
  if [[ "$relative_path" == /* || "$relative_path" == *..* ||
        "$relative_path" == *'*'* || "$relative_path" == *'?'* ||
        "$relative_path" == *'['* ]]; then
    echo "ERROR: include path must be explicit and repository-relative: $relative_path" >&2
    exit 1
  fi
  case "$relative_path" in
    *.vh|*.svh) ;;
    *)
      echo "ERROR: unsupported header suffix in $relative_path" >&2
      exit 1
      ;;
  esac
  test -f "$root_dir/$relative_path" || {
    echo "ERROR: include dependency does not exist: $relative_path" >&2
    exit 1
  }
done < "$include_files"

system_filelist="$filelist_dir/system_asic.f"
mlkem_filelist="$filelist_dir/mlkem_accelerator.f"
for required in \
    rtl/top/Kyber_System_Asic_Top.sv \
    rtl/puf/kp_ro_cell_asic.sv \
    rtl/asic/reset_sync_n.sv \
    rtl/asic/kp_asic_ro_macro_blackbox.sv; do
  rg -q -F -x "$required" "$system_filelist" || {
    echo "ERROR: system ASIC filelist is missing $required" >&2
    exit 1
  }
done

# The full-system list must be a superset of the standalone accelerator list.
while IFS= read -r dependency || [[ -n "$dependency" ]]; do
  [[ -z "$dependency" || "$dependency" == \#* ]] && continue
  rg -q -F -x "$dependency" "$system_filelist" || {
    echo "ERROR: system ASIC filelist is missing ML-KEM source $dependency" >&2
    exit 1
  }
done < "$mlkem_filelist"

# Both ML-KEM lists instantiate the same Keccak permutation used by the FIPS
# core. fips202_sponge itself is a separate controller and is not required.
while IFS= read -r dependency || [[ -n "$dependency" ]]; do
  [[ -z "$dependency" || "$dependency" == \#* ||
     "$dependency" == "rtl/hash_core/fips202_sponge.sv" ]] && continue
  for target_list in "$system_filelist" "$mlkem_filelist"; do
    rg -q -F -x "$dependency" "$target_list" || {
      echo "ERROR: ${target_list#$root_dir/} is missing Keccak source $dependency" >&2
      exit 1
    }
  done
done < "$filelist_dir/fips202_core.f"

if ! rg -q '[.]EXPOSE_KYBER_SECRETS[(]0[)]' \
    "$root_dir/rtl/top/Kyber_System_Asic_Top.sv"; then
  echo "ERROR: ASIC top must lock Kyber seed/key readback" >&2
  exit 1
fi

if ! rg -q 'parameter[[:space:]]+integer[[:space:]]+EXPOSE_SECRETS[[:space:]]*=[[:space:]]*0' \
    "$root_dir/rtl/kyber/kyber_axi_wrapper.v"; then
  echo "ERROR: standalone ML-KEM wrapper must default to locked secret readback" >&2
  exit 1
fi

while IFS= read -r excluded || [[ -n "$excluded" ]]; do
  [[ -z "$excluded" || "$excluded" == \#* ]] && continue
  for filelist in "$system_filelist" "$filelist_dir/mlkem_accelerator.f"; do
    if rg -q -F -x "$excluded" "$filelist"; then
      echo "ERROR: excluded source entered ${filelist#$root_dir/}: $excluded" >&2
      exit 1
    fi
  done
done < "$filelist_dir/legacy_exclusions.txt"

mapfile -t system_sources < <(awk 'NF && $1 !~ /^#/ {print}' "$system_filelist")
for index in "${!system_sources[@]}"; do
  system_sources[$index]="$root_dir/${system_sources[$index]}"
done

mapfile -t header_paths < <(awk 'NF && $1 !~ /^#/ {print}' "$include_files")
declare -A header_by_name=()
scan_paths=("${system_sources[@]}")
for relative_path in "${header_paths[@]}"; do
  header_name="${relative_path##*/}"
  if [[ -n "${header_by_name[$header_name]:-}" ]]; then
    echo "ERROR: ambiguous include basename: $header_name" >&2
    exit 1
  fi
  header_by_name[$header_name]="$relative_path"
  scan_paths+=("$root_dir/$relative_path")
done

mapfile -t referenced_headers < <(
  rg --no-filename -o '`include[[:space:]]+"[^"]+"' "${scan_paths[@]}" |
    sed -E 's/^`include[[:space:]]+"([^"]+)"$/\1/' | LC_ALL=C sort -u || true
)
for header_name in "${referenced_headers[@]}"; do
  if [[ -z "${header_by_name[$header_name]:-}" ]]; then
    echo "ERROR: unlisted include dependency: $header_name" >&2
    exit 1
  fi
done

if rg -n '^[[:space:]]*(LUT6_L|CARRY4|DSP48[A-Za-z0-9_]*)[[:space:]]*(#|[A-Za-z_])' \
    "${scan_paths[@]}"; then
  echo "ERROR: FPGA primitive found in the canonical ASIC source/header set" >&2
  exit 1
fi

echo "PASS: three canonical ASIC filelists contain explicit existing sources"
echo "PASS: include dependency list closes all referenced RTL headers"
echo "PASS: system filelist contains the complete ML-KEM/Keccak source set"
echo "PASS: system filelist contains the ASIC top and RO macro boundary"
echo "PASS: ASIC top and standalone accelerator default lock seed/key readback"
echo "PASS: legacy/FPGA-only sources and primitives are excluded"
