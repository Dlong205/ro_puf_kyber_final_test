# B2: export the exact LOC/BEL (and actual input pin map) of the RO LUTs and
# the prescaler FDCE from the accepted B1 implementation.
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
set checkpoint [file join $root_dir build puf64_microbench \
    puf64_microbench_zynq7020.runs impl_1 Puf64_Ro_Microbench_Zynq_Top_routed.dcp]
set output_xdc [file join $root_dir constraints puf64_microbench_placement.xdc]
set output_pins [file join $root_dir constraints puf64_microbench_lockpins.xdc]
if {[llength $argv] > 0} { set checkpoint [file normalize [lindex $argv 0]] }
if {[llength $argv] > 1} { set output_xdc [file normalize [lindex $argv 1]] }
if {![file exists $checkpoint]} { error "B1 routed checkpoint missing: $checkpoint" }
source [file join $script_dir ro_physical_common.tcl]

open_checkpoint $checkpoint
set cells [list]
foreach c [get_cells -quiet -hierarchical -filter {NAME =~ "*u_bench*ro0*/LUT6_*"}] {
    lappend cells $c
}
set ro_luts $cells
set presc [get_cells -quiet -hierarchical -filter {REF_NAME == "FDCE" && DONT_TOUCH == 1}]
if {[llength $presc] != 1} { error "expected one prescaler FDCE" }
lappend cells [lindex $presc 0]

set channel [open $output_xdc w]
puts $channel "## B2 placement export (LOC/BEL only) from the accepted B1 implementation."
foreach cell $cells {
    set bel [get_property BEL $cell]
    set loc [get_property LOC $cell]
    if {$bel eq "" || $loc eq ""} { close $channel; error "missing BEL/LOC for $cell" }
    set target [format {[get_cells -hierarchical -filter {NAME == "%s"}]} $cell]
    puts $channel [format {set_property BEL %s %s} $bel $target]
    puts $channel [format {set_property LOC %s %s} $loc $target]
}
close $channel

set channel [open $output_pins w]
puts $channel "## B4 LOCK_PINS export from the accepted implementation (RO LUTs only)."
foreach cell $ro_luts {
    set pin_map [ro_lock_input_pin_map $cell]
    if {[llength $pin_map] == 0} { close $channel; error "no pin map for $cell" }
    set target [format {[get_cells -hierarchical -filter {NAME == "%s"}]} $cell]
    puts $channel [format {set_property LOCK_PINS %s %s} [list $pin_map] $target]
}
close $channel
puts "PUF64_MICROBENCH_PLACEMENT_CELLS=[llength $cells]"
puts "PUF64_MICROBENCH_PLACEMENT_XDC=$output_xdc"
puts "PUF64_MICROBENCH_LOCKPINS_XDC=$output_pins"

set output_route [file join $root_dir constraints puf64_microbench_route.xdc]
set presc_c [get_pins -quiet -of_objects [lindex $presc 0] -filter {REF_PIN_NAME == "C"}]
set tap_net [lindex [get_nets -quiet -of_objects $presc_c] 0]
set route [get_property ROUTE $tap_net]
if {$route eq ""} { error "tap net is not routed" }
set channel [open $output_route w]
puts $channel "## B5 narrow route lock for the RO->prescaler tap net only."
puts $channel [format \
    {set_property FIXED_ROUTE %s [get_nets -hierarchical -filter {NAME == "%s"}]} \
    [list $route] $tap_net]
puts $channel [format \
    {set_property IS_ROUTE_FIXED true [get_nets -hierarchical -filter {NAME == "%s"}]} \
    $tap_net]
close $channel
puts "PUF64_MICROBENCH_ROUTE_NET=$tap_net"
puts "PUF64_MICROBENCH_ROUTE_XDC=$output_route"
close_design
