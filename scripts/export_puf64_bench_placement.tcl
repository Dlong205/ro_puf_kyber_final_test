# Export the accepted C2 bench placement (LOC/BEL), LOCK_PINS (RO LUTs) and a
# narrow FIXED_ROUTE on the RO->prescaler tap nets.
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
set checkpoint [file join $root_dir build puf64_bench \
    puf64_bench_zynq7020.runs impl_1 puf64_bench_top_routed.dcp]
set num_ro 4
if {[llength $argv] > 1} { set num_ro [lindex $argv 1] }
set out_place [file join $root_dir constraints puf64_bench_placement_n${num_ro}.xdc]
set out_pins [file join $root_dir constraints puf64_bench_lockpins_n${num_ro}.xdc]
set out_route [file join $root_dir constraints puf64_bench_route_n${num_ro}.xdc]
if {[llength $argv] > 0} { set checkpoint [file normalize [lindex $argv 0]] }
if {![file exists $checkpoint]} { error "bench routed checkpoint missing: $checkpoint" }
source [file join $script_dir ro_physical_common.tcl]

open_checkpoint $checkpoint
set ro_luts [get_cells -quiet -hierarchical -filter {NAME =~ "*u_bench*ro_cell*/u_backend/LUT6_*"}]
set presc [get_cells -quiet -hierarchical -filter {NAME =~ "*presc_fdce" && REF_NAME == "FDCE"}]
set stages [get_cells -quiet -hierarchical -filter {REF_NAME == "FDCE" && NAME =~ "*stage*ff*"}]
set cells [concat $ro_luts $presc $stages]

set ch [open $out_place w]
puts $ch "## C2 bench placement (LOC/BEL) from the accepted auto-place implementation."
foreach cell $cells {
    set bel [get_property BEL $cell]
    set loc [get_property LOC $cell]
    if {$bel eq "" || $loc eq ""} { close $ch; error "missing BEL/LOC for $cell" }
    set target [format {[get_cells -hierarchical -filter {NAME == "%s"}]} $cell]
    puts $ch [format {set_property BEL %s %s} $bel $target]
    puts $ch [format {set_property LOC %s %s} $loc $target]
}
close $ch

set ch [open $out_pins w]
puts $ch "## C2 bench LOCK_PINS for the RO LUTs."
foreach cell $ro_luts {
    set pin_map [ro_lock_input_pin_map $cell]
    if {[llength $pin_map] == 0} { close $ch; error "no pin map for $cell" }
    set target [format {[get_cells -hierarchical -filter {NAME == "%s"}]} $cell]
    puts $ch [format {set_property LOCK_PINS %s %s} [list $pin_map] $target]
}
close $ch

set ch [open $out_route w]
puts $ch "## C2 narrow FIXED_ROUTE for each RO tap net."
foreach p $presc {
    set cpin [get_pins -quiet -of_objects $p -filter {REF_PIN_NAME == "C"}]
    set net [lindex [get_nets -quiet -of_objects $cpin] 0]
    set route [get_property ROUTE $net]
    if {$route eq ""} { close $ch; error "tap net not routed: $net" }
    puts $ch [format {set_property FIXED_ROUTE %s [get_nets -hierarchical -filter {NAME == "%s"}]} [list $route] $net]
    puts $ch [format {set_property IS_ROUTE_FIXED true [get_nets -hierarchical -filter {NAME == "%s"}]} $net]
}
close $ch
puts "PUF64_BENCH_EXPORT cells=[llength $cells] ro_luts=[llength $ro_luts] presc=[llength $presc] stages=[llength $stages]"
close_design
