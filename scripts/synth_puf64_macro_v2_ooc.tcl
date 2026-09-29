# R1: OOC synthesis of the macro-V2 root + physical census + hierarchy audit.
# No placement/routing here (R2 routes the frozen macro).  Run under
# Vivado 2020.1:
#   vivado -mode batch -nolog -nojournal -source scripts/synth_puf64_macro_v2_ooc.tcl
set_param general.maxThreads 1
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
set out_dir [file join $root_dir build puf64_macro_v2]
file mkdir $out_dir

set sources [list \
    [file join $root_dir rtl puf kp_ro_cell.sv] \
    [file join $root_dir rtl puf kp_ro_cell_model.sv] \
    [file join $root_dir rtl puf kp_ro_cell_asic.sv] \
    [file join $root_dir rtl puf kp_ro_cell_xilinx.sv] \
    [file join $root_dir rtl puf kp_ripple_counter_v2.sv] \
    [file join $root_dir rtl puf puf64_ro_bench_v2.sv] \
    [file join $root_dir rtl puf kp_puf64_macro_v2.sv]]
foreach source $sources {
    if {![file isfile $source]} { error "R1 macro source missing: $source" }
}
# Golden v1 bench/counter must never enter the V2 OOC netlist.
read_verilog -sv $sources
synth_design -top kp_puf64_macro_v2 -part xc7z020clg400-2 -mode out_of_context
puts "R1_VIVADO_VERSION=[version -short]"
if {![string match "2020.1*" [version -short]]} {
    error "R1 gate: Vivado 2020.1 required, found [version -short]"
}

# --- physical census (post-synth, unplaced: counts + hierarchy only) ---
set ro [get_cells -quiet -hierarchical -filter {NAME =~ "*ro_cell*/u_backend/LUT6_*"}]
set pr [get_cells -quiet -hierarchical -filter {NAME =~ "*counter/presc_fdce" && REF_NAME == "FDCE"}]
set st [get_cells -quiet -hierarchical -filter {REF_NAME == "FDCE" && NAME =~ "*stage*ff*"}]
set inv_p [get_cells -quiet -hierarchical -filter {REF_NAME == "LUT1" && NAME =~ "*inv_presc*"}]
set inv_s [get_cells -quiet -hierarchical -filter {REF_NAME == "LUT1" && NAME =~ "*stage*inv*"}]
puts "R1_OOC_CENSUS ro_lut=[llength $ro] presc=[llength $pr] stages=[llength $st] inv_presc=[llength $inv_p] inv_stage=[llength $inv_s]"
if {[llength $ro] != 256} { error "R1 gate: expected 256 RO LUTs, found [llength $ro]" }
if {[llength $pr] != 64} { error "R1 gate: expected 64 prescalers, found [llength $pr]" }
if {[llength $st] != 1088} { error "R1 gate: expected 1088 ripple stages, found [llength $st]" }
if {[llength $inv_p] != 64} { error "R1 gate: expected 64 prescaler INVs, found [llength $inv_p]" }
if {[llength $inv_s] != 1088} { error "R1 gate: expected 1088 stage INVs, found [llength $inv_s]" }
foreach cell $inv_p {
    if {[get_property INIT $cell] ne "2'h1"} { error "R1 gate: presc INV INIT not 2'h1: $cell" }
}
foreach cell $inv_s {
    if {[get_property INIT $cell] ne "2'h1"} { error "R1 gate: stage INV INIT not 2'h1: $cell" }
}

# --- hierarchy audit: no physical cell may escape the macro root ---
set escaped {}
foreach cell [concat $ro $pr $st $inv_p $inv_s] {
    if {[string first "u_bench/" $cell] < 0} { lappend escaped $cell }
}
if {[llength $escaped] != 0} {
    error "R1 gate: [llength $escaped] physical cells outside u_bench, first: [lindex $escaped 0]"
}
# Forbid any golden-v1 module instance in the netlist.
foreach bad [list "puf64_ro_bench" "kp_ripple_counter"] {
    set hits [get_cells -quiet -hierarchical -filter "REF_NAME == \"$bad\""]
    if {[llength $hits] != 0} { error "R1 gate: golden module present: $bad ($hits)" }
}
puts "R1_OOC_CONTAINMENT=PASS cells=2560 all under u_bench, no golden modules"

set ooc_dcp [file join $out_dir macro_v2_ooc_synth.dcp]
write_checkpoint -force $ooc_dcp
report_utilization -file [file join $out_dir ooc_synth_utilization.rpt]
puts "R1_OOC_SYNTH_DCP=$ooc_dcp"
puts "R1_OOC_SYNTH=PASS"
