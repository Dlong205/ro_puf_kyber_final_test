#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd -- "$repo_dir"
sha256sum --check --strict manifests/edge_wrapper_v02.sha256
make -C sim/edge_wrapper -j1
echo "EDGE_WRAPPER_HANDOFF_V02_GATE=PASS"
echo "Scope: wrapper FSM handoff with stubs; not full PUF/FE/ML-KEM functional simulation."
