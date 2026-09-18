# Export a complete physical lock for the RO paths of the isolated 64-RO
# all-pairs64 characterization image from an accepted routed checkpoint.
# Primary physical evidence is the exported fingerprint file (LOC/BEL,
# LOCK_PINS per endpoint and FIXED_ROUTE per net) and the fingerprint of any
# later build compared byte-for-byte against it.  The DCP/anchor hash below is
# only a build-traceability guard preventing a *different* implementation from
# silently rewriting the baseline; DCPs can carry volatile metadata and are not
# treated as physical evidence.
# This includes all 256 RO LUTs (64 rings x 4 LUTs), the measurement-mux/counter
# leaf cells they load, their LUT pin mappings, and all 256 routed loop nets.
#
# Bootstrap semantics: the anchor file
#   constraints/ro_physical_lock_allpairs64_zynq7020.expected
# stores "DCP_SHA <digest>".  On the first accepted implementation it is
# written (bootstrapping the baseline).  Any later build must reproduce that
# DCP hash exactly, otherwise the export is refused so an unapproved
# implementation can never silently replace the physical baseline.

set_param general.maxThreads 1
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
source [file join $script_dir ro_physical_common.tcl]

set checkpoint [file join $root_dir build puf_allpairs64_characterization \
    puf_allpairs64_zynq7020.runs impl_1 Puf_AllPairs64_Characterization_Top_routed.dcp]
set output_xdc [file join $root_dir constraints \
    ro_physical_lock_allpairs64_zynq7020.xdc]
set output_fingerprint [file join $root_dir constraints \
    ro_physical_fingerprint_allpairs64_zynq7020.tsv]
set anchor_file [file join $root_dir constraints \
    ro_physical_lock_allpairs64_zynq7020.expected]

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
    set anchor_file [file normalize [lindex $argv 3]]
}

if {![file exists $checkpoint]} {
    error "Routed all-pairs64 checkpoint not found: $checkpoint"
}
set checkpoint_sha256 [ro_sha256_file $checkpoint]

set anchor_dcp {}
if {[file exists $anchor_file]} {
    set anchor_channel [open $anchor_file r]
    while {[gets $anchor_channel line] >= 0} {
        if {[regexp {^DCP_SHA ([0-9a-f]{64})$} $line unused digest]} {
            set anchor_dcp $digest
        }
    }
    close $anchor_channel
    if {$anchor_dcp eq ""} {
        error "Malformed anchor file: $anchor_file"
    }
    if {$checkpoint_sha256 ne $anchor_dcp} {
        error "Refusing to export from an unapproved DCP: expected=$anchor_dcp actual=$checkpoint_sha256"
    }
} else {
    file mkdir [file dirname $anchor_file]
    set anchor_channel [open $anchor_file w]
    puts $anchor_channel "DCP_SHA $checkpoint_sha256"
    puts $anchor_channel [format {# Bootstrapped %s by export_ro_physical_lock_allpairs64.tcl} \
        [clock format [clock seconds] -gmt true -format "%Y-%m-%d %H:%M:%S UTC"]]
    close $anchor_channel
    puts "PUF_ALLPAIRS64_LOCK_BOOTSTRAP=1"
}

open_checkpoint $checkpoint
if {[get_property PART [current_design]] ne "xc7z020clg400-2"} {
    error "Unexpected checkpoint part: [get_property PART [current_design]]"
}
set inventory [ro_collect_physical_inventory]
set ro_nets [dict get $inventory ro_nets]
set endpoint_cells [dict get $inventory endpoint_cells]

file mkdir [file dirname $output_xdc]
set channel [open $output_xdc w]
puts $channel "## Complete RO physical lock for the all-pairs64 characterization image."
puts $channel "## Source DCP SHA-256: $checkpoint_sha256"
puts $channel "## Vivado 2020.1 build 2902540; part xc7z020clg400-2."
puts $channel "## BEL is applied before LOC. Every connected leaf cell is fixed before routes."

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
    # The board XDC already locks every RO LUT's six logical inputs to
    # A6..A1.  Emit LOCK_PINS only for the leaf endpoints that are outside the
    # RO-cell wildcard so Vivado does not report duplicate-property warnings.
    if {![string match "*u_puf*ring*LUT6*" $cell]} {
        puts $channel [format \
            {set_property LOCK_PINS %s %s} [list $pin_map] $cell_target]
    }
    puts $channel [format \
        {set_property DONT_TOUCH true %s} $cell_target]
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
puts "PUF_ALLPAIRS64_LOCK_ENDPOINT_CELL_COUNT=[llength $endpoint_cells]"
puts "PUF_ALLPAIRS64_LOCK_NET_COUNT=[llength $ro_nets]"
puts "PUF_ALLPAIRS64_LOCK_XDC=$output_xdc"
puts "PUF_ALLPAIRS64_LOCK_FINGERPRINT=$output_fingerprint"
puts "PUF_ALLPAIRS64_LOCK_DCP_SHA=$checkpoint_sha256"
close_design