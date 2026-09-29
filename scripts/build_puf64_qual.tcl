# R6.1/R6.2 operational-qualification build (frozen gen1 mapping, NONRELEASE).
# Same flow as the PicoRV32 final (macro import + single-clock + timing +
# fingerprint), plus the R6 influence fingerprint and the superset sniffer
# audit.  Run under Vivado 2020.1, once per suffix for R6.2 A/B:
#   PUF64_QUAL_SUFFIX=A vivado -mode batch -nolog -nojournal \
#     -source scripts/build_puf64_qual.tcl
# Gate order: qual static -> synth complete -> import (target/inventory/
# routes/ports) -> single-clock cleanup (shell-only, macro untouched,
# re-audit) -> impl complete -> route -> timing 100MHz -> lifecycle +
# picorv32 + sniffer-superset audits -> critical logs (64x 8-295, 0
# unexpected) -> R2 macro fingerprint MATCH(frozen) -> influence export +
# SRC/GEN append.  A/B comparison happens outside (R6.2 gate script).
# NEVER programs the board.
set_param general.maxThreads 1
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
source [file join $script_dir ro_physical_common.tcl]
source [file join $script_dir audit_macro_v2_import.tcl]
source [file join $script_dir audit_final_lifecycle.tcl]
source [file join $script_dir audit_picorv32_final.tcl]
source [file join $script_dir audit_v2_critical_logs.tcl]

set suffix "A"
if {[info exists ::env(PUF64_QUAL_SUFFIX)] && $::env(PUF64_QUAL_SUFFIX) ne ""} {
    set suffix $::env(PUF64_QUAL_SUFFIX)
}
if {$suffix ni {"A" "B"}} {
    error "QUAL gate: PUF64_QUAL_SUFFIX must be A or B, got $suffix"
}
set build_dir [file join $root_dir build puf64_qual_${suffix}]
set project_name puf64_qual_zynq7020_${suffix}
set runs_name ${project_name}.runs
set project_file [file join $build_dir ${project_name}.xpr]
set report_dir [file join $root_dir reports puf64_qual_${suffix}]
set final_top Edge_Puf64_Zynq_PicoRV32_Final_100MHz_Top
set macro_dcp [file join $root_dir build puf64_macro_v2 macro_v2_routed_ooc.dcp]
set macro_fp [file join $root_dir build puf64_macro_v2 macro_v2_fingerprint.tsv]
set FROZEN_MACRO_SHA "bd0cd6200ca4e122932596eb8502d29f1b7d4b1aedf974a79990b4d1f5a9fdd4"
set TARGET "u_operational_uart/u_chain/u_puf64_core/u_macro"
set CORE "u_operational_uart/u_chain/u_puf64_core"
set FINAL_XDC [file join $root_dir constraints edge_puf64_zynq_operational_final_100mhz.xdc]

proc qual_apply_ro_constraints {} {
    set loop_nets [get_nets -quiet -hierarchical \
        -filter {NAME =~ "*u_macro*ro_cell*/t*"}]
    set ro_luts [get_cells -quiet -hierarchical \
        -filter {NAME =~ "*u_macro*ro_cell*/u_backend/LUT6_*"}]
    if {[llength $loop_nets] == 0 || [llength $ro_luts] != 256} {
        error "QUAL gate: RO constraint objects missing nets=[llength $loop_nets] luts=[llength $ro_luts]"
    }
    set_property ALLOW_COMBINATORIAL_LOOPS true $loop_nets
    set_false_path -through $loop_nets
    set_property DONT_TOUCH true $ro_luts
    puts "QUAL_RO_CONSTRAINTS_APPLIED nets=[llength $loop_nets] luts=[llength $ro_luts]"
}

# R6 superset audit: the capture sniffer (loads identical to final) must be
# present with block RAM + capture registers placed; the readout mux follows
# the QUAL generic (this build: NONRELEASE=1, readout live).
proc qual_audit_sniffer {} {
    set sniff "u_operational_uart/u_chain/u_puf64_core/u_qual_sniffer"
    set hits [get_cells -quiet -hierarchical -filter "NAME =~ \"*${sniff}/*\""]
    if {[llength $hits] == 0} {
        error "QUAL gate: sniffer hierarchy missing (superset broken)"
    }
    set brams [get_cells -quiet -hierarchical \
        -filter "NAME =~ \"*${sniff}/*\" && REF_NAME =~ RAMB*"]
    if {[llength $brams] < 1} {
        error "QUAL gate: sniffer BRAM missing (capture trimmed?)"
    }
    foreach cell $hits {
        if {[get_property LOC $cell] eq "" && \
            [string match "FD*" [get_property REF_NAME $cell]]} {
            error "QUAL gate: sniffer reg unplaced: $cell"
        }
    }
    puts "QUAL_SNIFFER=PASS cells=[llength $hits] bram=[llength $brams]"
}

