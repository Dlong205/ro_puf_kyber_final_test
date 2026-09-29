# Operational FINAL project, macro-V2 edition (single-clock, frozen mapping).
# Release-candidate: frozen mapping dir via include_dirs FIRST (default
# v2_mapping_frozen tag 0x81b5; PUF64_MAPPING_G2=1 selects v2_mapping_g2 tag
# 0x005d); device anchor in the final top (provisioned, no placeholder);
# macro enters ONLY as black box (bound later via DCP).
# Checked by scripts/check_operational_final_static.py.
set_param general.maxThreads 1
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
set picorv32_diag [expr {[info exists ::env(PUF64_PICORV32_DIAGNOSTIC)] &&
    $::env(PUF64_PICORV32_DIAGNOSTIC) eq "1"}]
set picorv32_final [expr {$picorv32_diag ||
    ([info exists ::env(PUF64_PICORV32_FINAL)] &&
     $::env(PUF64_PICORV32_FINAL) eq "1")}]
if {$picorv32_diag} {
    set build_dir [file join $root_dir build puf64_picorv32_diagnostic]
    set project_name puf64_picorv32_diagnostic_zynq7020
    set final_top Edge_Puf64_Zynq_PicoRV32_Final_100MHz_Top
} elseif {$picorv32_final} {
    set build_dir [file join $root_dir build puf64_picorv32_final]
    set project_name puf64_picorv32_final_zynq7020
    set final_top Edge_Puf64_Zynq_PicoRV32_Final_100MHz_Top
} else {
    set build_dir [file join $root_dir build puf64_operational_final]
    set project_name puf64_operational_final_zynq7020
    set final_top Edge_Puf64_Zynq_Operational_Final_100MHz_Top
}
# R7 characterize-through-final: PUF64_FINAL_CHAR=1 selects the NONRELEASE
# characterization build of the SAME final top (telemetry readout on, INFO
# marker 0x71) in its own build dir. Release and char never share a dir,
# bitstream, helper, anchor or tag claim.
set final_char [expr {[info exists ::env(PUF64_FINAL_CHAR)] && \
    $::env(PUF64_FINAL_CHAR) eq "1"}]
# Mapping generation flags (defined before any use): default frozen gen1
# (tag 0x81b5); PUF64_MAPPING_G2=1 selects v2_mapping_g2 (0x005d);
# PUF64_MAPPING_R7=1 selects v2_mapping_r7 (0x81b7, holdout-qualified
# through the final path). G2 and R7 are mutually exclusive; R7 and gen1
# never share a build dir, helper, anchor or tag claim.
set mapping_g2 [expr {[info exists ::env(PUF64_MAPPING_G2)] && \
    $::env(PUF64_MAPPING_G2) eq "1"}]
set mapping_r7 [expr {[info exists ::env(PUF64_MAPPING_R7)] && \
    $::env(PUF64_MAPPING_R7) eq "1"}]
if {$mapping_r7 && $mapping_g2} {
    error "FINAL gate: PUF64_MAPPING_G2 and PUF64_MAPPING_R7 are mutually exclusive"
}
if {$final_char && !$picorv32_final && !$picorv32_diag} {
    set build_dir [file join $root_dir build puf64_operational_final_char]
    set project_name puf64_operational_final_char_zynq7020
}
# R8 cutover: R7 release candidates build in their own dir (never shared
# with gen1/G2/char). Requires the holdout-qualified R7 mapping + anchor.
if {$mapping_r7 && !$picorv32_final && !$picorv32_diag && !$final_char} {
    set build_dir [file join $root_dir build puf64_operational_final_r7]
    set project_name puf64_operational_final_r7_zynq7020
}
# Mapping generation select: default frozen gen1 (tag 0x81b5);
# PUF64_MAPPING_G2=1 selects rtl/puf/v2_mapping_g2 (tag 0x005d);
# PUF64_MAPPING_R7=1 selects rtl/puf/v2_mapping_r7 (tag 0x81b7).
# (Flags defined above.)
if {$mapping_g2} {
    set frozen_dir [file join $root_dir rtl puf v2_mapping_g2]
    set expected_tag "16'h005d"
    set expected_tag_name "0x005d"
} elseif {$mapping_r7} {
    set frozen_dir [file join $root_dir rtl puf v2_mapping_r7]
    set expected_tag "16'h81b7"
    set expected_tag_name "0x81b7"
} else {
    set frozen_dir [file join $root_dir rtl puf v2_mapping_frozen]
    set expected_tag "16'h81b5"
    set expected_tag_name "0x81b5"
}

