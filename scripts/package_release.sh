#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mode="${1:-public}"
version="$(tr -d '[:space:]' < "$root_dir/VERSION")"
release_dir="$root_dir/release"
name="kyber-ro-puf-zynq7020-$version"

cd "$root_dir"
if [[ "$mode" == "--internal" ]]; then
  ./scripts/release_check.sh --internal
  name="$name-internal"
else
  ./scripts/release_check.sh
fi

mkdir -p "$release_dir"
archive="$release_dir/$name.tar.gz"
checksum="$archive.sha256"
manifest=(.gitattributes .gitignore ARTIFACTS.sha256 CHANGELOG.md LICENSES Makefile NOTICE.md README.md SECURITY.md VERSION
          constraints docs firmware host rtl scripts sim reports)
if [[ -f LICENSE ]]; then
  manifest+=(LICENSE)
fi

bitstream="Kyber_System_Top.bit"
if [[ ! -s "$bitstream" ]]; then
  bitstream="build/vivado/kyber_ro_puf_zynq7020.runs/impl_1/Kyber_System_Top.bit"
fi
test -s "$bitstream" || {
  echo "ERROR: no rebuilt or checked-in bitstream found" >&2
  exit 1
}

tar --sort=name --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner \
  --transform="s,^,$name/," \
  --exclude='build' \
  --exclude='release' \
  --exclude='sim/*/obj_dir*' \
  --exclude='sim/fuzzy_extractor/rtl_tcq0' \
  --exclude='sim/fuzzy_extractor/tb_fuzzy_extractor_main.cpp' \
  --exclude='firmware/firmware.elf' \
  --exclude='firmware/firmware.bin' \
  --exclude='firmware/.mode_*' \
  --exclude='helper.bin' \
  --exclude='hardware_helper.bin' \
  --exclude='*/__pycache__' \
  --exclude='*.pyc' \
  --exclude='.Xil' \
  --exclude='*.jou' --exclude='*.log' --exclude='*.pb' --exclude='*.vcd' \
  -czf "$archive" \
  "${manifest[@]}" \
  -C "$(dirname "$bitstream")" \
  "$(basename "$bitstream")"

sha256sum "$archive" > "$checksum"
echo "PACKAGE=$archive"
echo "CHECKSUM=$checksum"