if {[catch {exec env -u PYTHONHOME -u PYTHONPATH python3 \
        [file join $script_dir check_puf64_qual_static.py]} static_err]} {
    error "QUAL gate: static gate failed: $static_err"
}
puts "QUAL_STATIC=PASS"
if {![file exists $project_file]} {
    error "QUAL gate: qual project not found; run create_puf64_qual_project.tcl first"
}
if {[ro_sha256_file $macro_dcp] ne $FROZEN_MACRO_SHA} {
    error "QUAL gate: macro DCP is not the frozen R2 macro (SHA mismatch)"
}
if {![file isfile $macro_fp]} { error "QUAL gate: macro fingerprint missing" }
puts "QUAL_FROZEN_MACRO_SHA_OK=$FROZEN_MACRO_SHA"
file mkdir $report_dir
open_project $project_file
set stale_ooc [get_files -quiet "*macro_v2_routed_ooc.dcp"]
if {[llength $stale_ooc] != 0} {
    remove_files $stale_ooc
    puts "QUAL_HERMETIC_REMOVED_STALE_OOC=$stale_ooc"
}
puts "QUAL_BUILD_COMMIT=[exec git -C $root_dir rev-parse HEAD]"
puts "QUAL_VIVADO_VERSION=[version -short]"
if {![string match "2020.1*" [version -short]]} {
    error "QUAL gate: Vivado 2020.1 required"
}
if {[get_property TOP [get_filesets sources_1]] ne $final_top} {
    error "QUAL gate: wrong top"
}
set gen_prop [get_property generic [get_filesets sources_1]]
puts "QUAL_GENERICS=$gen_prop"
if {[string first "QUALIFICATION_NONRELEASE=1" $gen_prop] < 0} {
    error "QUAL gate: NONRELEASE generic missing (not a qual image?)"
}
if {[string first "QUAL_INFO_MARKER" $gen_prop] < 0} {
    error "QUAL gate: INFO marker generic missing"
}

reset_run synth_1
launch_runs synth_1 -jobs 1
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
puts "QUAL_SYNTH_STATUS=$synth_status"
if {![string match "*Complete*" $synth_status]} { error "QUAL gate: synthesis failed" }
open_run synth_1 -name qual_synth
set pre_sub [get_cells -quiet -hierarchical -filter "NAME =~ \"*${TARGET}/*\""]
if {[llength $pre_sub] != 0} {
    error "QUAL gate: black box $TARGET not empty pre-import: $pre_sub"
}
puts "QUAL_BLACKBOX_EMPTY=PASS"

read_checkpoint -cell [get_cells $TARGET] $macro_dcp
puts "QUAL_IMPORT_ACCEPTED"
macro_v2_audit_import $TARGET 1
macro_v2_lock_imported $TARGET

set stale_clk [get_clocks -quiet macro_clk]
if {[llength $stale_clk] == 0} {
    puts "QUAL_SINGLE_CLOCK_ALREADY_CLEAN"
} else {
    puts "QUAL_SINGLE_CLOCK_STALE_FOUND=[llength $stale_clk]"
    reset_timing
    read_xdc $FINAL_XDC
    set still [get_clocks -quiet macro_clk]
    if {[llength $still] != 0} {
        error "QUAL gate: macro_clk persists after single-clock cleanup"
    }
    puts "QUAL_SINGLE_CLOCK_CLEANUP=PASS"
}
if {[llength [get_clocks -quiet clk_sys_100mhz]] != 1} {
    error "QUAL gate: clk_sys_100mhz missing after cleanup"
}
if {[llength [get_clocks -quiet clk_in_50mhz]] != 1} {
    error "QUAL gate: clk_in_50mhz missing after cleanup"
}
if {[llength [get_clocks -quiet macro_clk]] != 0} {
    error "QUAL gate: macro_clk present after cleanup"
}
qual_apply_ro_constraints
macro_v2_audit_import $TARGET 1
puts "QUAL_MACRO_PRESERVED_AFTER_CLOCK_CLEANUP=PASS"

set synth_dcp [file join $build_dir $runs_name synth_1 ${final_top}.dcp]
write_checkpoint -force $synth_dcp
puts "QUAL_SYNTH_IMPORTED_SAVED=$synth_dcp"
close_design

