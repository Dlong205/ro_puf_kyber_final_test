#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
run_a="${1:-locked_a}"
run_b="${2:-locked_b}"

valid_run_id='^[A-Za-z0-9_-]+$'
[[ "$run_a" =~ $valid_run_id ]] || {
  echo "ERROR: invalid run id: $run_a" >&2
  exit 2
}
[[ "$run_b" =~ $valid_run_id ]] || {
  echo "ERROR: invalid run id: $run_b" >&2
  exit 2
}

golden="$root_dir/constraints/ro_physical_fingerprint_rc1_zynq7020.tsv"
fingerprint_a="$root_dir/build/soc_repro/$run_a/reports/ro_physical_fingerprint.tsv"
fingerprint_b="$root_dir/build/soc_repro/$run_b/reports/ro_physical_fingerprint.tsv"

for run_id in "$run_a" "$run_b"; do
  run_dir="$root_dir/build/soc_repro/$run_id"
  bitstream="$run_dir/kyber_ro_puf_${run_id}.runs/impl_1/Kyber_System_Top.bit"
  checkpoint="$run_dir/kyber_ro_puf_${run_id}.runs/impl_1/Kyber_System_Top_routed.dcp"
  timing="$run_dir/reports/post_route_timing.rpt"
  drc="$run_dir/reports/post_route_drc.rpt"
  fingerprint="$run_dir/reports/ro_physical_fingerprint.tsv"

  for artifact in "$bitstream" "$checkpoint" "$timing" "$drc" "$fingerprint"; do
    [[ -s "$artifact" ]] || {
      echo "ERROR: missing artifact for $run_id: $artifact" >&2
      exit 1
    }
  done

  grep -q "All user specified timing constraints are met" "$timing" || {
    echo "ERROR: timing failed for $run_id" >&2
    exit 1
  }
  grep -q "Design State : Fully Routed" "$drc" || {
    echo "ERROR: design is not fully routed for $run_id" >&2
    exit 1
  }
  if grep -Eq '^\|[^|]*\|[[:space:]]*(Error|Critical Warning)[[:space:]]*\|' "$drc"; then
    echo "ERROR: DRC has an error or critical warning for $run_id" >&2
    exit 1
  fi
  cmp -s "$golden" "$fingerprint" || {
    echo "ERROR: RO fingerprint differs from golden for $run_id" >&2
    exit 1
  }

  echo "PASS: $run_id is fully routed, timing-clean, DRC-clean and matches the RO fingerprint"
  sha256sum "$bitstream" "$checkpoint" "$fingerprint"
done

cmp -s "$fingerprint_a" "$fingerprint_b" || {
  echo "ERROR: RO physical fingerprints differ between $run_a and $run_b" >&2
  exit 1
}

echo "PASS: $run_a and $run_b reproduce the same 136-cell/128-net RO physical implementation"
