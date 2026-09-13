#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(cd -- "$script_dir/../.." && pwd)
vivado_bin=${VIVADO:-vivado}
run_id=${1:-edge_arty_diag_$(date -u +%Y%m%dT%H%M%SZ)}
memory_gib=${FPGA_100MHZ_MEMORY_GIB:-4}
timeout_duration=${FPGA_100MHZ_TIMEOUT:-30m}
part=xc7a35ticsg324-1L
[[ "$run_id" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "Invalid run id" >&2; exit 2; }
[[ "$memory_gib" =~ ^[1-9][0-9]*$ ]] || { echo "Invalid memory cap" >&2; exit 2; }
command -v "$vivado_bin" >/dev/null || { echo "Vivado not found: $vivado_bin" >&2; exit 2; }

out_dir="$repo_dir/build/fpga_100mhz/$run_id"
[[ ! -e "$out_dir" ]] || { echo "Output exists: $out_dir" >&2; exit 2; }
mkdir -p -- "$out_dir"
exec 9>"$repo_dir/build/fpga_100mhz/.worker.lock"
flock -n 9 || { echo "Another 100 MHz experiment is running" >&2; exit 2; }

cd -- "$repo_dir"
git rev-parse HEAD > "$out_dir/source_commit.txt"
git status --porcelain=v1 > "$out_dir/source_worktree_status.txt"
sha256sum -- constraints/edge_arty_diagnostic_35t.xdc \
    rtl/top/edge_mlkem_core.sv rtl/top/edge_uart_transport.sv \
    rtl/top/Edge_Arty_Diagnostic_Top.sv \
    "$script_dir/edge_arty_diag_implement.tcl" "$script_dir/run_edge_arty_diag.sh" \
    > "$out_dir/source_manifest.sha256"

vivado_command=(nice -n 10 timeout --signal=TERM --kill-after=30s "$timeout_duration"
    "$vivado_bin" -mode batch -nojournal -log "$out_dir/vivado.log"
    -source "$script_dir/edge_arty_diag_implement.tcl"
    -tclargs "$part" "$out_dir")
printf 'Edge Arty diagnostic 100MHz memory_cap=%sGiB output=%s\n' "$memory_gib" "$out_dir"
if command -v systemd-run >/dev/null && systemctl --user show-environment >/dev/null 2>&1; then
    systemd-run --user --scope --quiet -p "MemoryMax=${memory_gib}G" \
        -p MemorySwapMax=0 -p CPUQuota=100% "${vivado_command[@]}" \
        > "$out_dir/console.log" 2>&1
else
    cpu=$(awk '/^Cpus_allowed_list:/ {split($2, ids, /[-,]/); print ids[1]}' /proc/self/status)
    (
        ulimit -v "$((memory_gib * 1024 * 1024))"
        taskset -c "$cpu" "${vivado_command[@]}"
    ) > "$out_dir/console.log" 2>&1
fi
test -s "$out_dir/Edge_Arty_Diagnostic_Top.bit"
cat "$out_dir/result.tsv"
