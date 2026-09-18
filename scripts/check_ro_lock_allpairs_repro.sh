#!/usr/bin/env bash
set -euo pipefail

# Verify that a rebuilt all-pairs characterization image reproduces the
# accepted RO physical lock.  PRIMARY evidence is the physical fingerprint
# (LOC/BEL/LOCK_PINS per endpoint and FIXED_ROUTE per net), compared byte
# for byte.  DCP/bitstream SHA-256 values are build-traceability only: DCPs
# can carry volatile metadata, so a differing DCP hash is a WARNING, not a
# physical-lock failure.
root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

golden_fingerprint="$root_dir/constraints/ro_physical_fingerprint_allpairs_zynq7020.tsv"
run_dir="$root_dir/build/puf_allpairs_characterization"
bitstream="$run_dir/puf_allpairs_zynq7020.runs/impl_1/Puf_AllPairs_Characterization_Top.bit"
checkpoint="$run_dir/puf_allpairs_zynq7020.runs/impl_1/Puf_AllPairs_Characterization_Top_routed.dcp"
timing="$root_dir/reports/puf_allpairs_characterization/post_route_timing.rpt"
drc="$root_dir/reports/puf_allpairs_characterization/post_route_drc.rpt"
fingerprint="$root_dir/reports/puf_allpairs_characterization/ro_physical_fingerprint.tsv"
metadata="$root_dir/reports/puf_allpairs_characterization/build_metadata.tsv"

for artifact in "$golden_fingerprint" "$bitstream" "$checkpoint" \
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
  echo "ERROR: all-pairs RO physical fingerprint (LOC/BEL/LOCK_PINS/FIXED_ROUTE)"
  echo "       differs from the accepted baseline." >&2
  exit 1
}

grep -q "fingerprint_status	OK" "$metadata" || {
  echo "ERROR: build metadata does not record an applied verified lock" >&2
  exit 1
}

echo "PASS: all-pairs image reproduces the accepted RO physical fingerprint"
echo "      (primary evidence: LOC/BEL/LOCK_PINS/FIXED_ROUTE)."
sha256sum "$bitstream" "$checkpoint" "$fingerprint" "$metadata"
if [[ -s "$root_dir/constraints/ro_physical_lock_allpairs_zynq7020.expected" ]]; then
  anchor_dcp="$(awk '$1 == "DCP_SHA" {print $2}' "$root_dir/constraints/ro_physical_lock_allpairs_zynq7020.expected")"
  if [[ -n "$anchor_dcp" && "$anchor_dcp" != "$(awk '$1 == "routed_dcp_sha256" {print $2}' "$metadata")" ]]; then
    echo "WARNING: routed DCP hash differs from the accepted build anchor;"
    echo "         this is traceability-only and does not fail the physical lock."
  fi
fi