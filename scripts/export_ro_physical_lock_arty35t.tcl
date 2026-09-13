# Export the RO placement, LUT pin mapping and routed nets from the accepted
# 100 MHz full Edge checkpoint for Arty A7-35T.  The source hash prevents an
# accidental re-baseline from an unreviewed implementation.

set_param general.maxThreads 1
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
source [file join $script_dir ro_physical_common.tcl]

set checkpoint [file join $root_dir build fpga_100mhz \
    edgefull_10ns_syncscrub_v06 post_route.dcp]
set output_xdc [file join $root_dir constraints \
    ro_physical_lock_edge_arty35t_100mhz.xdc]
set output_fingerprint [file join $root_dir constraints \
    ro_physical_fingerprint_edge_arty35t_100mhz.tsv]
set expected_checkpoint_sha256 \
    bd71aaa172ef7b4f78176de1716ece3ff9c23c5749324d9a04a402c460d6b2cb

if {[llength $argv] > 0} {
    set checkpoint [file normalize [lindex $argv 0]]
}
if {[llength $argv] > 1} {
    set output_xdc [file normalize [lindex $argv 1]]
}
if {[llength $argv] > 2} {
    set output_fingerprint [file normalize [lindex $argv 2]]
}
if {[llength $argv] > 3} {
    error "Usage: export_ro_physical_lock_arty35t.tcl ?routed.dcp? ?output.xdc? ?fingerprint.tsv?"
}
if {![file isfile $checkpoint]} {
    error "Routed checkpoint not found: $checkpoint"
}
set checkpoint_sha256 [ro_sha256_file $checkpoint]
if {$checkpoint_sha256 ne $expected_checkpoint_sha256} {
    error "Refusing unapproved DCP: expected=$expected_checkpoint_sha256 actual=$checkpoint_sha256"
}

open_checkpoint $checkpoint
if {[get_property PART [current_design]] ne "xc7a35ticsg324-1L"} {
    error "Unexpected checkpoint part: [get_property PART [current_design]]"
}
set inventory [ro_collect_physical_inventory]
set ro_nets [dict get $inventory ro_nets]
set endpoint_cells [dict get $inventory endpoint_cells]
if {[llength $endpoint_cells] != 136} {
    error "Expected 136 RO endpoint cells, found [llength $endpoint_cells]"
}

file mkdir [file dirname $output_xdc]
set channel [open $output_xdc w]
puts $channel "## Full Edge RO physical lock for Arty A7-35T at 100 MHz."
puts $channel "## Source DCP SHA-256: $checkpoint_sha256"
puts $channel "## Vivado 2020.1 build 2902540; part xc7a35ticsg324-1L."
puts $channel "## Apply only to edge_puf_mlkem_core with the same rebuilt hierarchy."
puts $channel "## The complete PUF leaf placement, endpoint pins and all 128 RO routes are fixed."

# In a nearly full A7-35T, fixing only the RO endpoints allows the placer to
# move PUF control/shift registers into locations that can be blocked by the
# accepted RO routes.  Preserve every placed PUF leaf so the physical PUF is
# treated as one reproducible island.  Endpoint cells are emitted below with
# their additional LOCK_PINS constraints.
set endpoint_set [dict create]
foreach cell $endpoint_cells {
    dict set endpoint_set $cell 1
}
set puf_placed_cells {}
foreach cell [lsort -dictionary [get_cells -quiet -hierarchical \
        -filter {NAME =~ "u_puf/*" && IS_PRIMITIVE == 1}]] {
    set bel [get_property BEL $cell]
    set loc [get_property LOC $cell]
    if {$bel eq "" || $loc eq ""} {
        continue
    }
    lappend puf_placed_cells $cell
    if {[dict exists $endpoint_set $cell]} {
        continue
    }
    set cell_target [format \
        {[get_cells -hierarchical -filter {NAME == "%s"}]} $cell]
    puts $channel [format {set_property BEL %s %s} $bel $cell_target]
    puts $channel [format {set_property LOC %s %s} $loc $cell_target]
    puts $channel [format {set_property DONT_TOUCH true %s} $cell_target]
}

foreach cell $endpoint_cells {
    set bel [get_property BEL $cell]
    set loc [get_property LOC $cell]
    set pin_map [ro_lock_input_pin_map $cell]
    if {$bel eq "" || $loc eq "" || [llength $pin_map] == 0} {
        close $channel
        error "Incomplete endpoint constraint for $cell"
    }
    set cell_target [format \
        {[get_cells -hierarchical -filter {NAME == "%s"}]} $cell]
    puts $channel [format {set_property BEL %s %s} $bel $cell_target]
    puts $channel [format {set_property LOC %s %s} $loc $cell_target]
    puts $channel [format \
        {set_property LOCK_PINS %s %s} [list $pin_map] $cell_target]
    puts $channel [format {set_property DONT_TOUCH true %s} $cell_target]
}

foreach net $ro_nets {
    set route [get_property ROUTE $net]
    if {$route eq ""} {
        close $channel
        error "Cannot export empty route for $net"
    }
    puts $channel [format \
        {set_property FIXED_ROUTE %s [get_nets -hierarchical -filter {NAME == "%s"}]} \
        [list $route] $net]
    puts $channel [format \
        {set_property IS_ROUTE_FIXED true [get_nets -hierarchical -filter {NAME == "%s"}]} \
        $net]
}
close $channel

ro_write_physical_fingerprint $output_fingerprint $inventory
puts "RO_LOCK_ENDPOINT_CELL_COUNT=[llength $endpoint_cells]"
puts "RO_LOCK_NET_COUNT=[llength $ro_nets]"
puts "PUF_LOCK_PLACED_CELL_COUNT=[llength $puf_placed_cells]"
puts "RO_LOCK_XDC=$output_xdc"
puts "RO_LOCK_FINGERPRINT=$output_fingerprint"
close_design
