#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest="${1:-$root_dir/manifests/crypto_rtl_freeze_candidate.sha256}"
expected_files="$(mktemp)"
manifest_files="$(mktemp)"
trap 'rm -f "$expected_files" "$manifest_files"' EXIT

cd "$root_dir"
test -s "$manifest" || {
  echo "ERROR: crypto RTL freeze manifest is missing: $manifest" >&2
  exit 1
}

{
  find rtl/common rtl/hash_core rtl/kyber -type f \
    \( -name '*.v' -o -name '*.sv' \) -print
  printf '%s\n' rtl/top/kdf_keccak.sv
} | LC_ALL=C sort >"$expected_files"

awk '{print $2}' "$manifest" | LC_ALL=C sort >"$manifest_files"
if ! diff -u "$manifest_files" "$expected_files"; then
  echo "ERROR: crypto RTL file set differs from the freeze manifest" >&2
  exit 1
fi

sha256sum --check --strict "$manifest"
echo "PASS: crypto RTL source set and SHA-256 freeze manifest match"
