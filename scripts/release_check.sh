#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mode="${1:-public}"

cd "$root_dir"
./scripts/check_standalone.sh

# A release candidate must pass the deterministic single-attempt Kyber gate;
# the normal AXI test also remains in regression for register/handshake checks.
make -j1 regression
make -j1 kyber-long

test -s VERSION || { echo "ERROR: VERSION is missing" >&2; exit 1; }
test -s LICENSES/GPL-3.0-only.txt || { echo "ERROR: GPL text missing" >&2; exit 1; }
test -s LICENSES/BSD-2-Clause-BCH.txt || { echo "ERROR: BCH license missing" >&2; exit 1; }
test -s LICENSES/PicoRV32-ISC.txt || { echo "ERROR: PicoRV32 notice missing" >&2; exit 1; }
test -s SECURITY.md || { echo "ERROR: SECURITY.md missing" >&2; exit 1; }
test -s NOTICE.md || { echo "ERROR: NOTICE.md missing" >&2; exit 1; }

bitstream="build/vivado/kyber_ro_puf_zynq7020.runs/impl_1/Kyber_System_Top.bit"
if [[ ! -s "$bitstream" && -s Kyber_System_Top.bit ]]; then
  bitstream="Kyber_System_Top.bit"
fi
test -s "$bitstream" || { echo "ERROR: release bitstream missing" >&2; exit 1; }
test -s reports/post_route_timing.rpt || { echo "ERROR: timing report missing" >&2; exit 1; }
test -s reports/post_route_drc.rpt || { echo "ERROR: DRC report missing" >&2; exit 1; }

grep -q "All user specified timing constraints are met" reports/post_route_timing.rpt || {
  echo "ERROR: post-route timing did not pass" >&2
  exit 1
}
if grep -Eq '^ERROR:|^\|[^|]*\|[[:space:]]*(Error|Critical Warning)[[:space:]]*\|' \
    reports/post_route_drc.rpt; then
  echo "ERROR: post-route DRC contains errors" >&2
  exit 1
fi
if grep -Eq 'REQP-1839|REQP-1840' reports/post_route_drc.rpt; then
  echo "ERROR: asynchronous-reset-to-BRAM DRC warnings remain" >&2
  exit 1
fi

if find . -maxdepth 2 -type f \( -name 'helper.bin' -o -name 'hardware_helper.bin' \) \
    -print -quit | grep -q .; then
  echo "WARNING: local helper data exists and must remain excluded from packages" >&2
fi

if [[ "$mode" != "--internal" ]]; then
  test -s LICENSES/KYBER-PERMISSION.txt || {
    echo "BLOCKED: add explicit Kyber redistribution permission" >&2
    exit 2
  }
  test -s LICENSE || {
    echo "BLOCKED: select a top-level license for project-owned code" >&2
    exit 2
  }
fi

echo "PASS: release artifact, timing, DRC, provenance files and standalone invariants"
if [[ "$mode" == "--internal" ]]; then
  echo "INTERNAL RC ONLY: public license gates intentionally not waived"
else
  echo "PASS: public redistribution license gates"
fi
