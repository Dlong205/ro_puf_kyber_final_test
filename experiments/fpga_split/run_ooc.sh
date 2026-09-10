#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "Usage: bash experiments/fpga_split/run_ooc.sh <client|server|edgecore|edgefull|kdf|seedctl|fe|puf> [run-id]" >&2
    exit 2
fi
block=$1
run_id=${2:-$(date -u +%Y%m%dT%H%M%SZ)}
case "$block" in client|server|edgecore|edgefull|kdf|seedctl|fe|puf) ;; *) echo "Unknown block: $block" >&2; exit 2;; esac
[[ "$run_id" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "Invalid run-id" >&2; exit 2; }
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(cd -- "$script_dir/../.." && pwd)
vivado_bin=${VIVADO:-vivado}
part=${FPGA_SPLIT_PART:-xc7a35ticsg324-1L}
timeout_duration=${FPGA_SPLIT_TIMEOUT:-20m}
memory_gib=${FPGA_SPLIT_MEMORY_GIB:-8}
[[ "$memory_gib" =~ ^[1-9][0-9]*$ ]] || { echo "Invalid memory cap" >&2; exit 2; }
command -v "$vivado_bin" >/dev/null || { echo "Vivado not found: $vivado_bin" >&2; exit 2; }
for command_name in tclsh timeout flock sha256sum nice; do
    command -v "$command_name" >/dev/null || { echo "Missing command: $command_name" >&2; exit 2; }
done
out_dir="$repo_dir/build/fpga_split/$run_id/$block"
mkdir -p -- "$repo_dir/build/fpga_split"
# Serialize every invocation of this experiment across all run ids.
exec 9>"$repo_dir/build/fpga_split/.worker.lock"
flock -n 9 || { echo "Another FPGA split experiment is running" >&2; exit 2; }
[[ ! -e "$out_dir" ]] || { echo "Output exists; choose a fresh run-id: $out_dir" >&2; exit 2; }
mkdir -p -- "$out_dir"
cd -- "$repo_dir"
tclsh "$script_dir/sources.tcl" "$block" > "$out_dir/inputs.txt"
while IFS= read -r input_path; do
    sha256sum -- "$input_path"
done < "$out_dir/inputs.txt" > "$out_dir/source_manifest.sha256"
git rev-parse HEAD > "$out_dir/source_commit.txt"
git status --porcelain=v1 > "$out_dir/source_worktree_status.txt"

vivado_command=(nice -n 10 timeout --signal=TERM --kill-after=30s "$timeout_duration"
    "$vivado_bin" -mode batch -nojournal -log "$out_dir/vivado.log"
    -source "$script_dir/synth_block.tcl" -tclargs "$block" "$part" "$out_dir")
printf 'OOC block=%s part=%s timeout=%s memory_cap=%sGiB output=%s\n' \
    "$block" "$part" "$timeout_duration" "$memory_gib" "$out_dir"
cd -- "$out_dir"
if command -v systemd-run >/dev/null && command -v systemctl >/dev/null &&
        systemctl --user show-environment >/dev/null 2>&1; then
    # Cgroup caps include Vivado children; one core worth of CPU, no swap storm.
    systemd-run --user --scope --quiet \
        -p "MemoryMax=${memory_gib}G" -p MemorySwapMax=0 -p CPUQuota=100% \
        "${vivado_command[@]}" > "$out_dir/console.log" 2>&1
else
    # Fail-safe fallback: bound address space and pin to one allowed CPU.
    # Address-space limit is stricter than an RSS cap; startup can fail on hosts
    # where Vivado reserves a large virtual range. Never retry uncapped.
    command -v taskset >/dev/null || { echo "taskset required without systemd cgroup" >&2; exit 2; }
    cpu=$(awk '/^Cpus_allowed_list:/ {split($2, ids, /[-,]/); print ids[1]}' /proc/self/status)
    [[ "$cpu" =~ ^[0-9]+$ ]] || { echo "Cannot determine an allowed CPU" >&2; exit 2; }
    (
        ulimit -v "$((memory_gib * 1024 * 1024))"
        taskset -c "$cpu" "${vivado_command[@]}"
    ) > "$out_dir/console.log" 2>&1
fi
test -f "$out_dir/COMPLETE"
sha256sum --check --status "$out_dir/source_manifest.sha256"
printf 'PASS: %s\n' "$out_dir"
