# Operational FINAL build (frozen mapping 0x81b5, device anchor, single-clock).
# Release-candidate: proves macro import + single-clock + timing + fingerprint
# in the full operational design.  Run under Vivado 2020.1:
#   vivado -mode batch -nolog -nojournal -source scripts/build_puf64_operational_final.tcl
# Gate order: synth complete -> import (target/inventory/routes/ports) ->
# single-clock cleanup (shell-only, macro LOC/BEL/ROUTE untouched, re-audit) ->
# impl complete -> route -> timing 100MHz -> lifecycle netlist proof ->
# critical logs -> inventory/clock -> V2 fingerprint export ->
# R2_MACRO_FINGERPRINT_MATCH(final) (required).
set_param general.maxThreads 1
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
source [file join $script_dir ro_physical_common.tcl]
source [file join $script_dir audit_macro_v2_import.tcl]
source [file join $script_dir audit_final_lifecycle.tcl]
source [file join $script_dir audit_picorv32_final.tcl]

set picorv32_diag [expr {[info exists ::env(PUF64_PICORV32_DIAGNOSTIC)] &&
    $::env(PUF64_PICORV32_DIAGNOSTIC) eq "1"}]
set picorv32_final [expr {$picorv32_diag ||
    ([info exists ::env(PUF64_PICORV32_FINAL)] &&
     $::env(PUF64_PICORV32_FINAL) eq "1")}]
if {$picorv32_diag} {
    set build_dir [file join $root_dir build puf64_picorv32_diagnostic]
    set project_name puf64_picorv32_diagnostic_zynq7020
    set runs_name puf64_picorv32_diagnostic_zynq7020.runs
    set project_file [file join $build_dir ${project_name}.xpr]
    set report_dir [file join $root_dir reports puf64_picorv32_diagnostic]
    set final_top Edge_Puf64_Zynq_PicoRV32_Final_100MHz_Top
    set final_fp_name picorv32_diagnostic_fingerprint.tsv
} elseif {$picorv32_final} {
    set build_dir [file join $root_dir build puf64_picorv32_final]
    set project_name puf64_picorv32_final_zynq7020
    set runs_name puf64_picorv32_final_zynq7020.runs
    set project_file [file join $build_dir puf64_picorv32_final_zynq7020.xpr]
    set report_dir [file join $root_dir reports puf64_picorv32_final]
    set final_top Edge_Puf64_Zynq_PicoRV32_Final_100MHz_Top
    set final_fp_name picorv32_final_fingerprint.tsv
} else {
    set build_dir [file join $root_dir build puf64_operational_final]
    set project_name puf64_operational_final_zynq7020
    set runs_name puf64_operational_final_zynq7020.runs
    set project_file [file join $build_dir puf64_operational_final_zynq7020.xpr]
    set report_dir [file join $root_dir reports puf64_operational_final]
    set final_top Edge_Puf64_Zynq_Operational_Final_100MHz_Top
    set final_fp_name final_fingerprint.tsv
}
# R7 characterize-through-final (mirrors the create script): PUF64_FINAL_CHAR=1
# builds the NONRELEASE char image in its own dir. Same macro/fingerprint
# gates; the char bitstream is bench-only and never frozen as release.
set final_char [expr {[info exists ::env(PUF64_FINAL_CHAR)] && \
    $::env(PUF64_FINAL_CHAR) eq "1"}]
set mapping_r7 [expr {[info exists ::env(PUF64_MAPPING_R7)] && \
    $::env(PUF64_MAPPING_R7) eq "1"}]
