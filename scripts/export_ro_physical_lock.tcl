# Export a complete physical lock for the RO paths from an accepted routed
# full-SoC checkpoint.  This includes all RO LUTs, the measurement-mux leaf
# loads reached by t3, their actual LUT pin mapping, and all 128 routed nets.

set_param general.maxThreads 1
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
source [file join $script_dir ro_physical_common.tcl]

set checkpoint [file join $root_dir build vivado \
    kyber_ro_puf_zynq7020.runs impl_1 Kyber_System_Top_routed.dcp]
set output_xdc [file join $root_dir constraints \
    ro_physical_lock_rc1_zynq7020.xdc]
set output_fingerprint [file join $root_dir constraints \
    ro_physical_fingerprint_rc1_zynq7020.tsv]
set source_bitstream [file join $root_dir Kyber_System_Top.bit]
set expected_checkpoint_sha256 \
    f843e5fa2daa7e0f5c14f776e34166618479dcb33c4e1d1293f7ca4145d401af
set expected_bitstream_sha256 \
    183e0af367376ebd7ca6bc2f3747314fd0602306a630af2a2e51858ef1f20e8e
if {[llength $argv] > 0} {
    set checkpoint [file normalize [lindex $argv 0]]
}
if {[llength $argv] > 1} {
    set output_xdc [file normalize [lindex $argv 1]]
}
if {[llength $argv] > 2} {
    set output_fingerprint [file normalize [lindex $argv 2]]
}
if {![file exists $checkpoint]} {
    error "Routed checkpoint not found: $checkpoint"
}
set checkpoint_sha256 [ro_sha256_file $checkpoint]
set bitstream_sha256 [ro_sha256_file $source_bitstream]
if {$checkpoint_sha256 ne $expected_checkpoint_sha256} {
    error "Refusing to export from an unapproved DCP: expected=$expected_checkpoint_sha256 actual=$checkpoint_sha256"
}
if {$bitstream_sha256 ne $expected_bitstream_sha256} {
    error "Accepted RC1 bitstream hash changed: expected=$expected_bitstream_sha256 actual=$bitstream_sha256"
}

open_checkpoint $checkpoint
if {[get_property PART [current_design]] ne "xc7z020clg400-2"} {
    error "Unexpected checkpoint part: [get_property PART [current_design]]"
}
set inventory [ro_collect_physical_inventory]
set ro_nets [dict get $inventory ro_nets]
set endpoint_cells [dict get $inventory endpoint_cells]
if {[llength $endpoint_cells] != 136} {
    error "RC1 endpoint closure changed: expected 136 cells, found [llength $endpoint_cells]"
}

file mkdir [file dirname $output_xdc]
set channel [open $output_xdc w]
puts $channel "## Complete RO physical lock exported from the accepted routed ML-KEM RC1."
puts $channel "## Source DCP SHA-256: $checkpoint_sha256"
puts $channel "## Source bitstream SHA-256: $bitstream_sha256"
puts $channel "## Vivado 2020.1 build 2902540; part xc7z020clg400-2."
puts $channel "## BEL is applied before LOC. Every connected leaf cell is fixed before routes."
puts $channel {## Four measurement-mux leaf LUTs have a Vivado-generated n_0_<number> stem.
## That number depends on unrelated full-SoC logic, so resolve those endpoints
## by their stable hierarchy and lane suffix and require exactly one match.
proc ro_require_generated_lfsr_mux_endpoint {lane} {
    if {$lane < 2 || $lane > 5} {
        error "Invalid generated LFSR mux endpoint lane: $lane"
    }
    set selector [format \
        {NAME =~ "u_puf/lfsr_inst/n_0_*_BUFG_inst_i_%d"} $lane]
    set cells [get_cells -quiet -hierarchical -filter $selector]
    if {[llength $cells] != 1} {
        error "Expected one generated LFSR mux endpoint for lane $lane, found $cells"
    }
    return [lindex $cells 0]
}
set ro_generated_lfsr_mux_i2 [ro_require_generated_lfsr_mux_endpoint 2]
set ro_generated_lfsr_mux_i3 [ro_require_generated_lfsr_mux_endpoint 3]
set ro_generated_lfsr_mux_i4 [ro_require_generated_lfsr_mux_endpoint 4]
set ro_generated_lfsr_mux_i5 [ro_require_generated_lfsr_mux_endpoint 5]}

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
    if {[regexp \
            {^u_puf/lfsr_inst/n_0_[0-9]+_BUFG_inst_i_([2-5])$} \
            $cell unused generated_lane]} {
        set cell_target [format {$ro_generated_lfsr_mux_i%d} $generated_lane]
    }
    puts $channel [format {set_property BEL %s %s} $bel $cell_target]
    puts $channel [format {set_property LOC %s %s} $loc $cell_target]
    # The board XDC already locks every RO LUT's six logical inputs to
    # A6..A1.  Repeating the same property in this late implementation-only
    # XDC is harmless, but Vivado 2020.1 reports one critical warning for
    # every placed LUT.  Emit LOCK_PINS here only for the eight mux leaf
    # endpoints that are outside the RO-cell wildcard in the board XDC.
    if {![string match "*u_puf*ring*LUT6*" $cell]} {
        puts $channel [format \
            {set_property LOCK_PINS %s %s} [list $pin_map] $cell_target]
    }
    puts $channel [format \
        {set_property DONT_TOUCH true %s} $cell_target]
}
puts $channel {unset ro_generated_lfsr_mux_i2
unset ro_generated_lfsr_mux_i3
unset ro_generated_lfsr_mux_i4
unset ro_generated_lfsr_mux_i5}

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
puts "RO_LOCK_XDC=$output_xdc"
puts "RO_LOCK_FINGERPRINT=$output_fingerprint"
close_design
