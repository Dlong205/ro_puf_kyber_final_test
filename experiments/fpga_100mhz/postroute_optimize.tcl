# Incremental post-route timing recovery for the full Arty A7-35T Edge core.
set_param general.maxThreads 1

if {[llength $argv] != 2} {
    error "usage: postroute_optimize.tcl <input-dcp> <absolute-output-directory>"
}
lassign $argv input_dcp out_dir
set input_dcp [file normalize $input_dcp]
set out_dir [file normalize $out_dir]
if {![file isfile $input_dcp]} {
    error "Checkpoint not found: $input_dcp"
}
file mkdir $out_dir

open_checkpoint $input_dcp
phys_opt_design -directive AggressiveExplore
route_design

report_route_status -file [file join $out_dir post_route_status.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
    -max_paths 20 -file [file join $out_dir post_route_timing.rpt]
report_drc -file [file join $out_dir post_route_drc.rpt]
write_checkpoint [file join $out_dir post_route_optimized.dcp]

set setup_path [get_timing_paths -quiet -delay_type max -max_paths 1]
set hold_path [get_timing_paths -quiet -delay_type min -max_paths 1]
set setup_slack [expr {[llength $setup_path] ? [get_property SLACK $setup_path] : {NA}}]
set hold_slack [expr {[llength $hold_path] ? [get_property SLACK $hold_path] : {NA}}]
set unrouted [get_nets -hier -quiet -filter {ROUTE_STATUS == UNROUTED}]
set partial [get_nets -hier -quiet -filter {ROUTE_STATUS == PARTIALLY_ROUTED}]

set fd [open [file join $out_dir result.tsv] w]
puts $fd "setup_slack_ns\t$setup_slack"
puts $fd "hold_slack_ns\t$hold_slack"
puts $fd "unrouted_nets\t[llength $unrouted]"
puts $fd "partially_routed_nets\t[llength $partial]"
close $fd
puts "POSTROUTE_OPT_RESULT setup_slack_ns=$setup_slack hold_slack_ns=$hold_slack unrouted=[llength $unrouted] partial=[llength $partial]"
close_project
