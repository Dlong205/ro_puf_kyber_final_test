#!/usr/bin/env bash
set -euo pipefail

missing=0

for tool in yosys openroad sta klayout; do
  if command -v "$tool" >/dev/null 2>&1; then
    echo "FOUND: $tool=$(command -v "$tool")"
  else
    echo "MISSING: tool $tool" >&2
    missing=1
  fi
done

for variable in ASIC_PDK_NAME ASIC_PDK_VERSION; do
  value="${!variable:-}"
  if [[ -z "$value" || "$value" == UNSET ]]; then
    echo "MISSING: environment variable $variable" >&2
    missing=1
  else
    echo "FOUND: $variable=$value"
  fi
done

for variable in ASIC_PDK_ROOT; do
  value="${!variable:-}"
  if [[ -z "$value" || ! -d "$value" ]]; then
    echo "MISSING: directory variable $variable" >&2
    missing=1
  else
    echo "FOUND: $variable"
  fi
done

for variable in ASIC_LIBERTY_FILE ASIC_TECH_LEF ASIC_CELL_LEF; do
  value="${!variable:-}"
  if [[ -z "$value" || ! -f "$value" ]]; then
    echo "MISSING: file variable $variable" >&2
    missing=1
  else
    echo "FOUND: $variable"
  fi
done

if [[ $missing -ne 0 ]]; then
  echo "NO-GO: ASIC backend inputs are incomplete" >&2
  exit 2
fi

echo "PASS: minimum open-source digital backend tools and PDK inputs are present"
echo "INFO: RO macro, memory/pad/DFT views and MMMC still require separate gates"