if {$final_char && !$picorv32_final && !$picorv32_diag} {
    set build_dir [file join $root_dir build puf64_operational_final_char]
    set project_name puf64_operational_final_char_zynq7020
    set runs_name puf64_operational_final_char_zynq7020.runs
    set project_file [file join $build_dir puf64_operational_final_char_zynq7020.xpr]
    set report_dir [file join $root_dir reports puf64_operational_final_char]
    set final_fp_name final_char_fingerprint.tsv
    puts "FINAL_CHAR_NONRELEASE_BUILD (telemetry readout on, INFO 0x71)"
} elseif {$mapping_r7 && !$picorv32_final && !$picorv32_diag} {
    set build_dir [file join $root_dir build puf64_operational_final_r7]
    set project_name puf64_operational_final_r7_zynq7020
    set runs_name puf64_operational_final_r7_zynq7020.runs
    set project_file [file join $build_dir puf64_operational_final_r7_zynq7020.xpr]
    set report_dir [file join $root_dir reports puf64_operational_final_r7]
    set final_fp_name final_r7_fingerprint.tsv
    puts "FINAL_R7_RELEASE_BUILD (mapping 0x81b7, holdout-qualified)"
}
set macro_dcp [file join $root_dir build puf64_macro_v2 macro_v2_routed_ooc.dcp]
set macro_fp [file join $root_dir build puf64_macro_v2 macro_v2_fingerprint.tsv]
set FROZEN_MACRO_SHA "bd0cd6200ca4e122932596eb8502d29f1b7d4b1aedf974a79990b4d1f5a9fdd4"
set TARGET "u_operational_uart/u_chain/u_puf64_core/u_macro"
set FINAL_XDC [file join $root_dir constraints edge_puf64_zynq_operational_final_100mhz.xdc]

proc final_apply_ro_constraints {} {
    set loop_nets [get_nets -quiet -hierarchical \
        -filter {NAME =~ "*u_macro*ro_cell*/t*"}]
    set ro_luts [get_cells -quiet -hierarchical \
        -filter {NAME =~ "*u_macro*ro_cell*/u_backend/LUT6_*"}]
    if {[llength $loop_nets] == 0 || [llength $ro_luts] != 256} {
        error "FINAL gate: RO constraint objects missing nets=[llength $loop_nets] luts=[llength $ro_luts]"
    }
    set_property ALLOW_COMBINATORIAL_LOOPS true $loop_nets
    set_false_path -through $loop_nets
    set_property DONT_TOUCH true $ro_luts
    puts "FINAL_RO_CONSTRAINTS_APPLIED nets=[llength $loop_nets] luts=[llength $ro_luts]"
}

if {![file exists $project_file]} {
    error "FINAL gate: final project not found; run create_puf64_operational_final_project.tcl first"
}
if {[ro_sha256_file $macro_dcp] ne $FROZEN_MACRO_SHA} {
    error "FINAL gate: macro DCP is not the frozen R2 macro (SHA mismatch)"
}
if {![file isfile $macro_fp]} { error "FINAL gate: macro fingerprint missing" }
puts "FINAL_FROZEN_MACRO_SHA_OK=$FROZEN_MACRO_SHA"
file mkdir $report_dir
open_project $project_file
# Hermetic rebuild: a previous read_checkpoint -cell persists the OOC DCP in
# the project (ScopedToCell=u_macro) and Vivado would auto-link it at synth,
# so the pre-import box would not be empty.  Remove any such association so
# every build synthesizes a clean black box and imports explicitly.
set stale_ooc [get_files -quiet "*macro_v2_routed_ooc.dcp"]
if {[llength $stale_ooc] != 0} {
    remove_files $stale_ooc
    puts "FINAL_HERMETIC_REMOVED_STALE_OOC=$stale_ooc"
}
puts "FINAL_BUILD_COMMIT=[exec git -C $root_dir rev-parse HEAD]"
puts "FINAL_VIVADO_VERSION=[version -short]"
if {![string match "2020.1*" [version -short]]} {
    error "FINAL gate: Vivado 2020.1 required"
}
if {[get_property TOP [get_filesets sources_1]] ne $final_top} {
    error "FINAL gate: wrong top"
}

