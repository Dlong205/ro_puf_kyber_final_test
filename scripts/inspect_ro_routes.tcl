# Inspect the physical nets driven by the final LUT of every ring oscillator.
# This is intentionally read-only and is useful before attempting to lock
# routing: the final RO stage also drives the measurement mux, so every sink
# connected to that physical net must be understood first.

set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
set checkpoint [file join $root_dir build vivado \
    kyber_ro_puf_zynq7020.runs impl_1 Kyber_System_Top_routed.dcp]
if {[llength $argv] > 0} {
    set checkpoint [file normalize [lindex $argv 0]]
}
if {![file exists $checkpoint]} {
    error "Routed checkpoint not found: $checkpoint"
}

open_checkpoint $checkpoint

set final_luts [lsort -dictionary [get_cells -quiet -hierarchical \
    -filter {NAME =~ "*u_puf*ring*LUT6_INV2"}]]
puts "RO_FINAL_LUT_COUNT=[llength $final_luts]"
if {[llength $final_luts] != 32} {
    error "Expected 32 final RO LUTs, found [llength $final_luts]"
}

set unique_nets [dict create]
foreach cell $final_luts {
    set output_pins [get_pins -quiet -of_objects $cell -filter {DIRECTION == OUT}]
    if {[llength $output_pins] != 1} {
        error "Expected one output pin on $cell, found [llength $output_pins]"
    }

    set segments [get_nets -quiet -segments -of_objects $output_pins]
    if {[llength $segments] == 0} {
        error "No routed net segment found for $cell"
    }

    # ROUTE is held by one segment in a hierarchical physical-net group.
    set route_net ""
    foreach segment $segments {
        if {[get_property ROUTE $segment] ne ""} {
            set route_net $segment
            break
        }
    }
    if {$route_net eq ""} {
        error "No ROUTE-bearing segment found for $cell: $segments"
    }

    dict set unique_nets $route_net 1
    set sink_pins [get_pins -quiet -leaf -of_objects \
        [get_nets -quiet -segments $route_net] -filter {DIRECTION == IN}]
    set sink_cells [lsort -unique -dictionary \
        [get_cells -quiet -of_objects $sink_pins]]
    puts "RO_ROUTE cell=$cell net=$route_net segments=[llength $segments] sinks=[llength $sink_pins] route_fixed=[get_property IS_ROUTE_FIXED $route_net]"
    puts "RO_SINK_CELLS net=$route_net cells=$sink_cells"
    puts "RO_ROUTE_VALUE net=$route_net route=[get_property ROUTE $route_net]"
}

puts "RO_UNIQUE_FINAL_NET_COUNT=[dict size $unique_nets]"
close_design
