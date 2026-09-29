# R2: place/route + freeze the OOC macro-V2 + V2 fingerprint reference.
# Launch WITHOUT -nolog/-nojournal and WITH -log/-journal so the session log
# exists for the critical-warning gate.  See Makefile puf64-macro-v2-route.
# Fails closed on: route incomplete, timing violated, unexpected criticals,
# inventory/hierarchy drift, missing routes, global buffers on PUF clocks.
set_param general.maxThreads 1
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
source [file join $script_dir ro_physical_common.tcl]
source [file join $script_dir audit_puf64_operational_physical.tcl]

set out_dir [file join $root_dir build puf64_macro_v2]
set synth_dcp [file join $out_dir macro_v2_ooc_synth.dcp]
set ooc_xdc [file join $root_dir constraints puf64_macro_v2_ooc.xdc]
set routed_dcp [file join $out_dir macro_v2_routed_ooc.dcp]
set macro_fp [file join $out_dir macro_v2_fingerprint.tsv]
set report_dir $out_dir
if {![file isfile $synth_dcp]} { error "R2 gate: OOC synth DCP missing: $synth_dcp" }
if {![file isfile $ooc_xdc]} { error "R2 gate: OOC XDC missing: $ooc_xdc" }
puts "R2_VIVADO_VERSION=[version -short]"
if {![string match "2020.1*" [version -short]]} {
    error "R2 gate: Vivado 2020.1 required, found [version -short]"
}

open_checkpoint $synth_dcp
read_xdc $ooc_xdc
opt_design
place_design
route_design

# --- route completeness ---
set rs_file [file join $report_dir ooc_route_status.rpt]
report_route_status -file $rs_file
set ch [open $rs_file r]
set rs_data [read $ch]
close $ch
if {[regexp -nocase {partial|unrouted|RTSTAT|conflict} $rs_data]} {
    error "R2 route gate: partial route / RTSTAT / conflict (see $rs_file)"
}
puts "R2_ROUTE_STATUS=PASS"

# --- timing: macro_clk must meet 10ns; any violation fails ---
set tm_file [file join $report_dir ooc_timing.rpt]
report_timing_summary -file $tm_file -max_paths 10
set ch [open $tm_file r]
set tm_data [read $ch]
close $ch
if {[regexp {(VIOLATED|Timing constraints are not met)} $tm_data]} {
    error "R2 timing gate: violations present (see $tm_file)"
}
puts "R2_TIMING=PASS"

# --- inventory with placement (post-route) ---
set ro [get_cells -quiet -hierarchical -filter {NAME =~ "*ro_cell*/u_backend/LUT6_*"}]
set pr [get_cells -quiet -hierarchical -filter {NAME =~ "*counter/presc_fdce" && REF_NAME == "FDCE"}]
set st [get_cells -quiet -hierarchical -filter {REF_NAME == "FDCE" && NAME =~ "*stage*ff*"}]
set inv_p [get_cells -quiet -hierarchical -filter {REF_NAME == "LUT1" && NAME =~ "*inv_presc*"}]
set inv_s [get_cells -quiet -hierarchical -filter {REF_NAME == "LUT1" && NAME =~ "*stage*inv*"}]
if {[llength $ro] != 256 || [llength $pr] != 64 || [llength $st] != 1088 || \
    [llength $inv_p] != 64 || [llength $inv_s] != 1088} {
    error "R2 gate: inventory drift ro=[llength $ro] pr=[llength $pr] st=[llength $st] invp=[llength $inv_p] invs=[llength $inv_s]"
}
# The non-clocked population (methodology TIMING-17) must be exactly the
# 1152 ripple FDCEs: no other FDCE, no LDCE latches anywhere.
set all_fdce [get_cells -quiet -hierarchical -filter {REF_NAME == "FDCE"}]
set all_ldce [get_cells -quiet -hierarchical -filter {REF_NAME == "LDCE"}]
if {[llength $all_fdce] != 1152} {
    error "R2 gate: total FDCE count [llength $all_fdce] != 1152"
}
if {[llength $all_ldce] != 0} {
    error "R2 gate: unexpected LDCE latches: $all_ldce"
}
foreach cell [concat $ro $pr $st $inv_p $inv_s] {
    if {[get_property LOC $cell] eq "" || [get_property BEL $cell] eq ""} {
        error "R2 gate: missing LOC/BEL: $cell"
    }
    if {[string first "u_bench/" $cell] < 0} {
        error "R2 gate: physical cell outside u_bench: $cell"
    }
}
puts "R2_INVENTORY=PASS 256+64+1088+64+1088 all placed under u_bench"

# --- freeze + fingerprint (exporter fails closed on routes/buffers) ---
write_checkpoint -force $routed_dcp
set routed_sha [ro_sha256_file $routed_dcp]
puts "R2_ROUTED_DCP=$routed_dcp"
puts "R2_ROUTED_SHA=$routed_sha"
report_utilization -file [file join $report_dir ooc_utilization.rpt]
report_drc -file [file join $report_dir ooc_drc.rpt]
report_methodology -file [file join $report_dir ooc_methodology.rpt]
report_clock_utilization -file [file join $report_dir ooc_clock_util.rpt]
close_design

# Fingerprint in a nested call (clean state); nested vivado inherits env fine.
set exporter [file join $script_dir export_puf64_macro_v2_fingerprint.tcl]
if {[catch {exec vivado -mode batch -nolog -nojournal -source $exporter \
        -tclargs $routed_dcp $macro_fp "MACRO_DCP_SHA"} export_err]} {
    error "R2 gate: macro fingerprint export failed: $export_err"
}
set fp_sha [ro_sha256_file $macro_fp]
puts "R2_MACRO_FINGERPRINT=$macro_fp"
puts "R2_MACRO_FINGERPRINT_SHA=$fp_sha"
puts "R2_ROUTE_FREEZE=PASS"
