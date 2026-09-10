# Build a volatile, characterization-only image using one Vivado worker.
set_param general.maxThreads 1
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
set project_file [file join $root_dir build arty_puf_characterization \
    puf_characterization_arty_a7_35t.xpr]
set report_dir [file join $root_dir reports arty_puf_characterization]
if {![file exists $project_file]} {error "Arty PUF project not found"}
file mkdir $report_dir
open_project $project_file

reset_run synth_1
launch_runs synth_1 -jobs 1
wait_on_run synth_1
if {![string match "*Complete*" [get_property STATUS [get_runs synth_1]]]} {
    error "Arty PUF synthesis failed: [get_property STATUS [get_runs synth_1]]"
}
open_run synth_1
set ro_luts [get_cells -quiet -hierarchical -filter {NAME =~ "*u_puf*ring*LUT6*"}]
set ro_nets [get_nets -quiet -hierarchical -filter {NAME =~ "*u_puf*ring*/t*"}]
puts "ARTY_PUF_SYNTH_RO_LUT_COUNT=[llength $ro_luts]"
puts "ARTY_PUF_SYNTH_RO_LOOP_NET_COUNT=[llength $ro_nets]"
if {[llength $ro_luts] != 128 || [llength $ro_nets] != 128} {
    error "RO inventory mismatch"
}
report_utilization -file [file join $report_dir post_synth_utilization.rpt]
close_design

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 1
wait_on_run impl_1
if {![string match "*Complete*" [get_property STATUS [get_runs impl_1]]]} {
    error "Arty PUF implementation failed: [get_property STATUS [get_runs impl_1]]"
}
open_run impl_1
set placed_ro_luts [get_cells -quiet -hierarchical -filter {NAME =~ "*u_puf*ring*LUT6*"}]
puts "ARTY_PUF_ROUTE_RO_LUT_COUNT=[llength $placed_ro_luts]"
if {[llength $placed_ro_luts] != 128} {error "RO LUTs lost after route"}
report_utilization -file [file join $report_dir post_route_utilization.rpt]
report_timing_summary -file [file join $report_dir post_route_timing.rpt]
report_drc -file [file join $report_dir post_route_drc.rpt]
report_methodology -file [file join $report_dir post_route_methodology.rpt]
close_design
close_project
