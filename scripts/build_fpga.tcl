# Run synthesis or implementation for the standalone project.
# One worker is deliberate: this project previously exhausted RAM with jobs=2.

set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
set project_file [file join $root_dir build vivado kyber_ro_puf_zynq7020.xpr]
set report_dir [file join $root_dir reports]
set stage synth
if {[llength $argv] > 0} {
    set stage [lindex $argv 0]
}
if {$stage ni {synth impl}} {
    error "Stage must be synth or impl"
}
if {![file exists $project_file]} {
    error "Project not found. Run scripts/create_project.tcl first."
}

file mkdir $report_dir
open_project $project_file
set_param general.maxThreads 2
if {[llength [get_ips -quiet]] != 0 || [llength [get_files -all -quiet *.xci]] != 0} {
    error "Standalone invariant failed: generated Xilinx IP is present"
}

# Always rebuild synthesis.  Vivado 2020.1 can leave STATUS at "Complete"
# when externally referenced RTL or a memory-init file changes, which risks
# producing a bitstream from a stale netlist.
reset_run synth_1
launch_runs synth_1 -jobs 1
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
puts "SYNTH_STATUS=$synth_status"
if {![string match "*Complete*" $synth_status]} {
    error "Synthesis did not complete: $synth_status"
}

open_run synth_1
report_utilization -file [file join $report_dir post_synth_utilization.rpt]
report_timing_summary -file [file join $report_dir post_synth_timing.rpt]
report_cdc -details -file [file join $report_dir post_synth_cdc.rpt]
close_design

if {$stage eq "impl"} {
    reset_run impl_1
    launch_runs impl_1 -to_step write_bitstream -jobs 1
    wait_on_run impl_1
    set impl_status [get_property STATUS [get_runs impl_1]]
    puts "IMPL_STATUS=$impl_status"
    if {![string match "*Complete*" $impl_status]} {
        error "Implementation did not complete: $impl_status"
    }
    open_run impl_1
    report_utilization -file [file join $report_dir post_route_utilization.rpt]
    report_timing_summary -file [file join $report_dir post_route_timing.rpt]
    report_drc -file [file join $report_dir post_route_drc.rpt]
    report_methodology -file [file join $report_dir post_route_methodology.rpt]
    close_design
}
close_project
