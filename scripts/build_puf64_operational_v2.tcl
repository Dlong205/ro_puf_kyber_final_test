# R5-shell: operational-V2 construction build (CONSTRUCTION, NON-RELEASE).
# Proves macro import + timing + fingerprint in the full operational design
# before R4 yields the real mapping.  Placeholder mapping only.  Run under
# Vivado 2020.1:
#   vivado -mode batch -nolog -nojournal -source scripts/build_puf64_macrov2_char.tcl
# Gate order: synth complete -> import (target/inventory/routes/ports) ->
# impl complete -> route -> timing 100MHz -> critical logs -> inventory/clock
# -> V2 fingerprint export -> R2_MACRO_FINGERPRINT_MATCH (required).
set_param general.maxThreads 1
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
source [file join $script_dir ro_physical_common.tcl]
source [file join $script_dir audit_macro_v2_import.tcl]
# Critical-warning evidence for project flows lives in reports (DRC/
# methodology) plus 0-CRITICAL runme.logs; checked post-build by
# scripts/check_v2_image_reports.py (the 8-295 synth message does not exist
# when the macro arrives as a black box).

set build_dir [file join $root_dir build puf64_operational_v2]
set project_file [file join $build_dir puf64_operational_v2_zynq7020.xpr]
set report_dir [file join $root_dir reports/puf64_operational_v2]
set macro_dcp [file join $root_dir build puf64_macro_v2 macro_v2_routed_ooc.dcp]
set macro_fp [file join $root_dir build puf64_macro_v2 macro_v2_fingerprint.tsv]
set FROZEN_MACRO_SHA "bd0cd6200ca4e122932596eb8502d29f1b7d4b1aedf974a79990b4d1f5a9fdd4"
set TARGET "u_operational_uart/u_chain/u_puf64_core/u_macro"

if {![file exists $project_file]} {
    error "R5SH gate: char project not found; run create_puf64_macrov2_char_project.tcl first"
}
if {[ro_sha256_file $macro_dcp] ne $FROZEN_MACRO_SHA} {
    error "R5SH gate: macro DCP is not the frozen R2 macro (SHA mismatch)"
}
if {![file isfile $macro_fp]} { error "R5SH gate: macro fingerprint missing" }
puts "R5SH_FROZEN_MACRO_SHA_OK=$FROZEN_MACRO_SHA"
file mkdir $report_dir
open_project $project_file
# Hermetic rebuild: a previous read_checkpoint -cell persists the OOC DCP in
# the project (ScopedToCell=u_macro) and Vivado would auto-link it at synth,
# so the pre-import box would not be empty.  Remove any such association so
# every build synthesizes a clean black box and imports explicitly.
set stale_ooc [get_files -quiet "*macro_v2_routed_ooc.dcp"]
if {[llength $stale_ooc] != 0} {
    remove_files $stale_ooc
    puts "R5SH_HERMETIC_REMOVED_STALE_OOC=$stale_ooc"
}
puts "R5SH_BUILD_COMMIT=[exec git -C $root_dir rev-parse HEAD]"
puts "R5SH_VIVADO_VERSION=[version -short]"
if {![string match "2020.1*" [version -short]]} {
    error "R5SH gate: Vivado 2020.1 required"
}
if {[get_property TOP [get_filesets sources_1]] ne "Edge_Puf64_Zynq_Operational_V2_100MHz_Top"} {
    error "R5SH gate: wrong top"
}

# --- synthesis (macro stays a black box) ---
reset_run synth_1
launch_runs synth_1 -jobs 1
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
puts "R5SH_SYNTH_STATUS=$synth_status"
if {![string match "*Complete*" $synth_status]} { error "R5SH gate: synthesis failed" }
open_run synth_1 -name r3_synth
set pre_sub [get_cells -quiet -hierarchical -filter "NAME =~ \"*${TARGET}/*\""]
if {[llength $pre_sub] != 0} {
    error "R5SH gate: black box $TARGET not empty pre-import: $pre_sub"
}
puts "R5SH_BLACKBOX_EMPTY=PASS"

