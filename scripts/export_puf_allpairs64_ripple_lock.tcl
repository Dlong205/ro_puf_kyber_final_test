# F4: export the production ripple characterization physical lock
# (RO LUTs, prescaler FDCEs, ripple stages, and narrow ro_tap routes).
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
set checkpoint [file join $root_dir build puf_allpairs64_characterization \
    puf_allpairs64_zynq7020.runs impl_1 Puf_AllPairs64_Characterization_Top_routed.dcp]
set out_place [file join $root_dir constraints puf_allpairs64_ripple_placement.xdc]
set out_pins [file join $root_dir constraints puf_allpairs64_ripple_lockpins.xdc]
set out_route [file join $root_dir constraints puf_allpairs64_ripple_route.xdc]
set out_fp [file join $root_dir reports puf_allpairs64_characterization \
    ro_ripple_fingerprint.tsv]
if {[llength $argv] > 0} { set checkpoint [file normalize [lindex $argv 0]] }
if {![file exists $checkpoint]} { error "production routed checkpoint missing: $checkpoint" }
source [file join $script_dir ro_physical_common.tcl]

open_checkpoint $checkpoint
set ro_luts [get_cells -quiet -hierarchical \
    -filter {NAME =~ "*u_puf*ro_cell*/u_backend/LUT6_*"}]
set presc [get_cells -quiet -hierarchical \
    -filter {NAME =~ "*counter/presc_fdce" && REF_NAME == "FDCE"}]
set stages [get_cells -quiet -hierarchical \
    -filter {REF_NAME == "FDCE" && NAME =~ "*stage*ff*"}]
if {[llength $ro_luts] != 256} { error "expected 256 RO LUTs, found [llength $ro_luts]" }
if {[llength $presc] != 64} { error "expected 64 prescalers, found [llength $presc]" }
if {[llength $stages] != 1088} { error "expected 1088 ripple stages (17 per RO), found [llength $stages]" }

file mkdir [file dirname $out_fp]
set ch [open $out_place w]
puts $ch "## F4 production ripple placement (LOC/BEL)."
foreach cell [concat $ro_luts $presc $stages] {
    set bel [get_property BEL $cell]
    set loc [get_property LOC $cell]
    if {$bel eq "" || $loc eq ""} { close $ch; error "missing BEL/LOC for $cell" }
    set t [format {[get_cells -hierarchical -filter {NAME == "%s"}]} $cell]
    puts $ch [format {set_property BEL %s %s} $bel $t]
    puts $ch [format {set_property LOC %s %s} $loc $t]
}
close $ch

set ch [open $out_pins w]
puts $ch "## F4 production ripple LOCK_PINS for the RO LUTs."
foreach cell $ro_luts {
    set pm [ro_lock_input_pin_map $cell]
    if {[llength $pm] == 0} { close $ch; error "no pin map for $cell" }
    set t [format {[get_cells -hierarchical -filter {NAME == "%s"}]} $cell]
    puts $ch [format {set_property LOCK_PINS %s %s} [list $pm] $t]
}
close $ch

set ch [open $out_route w]
puts $ch "## F4 narrow FIXED_ROUTE for the RO -> prescaler tap nets."
set fp [open $out_fp w]
puts $fp "RO_RIPPLE_FINGERPRINT_V1"
foreach cell [lsort -dictionary [concat $ro_luts $presc $stages]] {
    puts $fp "CELL\t$cell\t[get_property LOC $cell]\t[get_property BEL $cell]"
}
foreach p [lsort -dictionary $presc] {
    set cpin [get_pins -quiet -of_objects $p -filter {REF_PIN_NAME == "C"}]
    set net [lindex [get_nets -quiet -of_objects $cpin] 0]
    set route [get_property ROUTE $net]
    if {$route eq ""} { close $ch; close $fp; error "tap not routed: $net" }
    puts $ch [format {set_property FIXED_ROUTE %s [get_nets -hierarchical -filter {NAME == "%s"}]} [list $route] $net]
    puts $ch [format {set_property IS_ROUTE_FIXED true [get_nets -hierarchical -filter {NAME == "%s"}]} $net]
    puts $fp "TAP\t$net\t$route"
}
close $ch
close $fp
puts "PUF_ALLPAIRS64_RIPPLE_LOCK cells=[llength $ro_luts]+[llength $presc]+[llength $stages]"
puts "PUF_ALLPAIRS64_RIPPLE_FINGERPRINT=$out_fp"
close_design