# Same implementation strategy as final (environment parity).
reset_run impl_1
set_property STEPS.OPT_DESIGN.ARGS.DIRECTIVE Default [get_runs impl_1]
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE Default [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE Default [get_runs impl_1]
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]
puts "QUAL_IMPL_STRATEGY=Default/Default/DefaultPhysOpt/AggressiveRouteOnly"
launch_runs impl_1 -to_step write_bitstream -jobs 1
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
puts "QUAL_IMPL_STATUS=$impl_status"
if {![string match "*Complete*" $impl_status]} { error "QUAL gate: implementation failed" }
open_run impl_1 -name qual_impl
if {[get_property TOP [current_design]] ne $final_top} {
    error "QUAL gate: wrong top after impl"
}
set dupes [get_cells -quiet -hierarchical -filter "NAME =~ \"*u_macro\""]
if {[llength $dupes] != 1} { error "QUAL gate: macro instance issue: $dupes" }
if {[llength [get_clocks -quiet macro_clk]] != 0} {
    error "QUAL gate: macro_clk reappeared after impl"
}
puts "QUAL_SINGLE_CLOCK_POST_IMPL=PASS clocks=[get_clocks -quiet]"
set rs_file [file join $report_dir post_route_status.rpt]
report_route_status -file $rs_file
set ch [open $rs_file r]
set rs_data [read $ch]
close $ch
if {[regexp -nocase {partial|unrouted|RTSTAT|conflict} $rs_data]} {
    error "QUAL route gate: partial/RTSTAT/conflict (see $rs_file)"
}
puts "QUAL_ROUTE_STATUS=PASS"
set tm_file [file join $report_dir post_route_timing.rpt]
report_timing_summary -file $tm_file -max_paths 10
set ch [open $tm_file r]
set tm_data [read $ch]
close $ch
if {[regexp {(VIOLATED|Timing constraints are not met)} $tm_data]} {
    error "QUAL timing gate: 100 MHz violations (see $tm_file)"
}
if {[string first "macro_clk" $tm_data] >= 0} {
    error "QUAL timing gate: macro_clk present in timing report"
}
puts "QUAL_TIMING_100MHZ=PASS"
macro_v2_audit_import $TARGET 1
final_audit_lifecycle
picorv32_final_audit "u_operational_uart/u_rv32_supervisor"
qual_audit_sniffer
# Critical-warning gate: the macro is a black box at synth, so (like the
# proven final/diag builds: 0/0) exactly 0 RO-loop 8-295 are expected and 0
# unexpected critical warnings are allowed.  Empty RO index range.
set synth_log [file join $build_dir $runs_name synth_1 runme.log]
set impl_log [file join $build_dir $runs_name impl_1 runme.log]
v2_audit_critical_logs [list $synth_log $impl_log] "Synth 8-295" \
    "kp_ro_cell_xilinx.sv" "u_macro/u_bench/" 0 1 0
puts "QUAL_CRITICAL_WARNINGS=PASS"
report_utilization -file [file join $report_dir post_route_utilization.rpt]
report_drc -file [file join $report_dir post_route_drc.rpt]
report_methodology -file [file join $report_dir post_route_methodology.rpt]
report_clock_utilization -file [file join $report_dir post_route_clock_util.rpt]

# R2 macro fingerprint equality with the frozen macro.
set routed_dcp [file join $build_dir $runs_name impl_1 ${final_top}_routed.dcp]
set bitstream [file join $build_dir $runs_name impl_1 ${final_top}.bit]
set r2_fp [file join $report_dir qual_r2_macro_fingerprint.tsv]
puts "QUAL_BITSTREAM_SHA=[ro_sha256_file $bitstream]"
puts "QUAL_DCP_SHA=[ro_sha256_file $routed_dcp]"
set exporter [file join $script_dir export_puf64_macro_v2_fingerprint.tcl]
if {[catch {exec vivado -mode batch -nolog -nojournal -source $exporter \
        -tclargs $routed_dcp $r2_fp "QUAL_DCP_SHA"} export_err]} {
    error "QUAL gate: R2 fingerprint export failed: $export_err"
}
set cmp [file join $script_dir compare_puf64_macro_v2_fingerprint.py]
if {[catch {exec env -u PYTHONHOME -u PYTHONPATH python3 $cmp $macro_fp $r2_fp} cmp_err]} {
    error "R2_MACRO_FINGERPRINT_MISMATCH(qual): $cmp_err"
}
puts "R2_MACRO_FINGERPRINT_MATCH(qual)"

# R6 operational influence fingerprint (separate Vivado pass on the DCP).
set infl_fp [file join $report_dir qual_operational_influence_fingerprint.tsv]
if {[catch {exec vivado -mode batch -nolog -nojournal \
        -source [file join $script_dir export_puf64_operational_influence_fingerprint.tcl] \
        -tclargs $routed_dcp $infl_fp $final_top \
        "u_operational_uart/u_chain/u_puf64_core/u_macro"} infl_err]} {
    error "QUAL gate: influence export failed: $infl_err"
}
if {[catch {exec env -u PYTHONHOME -u PYTHONPATH python3 \
        [file join $script_dir hash_operational_sources.py] \
        $project_file $infl_fp \
        "DIAGNOSTIC_FAILURE_CODES=1" \
        "QUALIFICATION_NONRELEASE=1" "QUAL_INFO_MARKER=8'h71" \
        "HREC_MAPPING_TAG=16'h81B5" "HREC_GENERATION=8'h01"} src_err]} {
    error "QUAL gate: SRC/GEN append failed: $src_err"
}
puts "QUAL_INFLUENCE_FINGERPRINT=$infl_fp"
puts "QUAL_PICORV32_CONTROL_PLANE=1"
puts "QUAL_PROFILE=QUALIFICATION_NONRELEASE_NONRELEASE"
puts "QUAL_BUILD_DONE bitstream=$bitstream"
close_design
close_project