file mkdir $build_dir
if {![file isfile [file join $frozen_dir puf64_mapping_data.vh]]} {
    error "FINAL gate: frozen mapping missing"
}
set _fh [open [file join $frozen_dir puf64_mapping_data.vh] r]
set ftext [read $_fh]
close $_fh
if {[string first $expected_tag $ftext] < 0} {
    error "FINAL gate: frozen mapping tag $expected_tag_name missing"
}

create_project $project_name $build_dir -part xc7z020clg400-2 -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

set sources [list \
    [file join $root_dir rtl common generic_bram.sv] \
    [file join $root_dir rtl common generic_fifo.sv] \
    [file join $root_dir rtl common generic_mult.sv] \
    [file join $root_dir rtl common generic_rom.sv] \
    [file join $root_dir rtl common generic_srl.sv] \
    [file join $root_dir rtl common generic_blk_mem_wrapper.sv] \
    [file join $root_dir rtl common generic_c_shift_ram_wrapper.sv] \
    [file join $root_dir rtl common generic_dist_mem_wrapper.sv] \
    [file join $root_dir rtl common keccak_pkg.sv] \
    [file join $root_dir rtl puf uart_rx.v] \
    [file join $root_dir rtl puf uart_tx.v] \
    [file join $root_dir rtl puf kp_puf64_macro_v2_bb.sv] \
    [file join $root_dir rtl puf kp_puf64_mapping_scheduler.sv] \
    [file join $root_dir rtl top helper_record.sv] \
    [file join $root_dir rtl top edge_uart_transport.sv] \
    [file join $root_dir rtl top edge_root_binding.sv] \
    [file join $root_dir rtl top edge_puf64_operational_core_v2.sv] \
    [file join $root_dir rtl top puf64_qual_telemetry_sniffer.sv] \
    [file join $root_dir rtl top kdf_keccak_compact.sv] \
    [file join $root_dir rtl top edge_seed_controller.sv] \
    [file join $root_dir rtl top edge_kem_scrub_controller.sv] \
    [file join $root_dir rtl top edge_control_plane.sv] \
    [file join $root_dir rtl top edge_mlkem_core.sv] \
    [file join $root_dir rtl top edge_puf64_operational_chain_v2.sv] \
    [file join $root_dir rtl top edge_puf64_operational_uart_v2.sv] \
    [file join $root_dir rtl top edge_kcv_anchor.sv] \
    [file join $root_dir rtl top Edge_Puf64_Zynq_Operational_Final_100MHz_Top.sv]]

if {$picorv32_final} {
    lappend sources \
        [file join $root_dir rtl soc picorv32.v] \
        [file join $root_dir rtl soc soc_bram.v] \
        [file join $root_dir rtl soc puf64_picorv32_supervisor.sv] \
        [file join $root_dir rtl top edge_puf64_operational_uart_picorv32.sv] \
        [file join $root_dir rtl top Edge_Puf64_Zynq_PicoRV32_Final_100MHz_Top.sv]
}

foreach pattern [list \
        [file join $root_dir rtl hash_core *.v] \
        [file join $root_dir rtl kyber ref *.v] \
        [file join $root_dir rtl fuzzy_extractor *.v] \
        [file join $root_dir rtl fuzzy_extractor *.sv]] {
    foreach source [glob -nocomplain $pattern] { lappend sources $source }
}
foreach source $sources {
    if {![file isfile $source]} { error "FINAL required RTL source missing: $source" }
}
add_files -norecurse $sources

if {$picorv32_final} {
    set supervisor_hex [file join $root_dir firmware puf64_supervisor.hex]
    if {![file isfile $supervisor_hex]} {
        error "FINAL gate: PicoRV32 supervisor firmware missing; run make -C firmware supervisor"
    }
    add_files -norecurse $supervisor_hex
    set_property file_type {Memory Initialization Files} [get_files $supervisor_hex]
}

set header_files [concat \
    [glob -nocomplain [file join $root_dir rtl top *.vh]] \
    [glob -nocomplain [file join $root_dir rtl fuzzy_extractor *.vh]]]
if {[llength $header_files] > 0} {
    add_files -norecurse $header_files
    set_property file_type {Verilog Header} [get_files $header_files]
}
# Frozen mapping include dir FIRST so the final resolves tag 0x81b5;
# the old golden vh stays on disk untouched but shadowed.
set_property include_dirs [list \
    $frozen_dir \
    [file join $root_dir rtl top] \
    [file join $root_dir rtl common] \
    [file join $root_dir rtl hash_core] \
    [file join $root_dir rtl kyber ref] \
    [file join $root_dir rtl fuzzy_extractor]] [get_filesets sources_1]

