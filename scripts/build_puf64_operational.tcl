# I4.2: first operational preservation build (synth + impl, no board program).
# Run under Vivado 2020.1 only, from the clean I4.1 checkpoint.
#
#   vivado -mode batch -nolog -nojournal -source scripts/build_puf64_operational.tcl
set_param general.maxThreads 1
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
source [file join $script_dir ro_physical_common.tcl]
source [file join $script_dir audit_puf64_operational_physical.tcl]

set build_dir [file join $root_dir build puf64_operational_preservation]
set project_file [file join $build_dir puf64_operational_zynq7020.xpr]
set report_dir [file join $root_dir reports puf64_operational_preservation]
set golden_fp [file join $report_dir golden_expanded_fingerprint.tsv]
set GOLDEN_DCP_SHA "febefcc7129fdf42aae7c3be55875ed61f8cfb72562bbe8830d514628b2788e0"

if {![file exists $project_file]} {
    error "I4.2 gate: operational project not found; run create_puf64_operational_project.tcl first"
}
if {![file isfile $golden_fp]} {
    error "I4.2 gate: golden expanded fingerprint missing ($golden_fp); export it from DCP $GOLDEN_DCP_SHA first"
}
file mkdir $report_dir
open_project $project_file
set commit_hash [exec git -C $root_dir rev-parse HEAD]
puts "I4_BUILD_COMMIT=$commit_hash"
puts "I4_VIVADO_VERSION=[version -short]"
if {![string match "2020.1*" [version -short]]} {
    error "I4.2 gate: Vivado 2020.1 required, found [version -short]"
}

# --- synthesis ---
reset_run synth_1
launch_runs synth_1 -jobs 1
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
puts "I4_SYNTH_STATUS=$synth_status"
if {![string match "*Complete*" $synth_status]} { error "I4.2 gate: synthesis failed: $synth_status" }
open_run synth_1 -name i4_synth
i4_audit_hierarchy
lassign [i4_audit_inventory] ro_luts presc stages
i4_audit_ro_tap_endpoints $presc
i4_audit_no_global_clocks $ro_luts $presc $stages
i4_audit_log_critical_warnings $build_dir synth
report_utilization -file [file join $report_dir post_synth_utilization.rpt]
report_timing_summary -file [file join $report_dir post_synth_timing.rpt]
close_design

# --- implementation ---
# Gate order: complete -> route -> timing -> critical warnings ->
# inventory/clock endpoints -> fingerprint export -> comparison.
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 1
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
puts "I4_IMPL_STATUS=$impl_status"
if {![string match "*Complete*" $impl_status]} { error "I4.2 gate: implementation failed: $impl_status" }
open_run impl_1 -name i4_impl
i4_audit_hierarchy
i4_audit_route_complete
i4_audit_timing_100mhz [file join $report_dir post_route_timing.rpt]
i4_audit_log_critical_warnings $build_dir impl
lassign [i4_audit_inventory] ro_luts presc stages
i4_audit_ro_tap_endpoints $presc
i4_audit_no_global_clocks $ro_luts $presc $stages
report_utilization -file [file join $report_dir post_route_utilization.rpt]
report_route_status -file [file join $report_dir post_route_status.rpt]
report_drc -file [file join $report_dir post_route_drc.rpt]
report_methodology -file [file join $report_dir post_route_methodology.rpt]
report_clock_utilization -file [file join $report_dir post_route_clock_util.rpt]
close_design

# --- candidate fingerprint + comparison (fail-closed) ---
set routed_dcp [file join $build_dir puf64_operational_zynq7020.runs impl_1 \
    Edge_Puf64_Zynq_Operational_100MHz_Top_routed.dcp]
set bitstream [file join $build_dir puf64_operational_zynq7020.runs impl_1 \
    Edge_Puf64_Zynq_Operational_100MHz_Top.bit]
set cand_fp [file join $report_dir candidate_expanded_fingerprint.tsv]
set bit_sha [ro_sha256_file $bitstream]
set dcp_sha [ro_sha256_file $routed_dcp]
puts "I4_CANDIDATE_BITSTREAM_SHA=$bit_sha"
puts "I4_CANDIDATE_DCP_SHA=$dcp_sha"

# Extract via the candidate exporter in a nested Vivado call so the open
# design state above cannot leak into the fingerprint.
set exporter [file join $script_dir export_puf64_operational_candidate_fingerprint.tcl]
if {[catch {exec vivado -mode batch -nolog -nojournal -source $exporter \
        -tclargs $routed_dcp $cand_fp} export_err]} {
    error "I4.2 gate: candidate fingerprint export failed: $export_err"
}
set cmp [file join $script_dir compare_puf64_operational_fingerprint.py]
# NOTE: nested exec inherits Vivado's PYTHONHOME/PYTHONPATH (a Python 2.7
# tree), which breaks system python3.  Strip them for the comparator call.
if {[catch {exec env -u PYTHONHOME -u PYTHONPATH python3 $cmp $golden_fp $cand_fp} cmp_err]} {
    puts "I4_CANDIDATE_FINGERPRINT=$cand_fp"
    error "I4_PHYSICAL_FINGERPRINT_MISMATCH: $cmp_err"
}
puts "I4_PHYSICAL_FINGERPRINT_MATCH"
puts "I4_BUILD_DONE bitstream=$bitstream dcp=$routed_dcp fingerprint=$cand_fp"
close_project
