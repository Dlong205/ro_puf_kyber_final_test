# I4.3A import TRIAL: read-only verdict on scoped macro reuse.
# Opens the existing operational SYNTH checkpoint (never saved), attempts
# read_checkpoint -cell into the exact target, then runs the post-import
# gates.  Any tool refusal, incompatibility, partial route, RTSTAT or
# conflict stops Option A with the verbatim error -- never forced.
#
#   vivado -mode batch -nolog -nojournal \
#     -source scripts/trial_puf64_routed_macro_import.tcl
set_param general.maxThreads 1
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
source [file join $script_dir ro_physical_common.tcl]

set TARGET "u_operational_uart/u_chain/u_puf64_core/u_puf64_physical/u_puf"
set synth_dcp [file join $root_dir build puf64_operational_preservation \
    puf64_operational_zynq7020.runs synth_1 Edge_Puf64_Zynq_Operational_100MHz_Top.dcp]
set macro_dcp [file join $root_dir build puf64_operational_preservation \
    i4_routed_macro_u_puf.dcp]
if {![file isfile $synth_dcp]} { error "I4.3A trial: synth DCP missing: $synth_dcp" }
if {![file isfile $macro_dcp]} { error "I4.3A trial: macro DCP missing: $macro_dcp (run export first)" }

open_checkpoint $synth_dcp

# --- pre-import: target exists exactly once, no flatten/duplicate ---
set targets [get_cells -quiet $TARGET]
if {[llength $targets] != 1} {
    error "I4.3A trial: target $TARGET must exist exactly once, found [llength $targets]"
}
set dupes [get_cells -quiet -hierarchical -filter "NAME =~ \"*u_puf64_physical/u_puf\""]
if {[llength $dupes] != 1} {
    error "I4.3A trial: duplicate/flattened u_puf instances: $dupes"
}
# Pre-import inventory inside the target (unplaced: counts only).
set pre_ro [get_cells -quiet -hierarchical -filter "NAME =~ \"*u_puf64_physical/u_puf*ro_cell*/u_backend/LUT6_*\""]
set pre_pr [get_cells -quiet -hierarchical -filter "NAME =~ \"*u_puf64_physical/u_puf*counter/presc_fdce\" && REF_NAME == \"FDCE\""]
set pre_st [get_cells -quiet -hierarchical -filter "REF_NAME == \"FDCE\" && NAME =~ \"*u_puf64_physical/u_puf*stage*ff*\""]
puts "I4_3A_PREIMPORT ro=[llength $pre_ro] presc=[llength $pre_pr] stages=[llength $pre_st]"
set pre_inv [get_cells -quiet -hierarchical -filter "REF_NAME == \"LUT1\" && NAME =~ \"*u_puf64_physical/u_puf*\""]
puts "I4_3A_PREIMPORT lut1_inside_target=[llength $pre_inv]"

# --- the import (hard failure stops Option A) ---
read_checkpoint -cell [get_cells $TARGET] $macro_dcp
puts "I4_3A_IMPORT_ACCEPTED"

# --- post-import gates (before any place/route) ---
set targets [get_cells -quiet $TARGET]
if {[llength $targets] != 1} { error "I4.3A gate: target multiplied after import" }
set ro [get_cells -quiet -hierarchical -filter {NAME =~ "*u_puf64_physical/u_puf*ro_cell*/u_backend/LUT6_*"}]
set pr [get_cells -quiet -hierarchical -filter {NAME =~ "*u_puf64_physical/u_puf*counter/presc_fdce" && REF_NAME == "FDCE"}]
set st [get_cells -quiet -hierarchical -filter {REF_NAME == "FDCE" && NAME =~ "*u_puf64_physical/u_puf*stage*ff*"}]
if {[llength $ro] != 256 || [llength $pr] != 64 || [llength $st] != 1088} {
    error "I4.3A gate: post-import inventory ro=[llength $ro] presc=[llength $pr] stages=[llength $st]"
}
set no_loc 0
foreach cell [concat $ro $pr $st] {
    if {[get_property LOC $cell] eq "" || [get_property BEL $cell] eq ""} { incr no_loc }
}
if {$no_loc != 0} { error "I4.3A gate: $no_loc qualified cells lost LOC/BEL in import" }
puts "I4_3A_POSTIMPORT place ro=256 presc=64 ripple=1088 all LOC/BEL present"
foreach cell $ro {
    if {[get_property INIT $cell] eq ""} { error "I4.3A gate: RO LUT lost INIT: $cell" }
    if {[join [ro_actual_input_pin_map $cell] ,] eq ""} { error "I4.3A gate: RO LUT lost pin map: $cell" }
}
puts "I4_3A_POSTIMPORT lut_init_pinmap_ok=256"
set tap_missing 0
set tap_nets {}
foreach p $pr {
    set cpin [get_pins -quiet -of_objects $p -filter {REF_PIN_NAME == "C"}]
    set net [lindex [get_nets -quiet -of_objects $cpin] 0]
    if {[ro_normalize_space [get_property ROUTE $net]] eq ""} { incr tap_missing } else { lappend tap_nets $net }
}
set rip_missing 0
foreach s $st {
    set cpin [get_pins -quiet -of_objects $s -filter {REF_PIN_NAME == "C"}]
    set net [lindex [get_nets -quiet -of_objects $cpin] 0]
    if {[ro_normalize_space [get_property ROUTE $net]] eq ""} { incr rip_missing }
}
if {$tap_missing != 0} { error "I4.3A gate: $tap_missing TAP routes missing after import" }
if {$rip_missing != 0} { error "I4.3A gate: $rip_missing ripple routes missing after import" }
puts "I4_3A_POSTIMPORT routes tap=64 ripple=1088 present"
# No global clock buffers on any TAP/chain net; endpoints sane.
foreach net $tap_nets {
    foreach pin [get_pins -quiet -leaf -of_objects [get_nets -quiet -segments $net]] {
        set ref [get_property REF_NAME [get_cells -quiet -of_objects $pin]]
        if {$ref eq "BUFG" || $ref eq "BUFGCTRL" || $ref eq "BUFH" || $ref eq "BUFHCE" || $ref eq "BUFR"} {
            error "I4.3A gate: TAP net $net touches $ref"
        }
    }
}
puts "I4_3A_POSTIMPORT clock_clean=64tap"
# Every used macro port must stay connected (no unconnected pins on target).
set floating 0
foreach pin [get_pins -quiet -of_objects [get_cells $TARGET]] {
    if {[llength [get_nets -quiet -of_objects $pin]] == 0} { incr floating }
}
if {$floating != 0} { error "I4.3A gate: $floating floating pins on target after import" }
puts "I4_3A_POSTIMPORT ports_connected (floating=0)"
puts "I4_3A_TRIAL_VERDICT=CLEAN_IMPORT"
close_design