# --- synthesis (macro stays a black box) ---
reset_run synth_1
launch_runs synth_1 -jobs 1
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
puts "FINAL_SYNTH_STATUS=$synth_status"
if {![string match "*Complete*" $synth_status]} { error "FINAL gate: synthesis failed" }
open_run synth_1 -name final_synth
set pre_sub [get_cells -quiet -hierarchical -filter "NAME =~ \"*${TARGET}/*\""]
if {[llength $pre_sub] != 0} {
    error "FINAL gate: black box $TARGET not empty pre-import: $pre_sub"
}
puts "FINAL_BLACKBOX_EMPTY=PASS"

# --- import the exact frozen macro ---
read_checkpoint -cell [get_cells $TARGET] $macro_dcp
puts "FINAL_IMPORT_ACCEPTED"
macro_v2_audit_import $TARGET 1
macro_v2_lock_imported $TARGET

# --- single-clock cleanup (shell constraint only) ---
# The OOC DCP carries a stale primary clock (macro_clk on the hier pin).
# Shell logic (including the macro control FSM) must run on clk_sys_100mhz.
# reset_timing clears in-memory timing constraints (physical IS_*_FIXED locks
# survive: they are placement/routing properties, not timing), then the final
# shell XDC re-applies ONLY clk_in_50mhz + clk_sys_100mhz + RO false-paths.
# Macro cells/nets are re-audited immediately to prove placement/routing
# untouched.
set stale_clk [get_clocks -quiet macro_clk]
if {[llength $stale_clk] == 0} {
    puts "FINAL_SINGLE_CLOCK_ALREADY_CLEAN"
} else {
    puts "FINAL_SINGLE_CLOCK_STALE_FOUND=[llength $stale_clk]"
    reset_timing
    read_xdc $FINAL_XDC
    set still [get_clocks -quiet macro_clk]
    if {[llength $still] != 0} {
        error "FINAL gate: macro_clk persists after single-clock cleanup"
    }
    puts "FINAL_SINGLE_CLOCK_CLEANUP=PASS"
}
set clklist [get_clocks -quiet]
puts "FINAL_CLOCKS_AFTER_CLEANUP=$clklist"
if {[llength [get_clocks -quiet clk_sys_100mhz]] != 1} {
    error "FINAL gate: clk_sys_100mhz missing after cleanup"
}
if {[llength [get_clocks -quiet clk_in_50mhz]] != 1} {
    error "FINAL gate: clk_in_50mhz missing after cleanup"
}
if {[llength [get_clocks -quiet macro_clk]] != 0} {
    error "FINAL gate: macro_clk present after cleanup"
}
final_apply_ro_constraints
# Re-prove the macro survived the constraint operation bit-identical.
macro_v2_audit_import $TARGET 1
puts "FINAL_MACRO_PRESERVED_AFTER_CLOCK_CLEANUP=PASS"

set synth_dcp [file join $build_dir $runs_name synth_1 ${final_top}.dcp]
write_checkpoint -force $synth_dcp
puts "FINAL_SYNTH_IMPORTED_SAVED=$synth_dcp"
close_design

