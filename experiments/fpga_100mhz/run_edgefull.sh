#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(cd -- "$script_dir/../.." && pwd)
vivado_bin=${VIVADO:-vivado}
run_id=${1:-$(date -u +%Y%m%dT%H%M%SZ)}
part=${FPGA_100MHZ_PART:-xc7a35ticsg324-1L}
memory_gib=${FPGA_100MHZ_MEMORY_GIB:-4}
timeout_duration=${FPGA_100MHZ_TIMEOUT:-30m}
[[ "$run_id" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "Invalid run id" >&2; exit 2; }
[[ "$memory_gib" =~ ^[1-9][0-9]*$ ]] || { echo "Invalid memory cap" >&2; exit 2; }
command -v "$vivado_bin" >/dev/null || { echo "Vivado not found: $vivado_bin" >&2; exit 2; }

out_dir="$repo_dir/build/fpga_100mhz/$run_id"
[[ ! -e "$out_dir" ]] || { echo "Output exists: $out_dir" >&2; exit 2; }
mkdir -p -- "$out_dir"
exec 9>"$repo_dir/build/fpga_100mhz/.worker.lock"
flock -n 9 || { echo "Another 100 MHz experiment is running" >&2; exit 2; }

cd -- "$repo_dir"
tclsh experiments/fpga_split/sources.tcl edgefull > "$out_dir/inputs.txt"
while IFS= read -r input_path; do sha256sum -- "$input_path"; done \
    < "$out_dir/inputs.txt" > "$out_dir/source_manifest.sha256"
sha256sum -- "$script_dir/edgefull_implement.tcl" \
    "$script_dir/clock_100mhz.xdc" "$script_dir/run_edgefull.sh" \
    >> "$out_dir/source_manifest.sha256"
git rev-parse HEAD > "$out_dir/source_commit.txt"
git status --porcelain=v1 > "$out_dir/source_worktree_status.txt"

vivado_command=(nice -n 10 timeout --signal=TERM --kill-after=30s "$timeout_duration"
    "$vivado_bin" -mode batch -nojournal -log "$out_dir/vivado.log"
    -source "$script_dir/edgefull_implement.tcl" -tclargs "$part" "$out_dir")
printf 'Edge 100MHz part=%s memory_cap=%sGiB output=%s\n' "$part" "$memory_gib" "$out_dir"
if command -v systemd-run >/dev/null && systemctl --user show-environment >/dev/null 2>&1; then
    systemd-run --user --scope --quiet -p "MemoryMax=${memory_gib}G" \
        -p MemorySwapMax=0 -p CPUQuota=100% "${vivado_command[@]}" \
        > "$out_dir/console.log" 2>&1
else
    command -v taskset >/dev/null || { echo "taskset is required" >&2; exit 2; }
    cpu=$(awk '/^Cpus_allowed_list:/ {split($2, ids, /[-,]/); print ids[1]}' /proc/self/status)
    (
        ulimit -v "$((memory_gib * 1024 * 1024))"
        taskset -c "$cpu" "${vivado_command[@]}"
    ) > "$out_dir/console.log" 2>&1
fi
test -f "$out_dir/result.tsv"
sha256sum --check --status "$out_dir/source_manifest.sha256"
cat "$out_dir/result.tsv"
