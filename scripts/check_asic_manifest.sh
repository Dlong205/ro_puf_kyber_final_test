#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
filelist="$root_dir/asic/filelists/system_asic.f"
include_files="$root_dir/asic/filelists/include_files.txt"
manifest="$root_dir/asic/manifests/system_asic.sha256"

if ! awk 'NF != 2 || length($1) != 64 || $1 !~ /^[0-9a-f]+$/ {bad=1}
          END {exit bad}' "$manifest"; then
  echo "ERROR: malformed SHA-256 manifest line" >&2
  exit 1
fi

if ! diff -u \
    <({ awk 'NF && $1 !~ /^#/ {print}' "$filelist"; \
        awk 'NF && $1 !~ /^#/ {print}' "$include_files"; } | LC_ALL=C sort) \
    <(awk '{print $2}' "$manifest" | LC_ALL=C sort); then
  echo "ERROR: ASIC manifest differs from the source/header dependency set" >&2
  exit 1
fi

cd "$root_dir"
sha256sum --check --strict "$manifest"
echo "PASS: canonical system ASIC source/header set and SHA-256 manifest match"
