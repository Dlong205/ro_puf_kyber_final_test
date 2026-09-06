# Build and audit one isolated full-SoC reproducibility candidate.

set_param general.maxThreads 1
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
set run_id locked_a
if {[llength $argv] > 0} {
    set run_id [lindex $argv 0]
}
if {![regexp {^[A-Za-z0-9_-]+$} $run_id]} {
    error "Invalid reproducibility run id: $run_id"
}

set build_dir [file join $root_dir build soc_repro $run_id]
set project_file [file join $build_dir "kyber_ro_puf_${run_id}.xpr"]
set report_dir [file join $build_dir reports]
set golden_fingerprint [file join $root_dir constraints \
    ro_physical_fingerprint_rc1_zynq7020.tsv]
set actual_fingerprint [file join $report_dir ro_physical_fingerprint.tsv]
set placement_map [file join $root_dir constraints \
    ro_placement_rc1_zynq7020.xdc]
set physical_lock [file join $root_dir constraints \
    ro_physical_lock_rc1_zynq7020.xdc]
source [file join $script_dir audit_ro_placement.tcl]
source [file join $script_dir audit_ro_physical_lock.tcl]

if {![file exists $project_file]} {
    error "Reproducibility project not found: $project_file"
}
file mkdir $report_dir
open_project $project_file
if {[llength [get_ips -quiet]] != 0 ||
    [llength [get_files -all -quiet *.xci]] != 0} {
    error "Generated Xilinx IP unexpectedly entered the reproducibility build"
}
set lock_in_project [get_files -quiet -all [file normalize $physical_lock]]
if {[llength $lock_in_project] != 1 ||
    [get_property USED_IN_SYNTHESIS $lock_in_project] ||
    ![get_property USED_IN_IMPLEMENTATION $lock_in_project] ||
    [get_property PROCESSING_ORDER $lock_in_project] ne "LATE"} {
    error "Reproducibility project does not contain the implementation-only LATE RO physical lock"
}

reset_run synth_1
launch_runs synth_1 -jobs 1
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
puts "SOC_REPRO_SYNTH_STATUS=$synth_status"
if {![string match "*Complete*" $synth_status]} {
    error "Reproducibility synthesis did not complete: $synth_status"
}

open_run synth_1
set ro_luts [get_cells -quiet -hierarchical \
    -filter {NAME =~ "*u_puf*ring*LUT6*"}]
if {[llength $ro_luts] != 128} {
    error "Expected 128 physical RO LUTs after synthesis, found [llength $ro_luts]"
}
audit_ro_placement $placement_map
report_utilization -file [file join $report_dir post_synth_utilization.rpt]
close_design

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 1
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
puts "SOC_REPRO_IMPL_STATUS=$impl_status"
if {![string match "*Complete*" $impl_status]} {
    error "Reproducibility implementation did not complete: $impl_status"
}

open_run impl_1
audit_ro_physical_lock $golden_fingerprint $actual_fingerprint
report_utilization -file [file join $report_dir post_route_utilization.rpt]
report_timing_summary -file [file join $report_dir post_route_timing.rpt]
report_route_status -file [file join $report_dir post_route_status.rpt]
report_drc -file [file join $report_dir post_route_drc.rpt]
report_methodology -file [file join $report_dir post_route_methodology.rpt]
set bitstream [file join $build_dir \
    "kyber_ro_puf_${run_id}.runs" impl_1 Kyber_System_Top.bit]
puts "SOC_REPRO_BITSTREAM=$bitstream"
puts "SOC_REPRO_PHYSICAL_AUDIT=PASS"
close_design
close_project