# --- implementation of the rest ---
reset_run impl_1
# Timing closure under single-clock (shell build strategy only; macro stays
# IS_*_FIXED locked, RTL/XDC/macro untouched). Attempt 1 (all default) failed
# clk_sys WNS -0.208 (175 endpoints, route-dominated ML-KEM hash reset
# paths); construction was thin (+0.007). Attempts 2-3 (PLACE ExtraTimingOpt)
# closed timing (WNS +0.164, no macro_clk) but moved unlocked macro-bench
# sync cells and left a_s1[3] partially routed -> fail-closed, discarded.
# Attempt 4 (OPT/PLACE/PHYS_OPT Default + ROUTE Explore) kept the route-safe
# default placement (route PASS) and cut the violation to WNS -0.033 with 6
# failing endpoints (same ML-KEM hash FIFO->sponge /R paths). Attempt 5
# (minimal delta): identical synthesis+placement to attempt 4, router only
# raised to AggressiveExplore to attack the residual 33 ps of route delay.
# Still requires route-complete + WNS>=0, no gate cut.
set_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE Default [get_runs impl_1]
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE Default [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE Default [get_runs impl_1]
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]
puts "FINAL_IMPL_STRATEGY=Default/Default/DefaultPhysOpt/AggressiveRouteOnly"
launch_runs impl_1 -to_step write_bitstream -jobs 1
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
puts "FINAL_IMPL_STATUS=$impl_status"
if {![string match "*Complete*" $impl_status]} { error "FINAL gate: implementation failed" }
open_run impl_1 -name final_impl
if {[get_property TOP [current_design]] ne $final_top} {
    error "FINAL gate: wrong top after impl"
}
set dupes [get_cells -quiet -hierarchical -filter "NAME =~ \"*u_macro\""]
if {[llength $dupes] != 1} { error "FINAL gate: macro instance issue: $dupes" }
# Single-clock must survive implementation: no macro_clk in the routed design.
if {[llength [get_clocks -quiet macro_clk]] != 0} {
    error "FINAL gate: macro_clk reappeared after impl"
}
puts "FINAL_SINGLE_CLOCK_POST_IMPL=PASS clocks=[get_clocks -quiet]"
set rs_file [file join $report_dir post_route_status.rpt]
report_route_status -file $rs_file
set ch [open $rs_file r]
set rs_data [read $ch]
close $ch
if {[regexp -nocase {partial|unrouted|RTSTAT|conflict} $rs_data]} {
    error "FINAL route gate: partial/RTSTAT/conflict (see $rs_file)"
}
puts "FINAL_ROUTE_STATUS=PASS"
set tm_file [file join $report_dir post_route_timing.rpt]
report_timing_summary -file $tm_file -max_paths 10
set ch [open $tm_file r]
set tm_data [read $ch]
close $ch
if {[regexp {(VIOLATED|Timing constraints are not met)} $tm_data]} {
    error "FINAL timing gate: 100 MHz violations (see $tm_file)"
}
if {[string first "macro_clk" $tm_data] >= 0} {
    error "FINAL timing gate: macro_clk present in timing report"
}
puts "FINAL_TIMING_100MHZ=PASS"
macro_v2_audit_import $TARGET 1
final_audit_lifecycle
if {$picorv32_final} {
    picorv32_final_audit "u_operational_uart/u_rv32_supervisor"
}
report_utilization -file [file join $report_dir post_route_utilization.rpt]
report_timing_summary -file $tm_file -max_paths 10
report_drc -file [file join $report_dir post_route_drc.rpt]
report_methodology -file [file join $report_dir post_route_methodology.rpt]
report_clock_utilization -file [file join $report_dir post_route_clock_util.rpt]
close_design

# --- fingerprint equality with the frozen macro ---
set routed_dcp [file join $build_dir $runs_name impl_1 ${final_top}_routed.dcp]
set bitstream [file join $build_dir $runs_name impl_1 ${final_top}.bit]
set final_fp [file join $report_dir $final_fp_name]
puts "FINAL_BITSTREAM_SHA=[ro_sha256_file $bitstream]"
puts "FINAL_DCP_SHA=[ro_sha256_file $routed_dcp]"
set exporter [file join $script_dir export_puf64_macro_v2_fingerprint.tcl]
if {[catch {exec vivado -mode batch -nolog -nojournal -source $exporter \
        -tclargs $routed_dcp $final_fp "FINAL_DCP_SHA"} export_err]} {
    error "FINAL gate: fingerprint export failed: $export_err"
}
set cmp [file join $script_dir compare_puf64_macro_v2_fingerprint.py]
if {[catch {exec env -u PYTHONHOME -u PYTHONPATH python3 $cmp $macro_fp $final_fp} cmp_err]} {
    error "R2_MACRO_FINGERPRINT_MISMATCH(final): $cmp_err"
}
puts "R2_MACRO_FINGERPRINT_MATCH(final)"
puts "FINAL_PICORV32_CONTROL_PLANE=$picorv32_final"
puts "FINAL_PICORV32_DIAGNOSTIC_NONRELEASE=$picorv32_diag"
puts "FINAL_BUILD_DONE bitstream=$bitstream"
close_project
