# Build the Phase B PUF64 single-RO microbenchmark and gate connectivity at
# both post-synthesis and post-route.
set_param general.maxThreads 1
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
set project_file [file join $root_dir build puf64_microbench puf64_microbench_zynq7020.xpr]
set report_dir [file join $root_dir reports puf64_microbench]
source [file join $script_dir check_ro_microbench_connectivity.tcl]

if {![file exists $project_file]} { error "Microbench project not found" }
file mkdir $report_dir
open_project $project_file

reset_run synth_1
launch_runs synth_1 -jobs 1
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
puts "PUF64_MICROBENCH_SYNTH_STATUS=$synth_status"
if {![string match "*Complete*" $synth_status]} { error "Microbench synthesis failed" }

open_run synth_1
check_ro_microbench_connectivity "synth"
report_utilization -file [file join $report_dir post_synth_utilization.rpt]
close_design

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 1
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
puts "PUF64_MICROBENCH_IMPL_STATUS=$impl_status"
if {![string match "*Complete*" $impl_status]} { error "Microbench implementation failed" }

open_run impl_1
check_ro_microbench_connectivity "route"
report_utilization -file [file join $report_dir post_route_utilization.rpt]
report_timing_summary -file [file join $report_dir post_route_timing.rpt]
report_route_status -file [file join $report_dir post_route_status.rpt]
report_drc -file [file join $report_dir post_route_drc.rpt]
close_design

set bitstream [file join $root_dir build puf64_microbench \
    puf64_microbench_zynq7020.runs impl_1 Puf64_Ro_Microbench_Zynq_Top.bit]
set routed_dcp [file join $root_dir build puf64_microbench \
    puf64_microbench_zynq7020.runs impl_1 Puf64_Ro_Microbench_Zynq_Top_routed.dcp]
set metadata_file [file join $report_dir build_metadata.tsv]
set metadata_channel [open $metadata_file w]
puts $metadata_channel "commit\t[exec git -C $root_dir rev-parse HEAD]"
puts $metadata_channel "part\txc7z020clg400-2"
puts $metadata_channel "top\tPuf64_Ro_Microbench_Zynq_Top"
puts $metadata_channel "input_clock_hz\t50000000"
puts $metadata_channel "system_clock_hz\t100000000"
close $metadata_channel
close_project
