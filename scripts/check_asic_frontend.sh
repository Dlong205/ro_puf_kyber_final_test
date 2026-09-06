#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
verilator_bin="${VERILATOR:-verilator}"
build_dir="${ASIC_FRONTEND_BUILD_DIR:-$root_dir/build/asic_frontend}"
lint_dir="$build_dir/verilator"
log_file="$lint_dir/verilator.log"
summary_file="$lint_dir/warning_summary.txt"
dependency_file="$lint_dir/obj_dir/VKyber_System_Asic_Top__verFiles.dat"

"$root_dir/scripts/check_asic_filelists.sh"
command -v "$verilator_bin" >/dev/null 2>&1 || {
  echo "ERROR: Verilator is not available: $verilator_bin" >&2
  exit 1
}

# The upstream BCH sources contain simulation-only #TCQ delays.  Reuse the
# existing deterministic TCQ=0 generated copy for Verilator elaboration; the
# canonical synthesis filelist continues to name the original RTL sources.
make -C "$root_dir/sim/fuzzy_extractor" -j1 rtl_tcq0/.stamp >/dev/null
fe_dir="$root_dir/sim/fuzzy_extractor/rtl_tcq0"
mkdir -p "$lint_dir"

# The Verilator-specific TCQ=0 copy must not silently change any include file.
while IFS= read -r header_path || [[ -n "$header_path" ]]; do
  [[ -z "$header_path" || "$header_path" == \#* ]] && continue
  if [[ "$header_path" == rtl/fuzzy_extractor/* ]]; then
    cmp -s "$root_dir/$header_path" "$fe_dir/${header_path##*/}" || {
      echo "ERROR: generated BCH header differs from canonical $header_path" >&2
      exit 1
    }
  fi
done < "$root_dir/asic/filelists/include_files.txt"

mapfile -t sources < <(awk 'NF && $1 !~ /^#/ {print}' \
  "$root_dir/asic/filelists/system_asic.f")
for index in "${!sources[@]}"; do
  if [[ "${sources[$index]}" == rtl/fuzzy_extractor/* ]]; then
    sources[$index]="$fe_dir/${sources[$index]##*/}"
  else
    sources[$index]="$root_dir/${sources[$index]}"
  fi
done

set +e
"$verilator_bin" --cc --no-skip-identical --timing \
  --top-module Kyber_System_Asic_Top \
  --Mdir "$lint_dir/obj_dir" -DKP_TARGET_ASIC \
  -I"$root_dir/rtl/kyber/ref" \
  -I"$root_dir/rtl/common" \
  -I"$root_dir/rtl/hash_core" \
  -I"$fe_dir" \
  -I"$root_dir/rtl/puf" \
  -Wall -Wno-fatal "${sources[@]}" >"$log_file" 2>&1
verilator_status=$?
set -e

{
  echo "tool=$($verilator_bin --version)"
  echo "top=Kyber_System_Asic_Top"
  echo "define=KP_TARGET_ASIC"
  echo "source_filelist=asic/filelists/system_asic.f"
  rg '^%Warning-[A-Z0-9_]+' "$log_file" |
    sed -E 's/^%Warning-([A-Z0-9_]+).*/\1/' |
    sort | uniq -c | sort -nr || true
} > "$summary_file"

if [[ $verilator_status -ne 0 ]]; then
  rg -n '^%Error' "$log_file" >&2 || true
  echo "ERROR: ASIC top elaboration failed; see $log_file" >&2
  exit "$verilator_status"
fi

test -s "$dependency_file" || {
  echo "ERROR: Verilator did not emit a dependency record: $dependency_file" >&2
  exit 1
}

# Verilator can auto-load a module by filename from -I. Compare its dependency
# record with the explicit compile list so such a hidden source cannot make the
# canonical filelist appear complete.
if ! diff -u \
    <(printf '%s\n' "${sources[@]}" | LC_ALL=C sort -u) \
    <(awk -F'"' '$1 ~ /^S[[:space:]]/ {print $(NF-1)}' "$dependency_file" |
      awk -v prefix="$root_dir/" 'index($0, prefix) == 1 && $0 ~ /[.]s?v$/' |
      LC_ALL=C sort -u); then
  echo "ERROR: implicit or missing RTL translation unit in Verilator dependency closure" >&2
  exit 1
fi

mapfile -t expected_headers < <(awk 'NF && $1 !~ /^#/ {print}' \
  "$root_dir/asic/filelists/include_files.txt")
for index in "${!expected_headers[@]}"; do
  if [[ "${expected_headers[$index]}" == rtl/fuzzy_extractor/* ]]; then
    expected_headers[$index]="$fe_dir/${expected_headers[$index]##*/}"
  else
    expected_headers[$index]="$root_dir/${expected_headers[$index]}"
  fi
done
if ! diff -u \
    <(printf '%s\n' "${expected_headers[@]}" | LC_ALL=C sort -u) \
    <(awk -F'"' '$1 ~ /^S[[:space:]]/ {print $(NF-1)}' "$dependency_file" |
      awk -v prefix="$root_dir/" 'index($0, prefix) == 1 && $0 ~ /[.]s?vh$/' |
      LC_ALL=C sort -u); then
  echo "ERROR: implicit or missing RTL header in Verilator dependency closure" >&2
  exit 1
fi

if rg -n '^%Warning-(MULTIDRIVEN|IMPLICIT|LATCH|UNOPTFLAT)' "$log_file"; then
  echo "ERROR: unwaived structural lint finding; see $log_file" >&2
  exit 1
fi

unexpected_undriven="$(rg '^%Warning-UNDRIVEN' "$log_file" |
  rg -v 'rtl/asic/kp_asic_ro_macro_blackbox[.]sv' || true)"
if [[ -n "$unexpected_undriven" ]]; then
  echo "$unexpected_undriven" >&2
  echo "ERROR: undriven signal outside the intentional RO macro black-box" >&2
  exit 1
fi

warning_count="$(rg -c '^%Warning' "$log_file" || true)"
echo "PASS: Kyber_System_Asic_Top elaborates from the canonical filelist"
echo "PASS: Verilator used no implicit RTL source/header outside the locked lists"
echo "PASS: no MULTIDRIVEN, IMPLICIT, LATCH or UNOPTFLAT finding"
echo "INFO: $warning_count non-gating lint warnings remain; see $summary_file"
echo "INFO: the intentional RO macro black-box remains undriven until PDK integration"
