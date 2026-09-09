#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
manifest=${1:-$repo_dir/manifests/edge_mlkem_integration_v01.sha256}
expected=$(mktemp)
listed=$(mktemp)
trap 'rm -f "$expected" "$listed"' EXIT

cd -- "$repo_dir"
printf '%s\n' \
    rtl/top/edge_mlkem_core.sv \
    sim/edge_mlkem/Makefile \
    sim/edge_mlkem/tb_edge_mlkem_core.sv \
    | LC_ALL=C sort > "$expected"

test -s "$manifest" || {
    echo "ERROR: missing Edge ML-KEM manifest: $manifest" >&2
    exit 1
}
awk 'NF != 2 || length($1) != 64 || $1 !~ /^[0-9a-f]+$/ {bad=1}
     {print $2} END {exit bad}' "$manifest" | LC_ALL=C sort > "$listed" || {
    echo "ERROR: malformed Edge ML-KEM manifest" >&2
    exit 1
}
diff -u "$expected" "$listed"
sha256sum --check --strict "$manifest"

# The integration wrapper depends on the already locked crypto candidate and
# the separately locked Edge control plane; neither dependency is duplicated
# in this small manifest.
bash scripts/check_crypto_freeze.sh manifests/crypto_rtl_freeze_candidate_v4.sha256
bash scripts/check_edge_control.sh
make -j1 -C sim/edge_mlkem check

echo "EDGE_MLKEM_INTEGRATION_V01_GATE=PASS"
echo "Scope: direct legacy stream integration; independent J oracle, framed transport and confirmation remain external gates."