set board_xdc [file join $root_dir constraints edge_puf64_zynq_operational_final_100mhz.xdc]
if {![file isfile $board_xdc]} { error "FINAL constraint missing: $board_xdc" }
add_files -fileset constrs_1 -norecurse [list $board_xdc]

set_property top $final_top [get_filesets sources_1]
set_property top_auto_set false [get_filesets sources_1]
# NOTE: set_property generic REPLACES the whole generic list, so all top
# generics must be set in ONE call. A second call would silently drop
# DIAGNOSTIC_FAILURE_CODES (observed once as release-code 0x03 on a
# diagnostic image). Verified by check: exactly one 'set_property generic'.
set generic_list {}
if {$picorv32_diag} {
    lappend generic_list "DIAGNOSTIC_FAILURE_CODES=1"
    puts "PICORV32_DIAGNOSTIC_FAILURE_CODES=ENABLED_NONRELEASE"
}
# R7 char build: NONRELEASE readout + INFO marker, same frozen mapping/anchor.
if {$final_char} {
    lappend generic_list "QUALIFICATION_NONRELEASE=1" \
        "QUAL_TELEMETRY_ENABLE=1" "QUAL_INFO_MARKER=8'h71" \
        "TIE_BUDGET=8"
    puts "FINAL_CHAR_GENERICS=NONRELEASE_TELEMETRY_INFO71_TIE8"
}
# Mapping generation generics for the plain final top (gen1 values are the
# RTL defaults; R7 overrides them explicitly — never silently). R7 KCV is
# the holdout-qualified R7 anchor (14edaaed..., ctx 0x0181b701010102).
if {$mapping_r7 && !$picorv32_final && !$picorv32_diag} {
    lappend generic_list "HREC_MAPPING_TAG=16'h81b7" "HREC_GENERATION=8'h01" "DEVICE_TRUSTED_KCV=224'h14edaaedcb8b7fcff6a60b74bee32c6c6a5d6195e3566dda7b3b21bb"
    puts "FINAL_MAPPING_GENERATION=R7_0x81b7_gen01"
}
# Mapping generation generics for the PicoRV32 top (gen1 values are the RTL
# defaults; gen2 overrides them explicitly — never silently).
if {$picorv32_final} {
    if {$mapping_g2} {
        lappend generic_list "HREC_MAPPING_TAG=16'h005d" "HREC_GENERATION=8'h02" "DEVICE_TRUSTED_KCV=224'h7f05d2d188f782c8f918a70e28f1137e566589743e2b7dd85f7bae21"
        puts "FINAL_MAPPING_GENERATION=G2_0x005d_gen02"
    } else {
        puts "FINAL_MAPPING_GENERATION=GEN1_0x81b5_gen01"
    }
}
if {[llength $generic_list] > 0} {
    set_property generic $generic_list [get_filesets sources_1]
}
update_compile_order -fileset sources_1
if {[llength [get_ips -quiet]] != 0 || [llength [get_files -all -quiet *.xci]] != 0} {
    error "Generated Xilinx IP unexpectedly entered the FINAL project"
}
# Fail closed if placeholder or real macro RTL entered synthesis.
foreach bad [list "*v2_construction_placeholder*" "*kp_puf64_macro_v2.sv" "*puf64_ro_bench_v2.sv" \
        "*kp_ripple_counter_v2.sv" "*kp_puf64_physical.sv" \
        "*puf64_ro_bench.sv" "*kp_ripple_counter.sv" \
        "*Puf_AllPairs64_Characterization_Top.sv" "*Kyber_System_Top.sv" \
        "*Edge_Puf64_Zynq_Operational_V2_100MHz_Top.sv"] {
    if {[llength [get_files -quiet $bad]] != 0} {
        set hits [get_files -quiet $bad]
        set ok 0
        if {$bad eq "*kp_puf64_macro_v2.sv" && [llength $hits] == 1 && \
            [string match "*_bb.sv" [lindex $hits 0]]} { set ok 1 }
        if {!$ok} { error "FINAL gate: forbidden source in project: $bad ($hits)" }
    }
}
puts "FINAL_PROJECT=[file join $build_dir ${project_name}.xpr]"
puts "FINAL_TOP=$final_top"
puts "FINAL_PICORV32_CONTROL_PLANE=$picorv32_final"
puts "FINAL_PICORV32_DIAGNOSTIC_NONRELEASE=$picorv32_diag"
if {$mapping_g2} {
    puts "FINAL_MAPPING=G2_0x005d"
} elseif {$mapping_r7} {
    puts "FINAL_MAPPING=R7_0x81b7"
} else {
    puts "FINAL_MAPPING=FROZEN_0x81b5"
}
close_project
