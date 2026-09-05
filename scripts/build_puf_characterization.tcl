# Build the isolated PUF characterization bitstream using one worker/thread.

set_param general.maxThreads 1
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
set project_file [file join $root_dir build puf_characterization puf_characterization_zynq7020.xpr]
set report_dir [file join $root_dir reports puf_characterization]
set placement_map [file join $root_dir constraints ro_placement_rc1_zynq7020.xdc]
source [file join $script_dir audit_ro_placement.tcl]

if {![file exists $project_file]} {
    error "PUF characterization project not found"
}

file mkdir $report_dir
open_project $project_file
reset_run synth_1
launch_runs synth_1 -jobs 1
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
puts "PUF_SYNTH_STATUS=$synth_status"
if {![string match "*Complete*" $synth_status]} {
    error "PUF synthesis did not complete: $synth_status"
}

open_run synth_1
set ro_luts [get_cells -quiet -hierarchical -filter {NAME =~ "*u_puf*ring*LUT6*"}]
puts "PUF_SYNTH_RO_LUT_COUNT=[llength $ro_luts]"
if {[llength $ro_luts] != 128} {
    error "Expected 128 physical RO LUTs, found [llength $ro_luts]"
}
audit_ro_placement $placement_map
report_utilization -file [file join $report_dir post_synth_utilization.rpt]
close_design

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 1
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
puts "PUF_IMPL_STATUS=$impl_status"
if {![string match "*Complete*" $impl_status]} {
    error "PUF implementation did not complete: $impl_status"
}

open_run impl_1
set placed_ro_luts [get_cells -quiet -hierarchical -filter {NAME =~ "*u_puf*ring*LUT6*"}]
puts "PUF_ROUTE_RO_LUT_COUNT=[llength $placed_ro_luts]"
if {[llength $placed_ro_luts] != 128} {
    error "RO placement map did not resolve completely"
}
audit_ro_placement $placement_map
report_utilization -file [file join $report_dir post_route_utilization.rpt]
report_timing_summary -file [file join $report_dir post_route_timing.rpt]
report_drc -file [file join $report_dir post_route_drc.rpt]
report_methodology -file [file join $report_dir post_route_methodology.rpt]
close_design
close_project
