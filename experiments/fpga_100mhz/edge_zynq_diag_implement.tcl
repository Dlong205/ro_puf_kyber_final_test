# Full Edge diagnostic board image for XC7Z020 at an internal 100 MHz.
set_param general.maxThreads 1
set here [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $here ../..]]
source [file join $root_dir experiments fpga_split sources.tcl]

if {$argc != 1} {
    error "usage: edge_zynq_diag_implement.tcl <output-directory>"
}
set part xc7z020clg400-2
set out_dir [file normalize [lindex $argv 0]]
file mkdir $out_dir

create_project -in_memory -part $part
set_property target_language Verilog [current_project]
set_property include_dirs [fpga_split::includes] [current_fileset]
foreach path [fpga_split::sources edgefull] {
    if {[file extension $path] eq ".sv"} {read_verilog -sv $path} else {read_verilog $path}
}
foreach path [list \
        [file join $root_dir rtl puf uart_rx.v] \
        [file join $root_dir rtl puf uart_tx.v] \
        [file join $root_dir rtl top edge_uart_transport.sv] \
        [file join $root_dir rtl top Edge_Zynq_Diagnostic_100MHz_Top.sv]] {
    if {[file extension $path] eq ".sv"} {read_verilog -sv $path} else {read_verilog $path}
}
read_xdc [file join $root_dir constraints edge_zynq_diagnostic_100mhz.xdc]
synth_design -top Edge_Zynq_Diagnostic_100MHz_Top -part $part \
    -flatten_hierarchy rebuilt

if {[llength [get_cells -hier -quiet -filter {IS_BLACKBOX == 1}]] != 0} {
    error "Unresolved black boxes in Zynq diagnostic board image"
}
set ro_luts [get_cells -hier -quiet -filter {NAME =~ "*u_core/u_puf*ring*LUT6*"}]
set ro_loop_nets [get_nets -hier -quiet -filter {NAME =~ "*u_core/u_puf*ring*/t*"}]
if {[llength $ro_luts] != 128 || [llength $ro_loop_nets] != 128} {
    error "RO inventory mismatch: LUTs=[llength $ro_luts] nets=[llength $ro_loop_nets]"
}
set_property ALLOW_COMBINATORIAL_LOOPS true $ro_loop_nets
set_false_path -through $ro_loop_nets

# Reuse the accepted RC1 BEL/LOC map under the Edge hierarchy.  This fixes the
# physical oscillator cells without pretending that the old routes are valid
# for this new 100 MHz top.
set source_map [file join $root_dir constraints ro_placement_rc1_zynq7020.xdc]
set mapped_xdc [file join $out_dir ro_placement_edge_zynq7020.xdc]
set source_fd [open $source_map r]
set mapped_text [string map [list {"u_puf/} {"u_core/u_puf/}] [read $source_fd]]
close $source_fd
set mapped_fd [open $mapped_xdc w]
puts -nonewline $mapped_fd $mapped_text
close $mapped_fd
read_xdc $mapped_xdc

set mapped_ro_luts [get_cells -hier -quiet -filter {
    NAME =~ "*u_core/u_puf*ring*LUT6*" && LOC != "" && BEL != ""}]
if {[llength $mapped_ro_luts] != 128} {
    error "RO placement map resolved [llength $mapped_ro_luts]/128 LUTs"
}

report_utilization -file [file join $out_dir post_synth_utilization.rpt]
write_checkpoint [file join $out_dir post_synth.dcp]
opt_design
place_design
phys_opt_design
report_utilization -file [file join $out_dir post_place_utilization.rpt]
route_design
set setup_path [get_timing_paths -quiet -delay_type max -max_paths 1]
if {[llength $setup_path] && [get_property SLACK $setup_path] < 0.0} {
    phys_opt_design -directive AggressiveExplore
    route_design
}

set route_report [report_route_status -return_string]
if {![regexp {# of nets with routing errors[^:]*:[[:space:]]*([0-9]+)} \
        $route_report unused route_errors]} {
    error "Could not parse routing errors"
}
report_route_status -file [file join $out_dir post_route_status.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
    -max_paths 20 -file [file join $out_dir post_route_timing.rpt]
report_drc -file [file join $out_dir post_route_drc.rpt]
report_methodology -file [file join $out_dir post_route_methodology.rpt]
write_checkpoint [file join $out_dir post_route.dcp]
write_bitstream -force [file join $out_dir Edge_Zynq_Diagnostic_100MHz_Top.bit]

set setup_path [get_timing_paths -quiet -delay_type max -max_paths 1]
set hold_path [get_timing_paths -quiet -delay_type min -max_paths 1]
set setup_slack [expr {[llength $setup_path] ? [get_property SLACK $setup_path] : {NA}}]
set hold_slack [expr {[llength $hold_path] ? [get_property SLACK $hold_path] : {NA}}]
set sys_clocks [get_clocks -quiet -of_objects [get_pins u_clk_100_bufg/O]]
set fd [open [file join $out_dir result.tsv] w]
puts $fd "part\t$part"
puts $fd "input_clock_period_ns\t20.000"
puts $fd "core_clock_period_ns\t10.000"
puts $fd "core_clocks\t[join $sys_clocks ,]"
puts $fd "ro_luts\t[llength $ro_luts]"
puts $fd "ro_placed_luts\t[llength $mapped_ro_luts]"
puts $fd "ro_loop_nets\t[llength $ro_loop_nets]"
puts $fd "setup_slack_ns\t$setup_slack"
puts $fd "hold_slack_ns\t$hold_slack"
puts $fd "routing_errors\t$route_errors"
close $fd
puts "EDGE_ZYNQ_100MHZ_RESULT setup=$setup_slack hold=$hold_slack routing_errors=$route_errors"
if {$route_errors != 0 || $setup_slack < 0.0 || $hold_slack < 0.0} {
    error "100 MHz board image did not close timing/routing"
}
close_project
