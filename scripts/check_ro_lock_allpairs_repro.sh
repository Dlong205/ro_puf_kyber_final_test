#!/usr/bin/env bash
set -euo pipefail

# Verify that a rebuilt all-pairs characterization image reproduces the
# accepted RO physical lock and that its bitstream/checkpoint are anchored.
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

golden_fingerprint="$root_dir/constraints/ro_physical_fingerprint_allpairs_zynq7020.tsv"
anchor="$root_dir/constraints/ro_physical_lock_allpairs_zynq7020.expected"
run_dir="$root_dir/build/puf_allpairs_characterization"
bitstream="$run_dir/puf_allpairs_zynq7020.runs/impl_1/Puf_AllPairs_Characterization_Top.bit"
checkpoint="$run_dir/puf_allpairs_zynq7020.runs/impl_1/Puf_AllPairs_Characterization_Top_routed.dcp"
timing="$root_dir/reports/puf_allpairs_characterization/post_route_timing.rpt"
drc="$root_dir/reports/puf_allpairs_characterization/post_route_drc.rpt"
fingerprint="$root_dir/reports/puf_allpairs_characterization/ro_physical_fingerprint.tsv"
metadata="$root_dir/reports/puf_allpairs_characterization/build_metadata.tsv"

for artifact in "$anchor" "$golden_fingerprint" "$bitstream" "$checkpoint" \
                "$timing" "$drc" "$fingerprint" "$metadata"; do
  [[ -s "$artifact" ]] || {
    echo "ERROR: missing artifact: $artifact" >&2
    exit 1
  }
done

grep -q "All user specified timing constraints are met" "$timing" || {
  echo "ERROR: timing failed for all-pairs image" >&2
  exit 1
}
grep -q "Design State : Fully Routed" "$drc" || {
  echo "ERROR: design is not fully routed" >&2
  exit 1
}
if grep -Eq '^\|[^|]*\|[[:space:]]*(Error|Critical Warning)[[:space:]]*\|' "$drc"; then
  echo "ERROR: DRC has an error or critical warning" >&2
  exit 1
fi

cmp -s "$golden_fingerprint" "$fingerprint" || {
  echo "ERROR: all-pairs RO fingerprint differs from the accepted baseline" >&2
  exit 1
}

expected_dcp="$(awk '$1 == "DCP_SHA" {print $2}' "$anchor")"
actual_dcp="$(awk '$1 == "routed_dcp_sha256" {print $2}' "$metadata")"
[[ -n "$expected_dcp" && "$expected_dcp" == "$actual_dcp" ]] || {
  echo "ERROR: routed DCP does not match the accepted baseline anchor" >&2
  exit 1
}

grep -q "fingerprint_status	OK" "$metadata" && grep -q "lock_in_project	true" "$metadata" || {
  echo "ERROR: build metadata does not record an applied verified lock" >&2
  exit 1
}

echo "PASS: all-pairs image is fully routed, timing-clean, DRC-clean and"
echo "      reproduces the accepted 128-cell RO physical fingerprint."
sha256sum "$bitstream" "$checkpoint" "$fingerprint" "$metadata"