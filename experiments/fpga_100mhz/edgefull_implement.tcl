# Full Edge 100 MHz feasibility experiment for Arty A7-35T.
# This is deliberately separate from the accepted 50 MHz OOC evidence flow.
set_param general.maxThreads 1
set here [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $here ../..]]
source [file join $root_dir experiments fpga_split sources.tcl]

if {[llength $argv] < 2 || [llength $argv] > 3} {
    error "usage: edgefull_implement.tcl <part> <absolute-output-directory> ?ro-lock.xdc?"
}
lassign $argv part out_dir ro_lock_xdc
if {![regexp {^xc7[A-Za-z0-9-]+$} $part] ||
    [llength [get_parts -quiet $part]] != 1} {
    error "Invalid or unavailable part: $part"
}
set out_dir [file normalize $out_dir]
file mkdir $out_dir

create_project -in_memory -part $part
set_property target_language Verilog [current_project]
set_property include_dirs [fpga_split::includes] [current_fileset]
foreach path [fpga_split::sources edgefull] {
    if {[file extension $path] eq ".sv"} {
        read_verilog -sv $path
    } else {
        read_verilog $path
    }
}
read_xdc [file join $here clock_100mhz.xdc]
synth_design -mode out_of_context -top [fpga_split::top edgefull] \
    -part $part -flatten_hierarchy rebuilt

# A complete RO lock is an implementation constraint and therefore resolves
# only after synthesis has rebuilt the hierarchy.  Keep it optional so the
# unconstrained feasibility baseline remains reproducible.
if {[llength $argv] == 3} {
    set ro_lock_xdc [file normalize $ro_lock_xdc]
    if {![file isfile $ro_lock_xdc]} {
        error "RO physical lock not found: $ro_lock_xdc"
    }
    read_xdc $ro_lock_xdc
}

if {[llength [get_cells -hier -quiet -filter {IS_BLACKBOX == 1}]] != 0} {
    error "Unresolved black boxes in Edge design"
}
set ro_luts [get_cells -hier -quiet -filter {NAME =~ "*ring*LUT6*"}]
if {[llength $ro_luts] != 128} {
    error "Expected 128 physical RO LUTs, got [llength $ro_luts]"
}
set ro_loop_nets [get_nets -hier -quiet -filter {NAME =~ "*u_puf*ring*/t*"}]
if {[llength $ro_loop_nets] != 128} {
    error "Expected 128 RO loop nets, got [llength $ro_loop_nets]"
}
set_property ALLOW_COMBINATORIAL_LOOPS true $ro_loop_nets
set_false_path -through $ro_loop_nets

report_utilization -file [file join $out_dir post_synth_utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
    -file [file join $out_dir post_synth_timing.rpt]
write_checkpoint [file join $out_dir post_synth.dcp]

opt_design
place_design
phys_opt_design
report_utilization -file [file join $out_dir post_place_utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
    -file [file join $out_dir post_place_timing.rpt]
write_checkpoint [file join $out_dir post_place.dcp]

route_design
# At >92% LUT utilization the first legal route can miss 10 ns by a small
# routing margin.  Let Vivado optimize only when timing is still negative,
# then restore any affected routes before producing sign-off reports.
set initial_setup_path [get_timing_paths -quiet -delay_type max -max_paths 1]
if {[llength $initial_setup_path] &&
    [get_property SLACK $initial_setup_path] < 0.0} {
    phys_opt_design -directive AggressiveExplore
    route_design
}
set route_report [report_route_status -return_string]
if {![regexp {# of nets with routing errors[^:]*:[[:space:]]*([0-9]+)} \
        $route_report unused route_errors]} {
    error "Could not parse routing-error count"
}
report_route_status -file [file join $out_dir post_route_status.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
    -max_paths 20 -file [file join $out_dir post_route_timing.rpt]
report_drc -file [file join $out_dir post_route_drc.rpt]
report_methodology -file [file join $out_dir post_route_methodology.rpt]
write_checkpoint [file join $out_dir post_route.dcp]

set setup_path [get_timing_paths -quiet -delay_type max -max_paths 1]
set hold_path [get_timing_paths -quiet -delay_type min -max_paths 1]
set setup_slack [expr {[llength $setup_path] ? [get_property SLACK $setup_path] : {NA}}]
set hold_slack [expr {[llength $hold_path] ? [get_property SLACK $hold_path] : {NA}}]
set unrouted [get_nets -hier -quiet -filter {ROUTE_STATUS == UNROUTED}]
set partial [get_nets -hier -quiet -filter {ROUTE_STATUS == PARTIALLY_ROUTED}]

set fd [open [file join $out_dir result.tsv] w]
puts $fd "part\t$part"
puts $fd "clock_period_ns\t10.000"
puts $fd "ro_luts\t[llength $ro_luts]"
puts $fd "ro_loop_nets\t[llength $ro_loop_nets]"
puts $fd "setup_slack_ns\t$setup_slack"
puts $fd "hold_slack_ns\t$hold_slack"
puts $fd "unrouted_nets\t[llength $unrouted]"
puts $fd "partially_routed_nets\t[llength $partial]"
puts $fd "routing_errors\t$route_errors"
close $fd
puts "EDGE_100MHZ_RESULT setup_slack_ns=$setup_slack hold_slack_ns=$hold_slack unrouted=[llength $unrouted] partial=[llength $partial] routing_errors=$route_errors"
if {$route_errors != 0} {
    error "Implementation has $route_errors routing error(s)"
}
close_project
