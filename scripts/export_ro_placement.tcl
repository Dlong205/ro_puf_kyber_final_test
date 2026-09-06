# Export LOC/BEL constraints for every physical RO LUT in an implemented
# checkpoint.  Output is written to stdout so callers can review it before
# adding a placement map to source control.

set_param general.maxThreads 1
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
set checkpoint [file join $root_dir build vivado kyber_ro_puf_zynq7020.runs impl_1 Kyber_System_Top_routed.dcp]

if {![file exists $checkpoint]} {
    error "Implemented checkpoint not found: $checkpoint"
}

open_checkpoint $checkpoint
set ro_luts [lsort [get_cells -quiet -hierarchical -filter {NAME =~ "*u_puf*ring*LUT6*"}]]

puts "RO_PLACEMENT_CELL_COUNT=[llength $ro_luts]"
if {[llength $ro_luts] != 128} {
    error "Expected exactly 128 RO LUTs"
}
foreach cell $ro_luts {
    set loc [get_property LOC $cell]
    set bel [get_property BEL $cell]
    if {$loc eq "" || $bel eq ""} {
        error "RO LUT is not fully placed: $cell LOC=$loc BEL=$bel"
    }
    puts [format {set_property BEL %s [get_cells -hierarchical -filter {NAME == "%s"}]} $bel $cell]
    puts [format {set_property LOC %s [get_cells -hierarchical -filter {NAME == "%s"}]} $loc $cell]
}
close_design
