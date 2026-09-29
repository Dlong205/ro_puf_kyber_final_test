# I4.3A: export the golden routed macro (u_puf) as a scoped checkpoint.
# Source of truth is ONLY the golden routed DCP (SHA pinned); the candidate
# DCP c4e7ea08... must never be used here.  Run under Vivado 2020.1:
#
#   vivado -mode batch -nolog -nojournal \
#     -source scripts/export_puf64_routed_macro.tcl
#
# If Vivado refuses the scoped export, this script fails hard with the tool's
# verbatim error: Option A stops, no forced import is attempted.
set_param general.maxThreads 1
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
source [file join $script_dir ro_physical_common.tcl]

set GOLDEN_DCP_SHA "febefcc7129fdf42aae7c3be55875ed61f8cfb72562bbe8830d514628b2788e0"
set GOLDEN_CELL "u_puf"
set golden_dcp [file join $root_dir build puf_allpairs64_characterization \
    puf_allpairs64_zynq7020.runs impl_1 Puf_AllPairs64_Characterization_Top_routed.dcp]
set out_dir [file join $root_dir build puf64_operational_preservation]
set macro_dcp [file join $out_dir i4_routed_macro_u_puf.dcp]
set manifest [file join $out_dir i4_routed_macro_manifest.tsv]

set actual_sha [ro_sha256_file $golden_dcp]
if {$actual_sha ne $GOLDEN_DCP_SHA} {
    error "I4.3A gate: golden DCP hash mismatch: expected=$GOLDEN_DCP_SHA actual=$actual_sha"
}
puts "I4_3A_GOLDEN_DCP_SHA_OK=$actual_sha"

open_checkpoint $golden_dcp

# --- census inside the golden macro cell ---
set macro_cells [get_cells -quiet $GOLDEN_CELL]
if {[llength $macro_cells] != 1} {
    error "I4.3A gate: golden cell $GOLDEN_CELL must exist exactly once, found [llength $macro_cells]"
}
set ro_luts [get_cells -quiet -hierarchical \
    -filter "NAME =~ \"*${GOLDEN_CELL}*ro_cell*/u_backend/LUT6_*\""]
set presc [get_cells -quiet -hierarchical \
    -filter "NAME =~ \"*${GOLDEN_CELL}*counter/presc_fdce\" && REF_NAME == \"FDCE\""]
set stages [get_cells -quiet -hierarchical \
    -filter "REF_NAME == \"FDCE\" && NAME =~ \"*${GOLDEN_CELL}*stage*ff*\""]
if {[llength $ro_luts] != 256} { error "I4.3A gate: expected 256 RO LUTs in $GOLDEN_CELL, found [llength $ro_luts]" }
if {[llength $presc] != 64} { error "I4.3A gate: expected 64 prescalers in $GOLDEN_CELL, found [llength $presc]" }
if {[llength $stages] != 1088} { error "I4.3A gate: expected 1088 ripple stages in $GOLDEN_CELL, found [llength $stages]" }
puts "I4_3A_GOLDEN_INVENTORY ro=256 presc=64 ripple=1088"

# --- ripple-chain inversion LUT1s: census (they may sit outside the macro) ---
set lut1_inside 0
set lut1_outside 0
set chain_missing 0
set tap_missing 0
set lut1_records {}
foreach s [lsort -dictionary $stages] {
    set cpin [get_pins -quiet -of_objects $s -filter {REF_PIN_NAME == "C"}]
    set net [lindex [get_nets -quiet -of_objects $cpin] 0]
    if {[ro_normalize_space [get_property ROUTE $net]] eq ""} { incr chain_missing }
    set drvpin ""
    foreach pin [get_pins -quiet -leaf -of_objects [get_nets -quiet -segments $net]] {
        if {[get_property DIRECTION $pin] eq "OUT"} { set drvpin $pin }
    }
    set drvcell [get_cells -quiet -of_objects $drvpin]
    if {[get_property REF_NAME $drvcell] ne "LUT1"} {
        error "I4.3A gate: chain driver is not LUT1: $drvpin ([get_property REF_NAME $drvcell])"
    }
    if {[string first "${GOLDEN_CELL}/" $drvcell] >= 0} { incr lut1_inside } else { incr lut1_outside }
    lappend lut1_records "$drvcell\t[get_property LOC $drvcell]\t[get_property BEL $drvcell]\t[get_property INIT $drvcell]"
}
foreach p [lsort -dictionary $presc] {
    set cpin [get_pins -quiet -of_objects $p -filter {REF_PIN_NAME == "C"}]
    set net [lindex [get_nets -quiet -of_objects $cpin] 0]
    if {[ro_normalize_space [get_property ROUTE $net]] eq ""} { incr tap_missing }
}
if {$chain_missing != 0} { error "I4.3A gate: $chain_missing ripple routes missing in golden macro" }
if {$tap_missing != 0} { error "I4.3A gate: $tap_missing TAP routes missing in golden macro" }
puts "I4_3A_GOLDEN_ROUTES tap=64 ripple=1088"
puts "I4_3A_GOLDEN_LUT1 chain_inverters=[llength $lut1_records] inside_macro=$lut1_inside outside_macro=$lut1_outside"

# --- macro port census (import gate: every used port must stay connected) ---
set ports [lsort -dictionary [get_pins -quiet -of_objects [get_cells $GOLDEN_CELL]]]
set n_ports [llength $ports]
puts "I4_3A_GOLDEN_PORTS=$n_ports"

# --- manifest first (evidence survives even if the tool refuses export) ---
file mkdir $out_dir
set ch [open $manifest w]
puts $ch "I4_ROUTED_MACRO_MANIFEST_V1"
puts $ch "golden_dcp_sha\t$actual_sha"
puts $ch "golden_cell\t$GOLDEN_CELL"
puts $ch "ro_luts\t256"
puts $ch "prescaler\t64"
puts $ch "ripple_stages\t1088"
puts $ch "tap_routes\t64"
puts $ch "ripple_routes\t1088"
puts $ch "chain_inverter_lut1_total\t[llength $lut1_records]"
puts $ch "chain_inverter_lut1_inside_macro\t$lut1_inside"
puts $ch "chain_inverter_lut1_outside_macro\t$lut1_outside"
puts $ch "macro_port_count\t$n_ports"
puts $ch "macro_checkpoint\t[file tail $macro_dcp]"
puts $ch "PORTS"
foreach port [lsort -dictionary $ports] { puts $ch "PORT\t$port\t[get_property DIRECTION $port]" }
puts $ch "CHAIN_INVERTERS"
foreach record [lsort -dictionary $lut1_records] { puts $ch "LUT1\t$record" }
close $ch
puts "I4_3A_MANIFEST=$manifest"

# --- scoped export (hard failure stops Option A; never force) ---
write_checkpoint -cell [get_cells $GOLDEN_CELL] -force $macro_dcp
set macro_sha [ro_sha256_file $macro_dcp]
puts "I4_3A_MACRO_DCP=$macro_dcp"
puts "I4_3A_MACRO_SHA=$macro_sha"
close_design
