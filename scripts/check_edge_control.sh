#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
manifest=${1:-$repo_dir/manifests/edge_control_v02.sha256}
expected=$(mktemp)
listed=$(mktemp)
trap 'rm -f "$expected" "$listed"' EXIT

cd -- "$repo_dir"
for name in \
    rtl/top/edge_seed_controller.sv \
    rtl/top/edge_kem_scrub_controller.sv \
    rtl/top/edge_control_plane.sv \
    rtl/top/kdf_keccak_compact.sv \
    sim/edge_seed/Makefile \
    sim/edge_seed/tb_kdf_compact.sv \
    sim/edge_seed/tb_edge_seed_controller.sv \
    sim/edge_seed/tb_edge_kem_scrub_controller.sv \
    sim/edge_seed/tb_edge_control_plane.sv
do
    printf '%s\n' "$name"
done | LC_ALL=C sort > "$expected"

test -s "$manifest" || { echo "ERROR: missing Edge manifest: $manifest" >&2; exit 1; }
awk 'NF != 2 || length($1) != 64 || $1 !~ /^[0-9a-f]+$/ {bad=1}
     {print $2} END {exit bad}' "$manifest" | LC_ALL=C sort > "$listed" || {
    echo "ERROR: malformed Edge manifest" >&2
    exit 1
}
diff -u "$expected" "$listed"
sha256sum --check --strict "$manifest"
make -j1 -C sim/edge_seed check
echo "EDGE_CONTROL_V02_GATE=PASS"
echo "Scope: controller-level only; use check_edge_mlkem.sh for direct Kyber integration."
