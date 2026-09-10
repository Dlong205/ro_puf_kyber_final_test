#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
report_dir="$repo_dir/reports/fpga_split_2026-09-10/edgefull_compact_v02"
summary="$report_dir/summary.json"

cd -- "$repo_dir"
bash scripts/check_edge_wrapper.sh
bash scripts/check_edge_mlkem.sh
sha256sum --check --strict "$report_dir/edgefull/source_manifest.sha256"

python3 - "$summary" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert len(data["blocks"]) == 1
block = data["blocks"][0]
assert block["block"] == "edgefull"
assert block["metadata"]["part"] == "xc7a35ticsg324-1L"
assert block["metadata"]["puf_backend"] == "xilinx_lut"
assert block["resources"]["lut"] == {"used": 19566.0, "available": 20800.0}
assert block["diagnostics"]["errors"] == []
critical = block["diagnostics"]["critical_warnings"]
assert len(critical) == 32
assert all("Synth 8-295" in line and "kp_ro_cell_xilinx.sv" in line
           for line in critical)
print("EDGE_ARTY35T_OOC_RESOURCE=19566/20800_LUT")
PY

echo "EDGE_ARTY35T_RESOURCE_CANDIDATE_V02_GATE=PASS"
echo "Scope: OOC synthesis/resource only; 32 intentional RO timing loops remain for physical constraints and P&R."
