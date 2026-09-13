# Verify a routed Arty A7-35T full Edge checkpoint against the accepted RO
# physical fingerprint.  This checks fixed placement, LUT pins and all routes.

set_param general.maxThreads 1
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
set checkpoint [file join $root_dir build fpga_100mhz \
    edgefull_10ns_rolock_repro_a post_route.dcp]
set golden [file join $root_dir constraints \
    ro_physical_fingerprint_edge_arty35t_100mhz.tsv]
set actual [file join $root_dir build fpga_100mhz \
    edgefull_10ns_rolock_repro_a ro_physical_fingerprint.tsv]

if {[llength $argv] > 0} {
    set checkpoint [file normalize [lindex $argv 0]]
}
if {[llength $argv] > 1} {
    set actual [file normalize [lindex $argv 1]]
}
if {[llength $argv] > 2} {
    error "Usage: validate_ro_physical_lock_arty35t.tcl ?routed.dcp? ?actual.tsv?"
}
if {![file isfile $checkpoint]} {
    error "Routed checkpoint not found: $checkpoint"
}

source [file join $script_dir ro_physical_common.tcl]
file mkdir [file dirname $actual]
open_checkpoint $checkpoint
if {[get_property PART [current_design]] ne "xc7a35ticsg324-1L"} {
    error "Unexpected checkpoint part: [get_property PART [current_design]]"
}
set inventory [ro_collect_physical_inventory]
set endpoint_cells [dict get $inventory endpoint_cells]
set ro_nets [dict get $inventory ro_nets]
set puf_placed_cells [lsort -dictionary [get_cells -quiet -hierarchical \
    -filter {NAME =~ "u_puf/*" && IS_PRIMITIVE == 1 && LOC != "" && BEL != ""}]]
if {[llength $puf_placed_cells] != 1166} {
    error "Expected 1166 placed PUF primitives, found [llength $puf_placed_cells]"
}
foreach cell $puf_placed_cells {
    if {![get_property IS_LOC_FIXED $cell] ||
        ![get_property IS_BEL_FIXED $cell]} {
        error "PUF primitive placement is not fixed: $cell"
    }
}
if {[llength $endpoint_cells] != 136} {
    error "Expected 136 fixed endpoint cells, found [llength $endpoint_cells]"
}
foreach cell $endpoint_cells {
    if {![get_property IS_LOC_FIXED $cell] ||
        ![get_property IS_BEL_FIXED $cell]} {
        error "RO endpoint placement is not fixed: $cell"
    }
    if {[get_property LOCK_PINS $cell] eq ""} {
        error "RO endpoint input pins are not locked: $cell"
    }
}
foreach net $ro_nets {
    if {![get_property IS_ROUTE_FIXED $net]} {
        error "RO route is not fixed: $net"
    }
    if {[get_property FIXED_ROUTE $net] eq "" ||
        [get_property ROUTE $net] eq ""} {
        error "RO route is empty or only partially constrained: $net"
    }
    if {[ro_normalize_space [get_property FIXED_ROUTE $net]] ne
        [ro_normalize_space [get_property ROUTE $net]]} {
        error "Actual route differs from FIXED_ROUTE: $net"
    }
}
ro_write_physical_fingerprint $actual $inventory
ro_compare_physical_fingerprints $golden $actual
puts "RO_PHYSICAL_LOCK_AUDIT=PASS"
puts "PUF_FIXED_PRIMITIVE_COUNT=[llength $puf_placed_cells]"
puts "RO_FIXED_ENDPOINT_CELL_COUNT=[llength $endpoint_cells]"
puts "RO_FIXED_NET_COUNT=[llength $ro_nets]"
puts "RO_ARTY35T_LOCK_VALIDATION=PASS"
puts "RO_VALIDATED_CHECKPOINT=$checkpoint"
puts "RO_VALIDATED_FINGERPRINT=$actual"
close_design