# --- import the exact frozen macro ---
read_checkpoint -cell [get_cells $TARGET] $macro_dcp
puts "R5SH_IMPORT_ACCEPTED"
macro_v2_audit_import $TARGET 1
macro_v2_lock_imported $TARGET
set synth_dcp [file join $build_dir puf64_operational_v2_zynq7020.runs synth_1 \
    Edge_Puf64_Zynq_Operational_V2_100MHz_Top.dcp]
write_checkpoint -force $synth_dcp
puts "R5SH_SYNTH_IMPORTED_SAVED=$synth_dcp"
close_design

# --- implementation of the rest ---
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 1
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
puts "R5SH_IMPL_STATUS=$impl_status"
if {![string match "*Complete*" $impl_status]} { error "R5SH gate: implementation failed" }
open_run impl_1 -name r3_impl
if {[get_property TOP [current_design]] ne "Edge_Puf64_Zynq_Operational_V2_100MHz_Top"} {
    error "R5SH gate: wrong top after impl"
}
set dupes [get_cells -quiet -hierarchical -filter "NAME =~ \"*u_macro\""]
if {[llength $dupes] != 1} { error "R5SH gate: macro instance issue: $dupes" }
set rs_file [file join $report_dir post_route_status.rpt]
report_route_status -file $rs_file
set ch [open $rs_file r]
set rs_data [read $ch]
close $ch
if {[regexp -nocase {partial|unrouted|RTSTAT|conflict} $rs_data]} {
    error "R3 route gate: partial/RTSTAT/conflict (see $rs_file)"
}
puts "R5SH_ROUTE_STATUS=PASS"
set tm_file [file join $report_dir post_route_timing.rpt]
report_timing_summary -file $tm_file -max_paths 10
set ch [open $tm_file r]
set tm_data [read $ch]
close $ch
if {[regexp {(VIOLATED|Timing constraints are not met)} $tm_data]} {
    error "R3 timing gate: 100 MHz violations (see $tm_file)"
}
puts "R5SH_TIMING_100MHZ=PASS"
macro_v2_audit_import $TARGET 1
report_utilization -file [file join $report_dir post_route_utilization.rpt]
report_timing_summary -file $tm_file -max_paths 10
report_drc -file [file join $report_dir post_route_drc.rpt]
report_methodology -file [file join $report_dir post_route_methodology.rpt]
report_clock_utilization -file [file join $report_dir post_route_clock_util.rpt]
close_design

# --- fingerprint equality with the frozen macro ---
set routed_dcp [file join $build_dir puf64_operational_v2_zynq7020.runs impl_1 \
    Edge_Puf64_Zynq_Operational_V2_100MHz_Top_routed.dcp]
set bitstream [file join $build_dir puf64_operational_v2_zynq7020.runs impl_1 \
    Edge_Puf64_Zynq_Operational_V2_100MHz_Top.bit]
set shell_fp [file join $report_dir shell_v2_fingerprint.tsv]
puts "R5SH_SHELL_BITSTREAM_SHA=[ro_sha256_file $bitstream]"
puts "R5SH_SHELL_DCP_SHA=[ro_sha256_file $routed_dcp]"
set exporter [file join $script_dir export_puf64_macro_v2_fingerprint.tcl]
if {[catch {exec vivado -mode batch -nolog -nojournal -source $exporter \
        -tclargs $routed_dcp $shell_fp "SHELL_DCP_SHA"} export_err]} {
    error "R5SH gate: char fingerprint export failed: $export_err"
}
set cmp [file join $script_dir compare_puf64_macro_v2_fingerprint.py]
if {[catch {exec env -u PYTHONHOME -u PYTHONPATH python3 $cmp $macro_fp $shell_fp} cmp_err]} {
    error "R2_MACRO_FINGERPRINT_MISMATCH(shell): $cmp_err"
}
puts "R2_MACRO_FINGERPRINT_MATCH(shell)"
puts "R5SH_SHELL_BUILD_DONE bitstream=$bitstream"
close_project
