# R6.1 operational-qualification project (macro-V2, PicoRV32 control plane).
# Same environment as the PicoRV32 final: identical sources + sniffer,
# frozen gen1 mapping dir FIRST, same shell XDC, same top
# (Edge_Puf64_Zynq_PicoRV32_Final_100MHz_Top); the ONLY delta is the single
# set_property generic call selecting the NONRELEASE qualification profile
# (DIAGNOSTIC_FAILURE_CODES=1 like the gen1 diag, QUALIFICATION_NONRELEASE=1,
# QUAL_INFO_MARKER=0x71).  Checked by scripts/check_puf64_qual_static.py.
#
# A/B reproducibility (R6.2): PUF64_QUAL_SUFFIX=A|B selects disjoint build
# and report dirs; everything else is identical.
#   PUF64_QUAL_SUFFIX=A vivado -mode batch -nolog -nojournal \
#     -source scripts/create_puf64_qual_project.tcl
set_param general.maxThreads 1
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]

set suffix "A"
if {[info exists ::env(PUF64_QUAL_SUFFIX)] && $::env(PUF64_QUAL_SUFFIX) ne ""} {
    set suffix $::env(PUF64_QUAL_SUFFIX)
}
if {$suffix ni {"A" "B"}} {
    error "QUAL gate: PUF64_QUAL_SUFFIX must be A or B, got $suffix"
}
set build_dir [file join $root_dir build puf64_qual_${suffix}]
set project_name puf64_qual_zynq7020_${suffix}
set final_top Edge_Puf64_Zynq_PicoRV32_Final_100MHz_Top
set frozen_dir [file join $root_dir rtl puf v2_mapping_frozen]
set expected_tag "16'h81b5"

file mkdir $build_dir
if {![file isfile [file join $frozen_dir puf64_mapping_data.vh]]} {
    error "QUAL gate: frozen mapping missing"
}
set _fh [open [file join $frozen_dir puf64_mapping_data.vh] r]
set ftext [read $_fh]
close $_fh
if {[string first $expected_tag $ftext] < 0} {
    error "QUAL gate: frozen mapping tag 0x81b5 missing"
}

create_project $project_name $build_dir -part xc7z020clg400-2 -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

# Identical source set to the PicoRV32 final PLUS the qual sniffer (the
# superset capture hardware that final also carries).
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
    [file join $root_dir rtl top puf64_qual_telemetry_sniffer.sv] \
    [file join $root_dir rtl top edge_puf64_operational_core_v2.sv] \
    [file join $root_dir rtl top kdf_keccak_compact.sv] \
    [file join $root_dir rtl top edge_seed_controller.sv] \
    [file join $root_dir rtl top edge_kem_scrub_controller.sv] \
    [file join $root_dir rtl top edge_control_plane.sv] \
    [file join $root_dir rtl top edge_mlkem_core.sv] \
    [file join $root_dir rtl top edge_puf64_operational_chain_v2.sv] \
    [file join $root_dir rtl top edge_puf64_operational_uart_v2.sv] \
    [file join $root_dir rtl top edge_kcv_anchor.sv] \
    [file join $root_dir rtl top Edge_Puf64_Zynq_Operational_Final_100MHz_Top.sv] \
    [file join $root_dir rtl soc picorv32.v] \
    [file join $root_dir rtl soc soc_bram.v] \
    [file join $root_dir rtl soc puf64_picorv32_supervisor.sv] \
    [file join $root_dir rtl top edge_puf64_operational_uart_picorv32.sv] \
    [file join $root_dir rtl top Edge_Puf64_Zynq_PicoRV32_Final_100MHz_Top.sv]]

foreach pattern [list \
        [file join $root_dir rtl hash_core *.v] \
        [file join $root_dir rtl kyber ref *.v] \
        [file join $root_dir rtl fuzzy_extractor *.v] \
        [file join $root_dir rtl fuzzy_extractor *.sv]] {
    foreach source [glob -nocomplain $pattern] { lappend sources $source }
}
foreach source $sources {
    if {![file isfile $source]} { error "QUAL required RTL source missing: $source" }
}
add_files -norecurse $sources

set supervisor_hex [file join $root_dir firmware puf64_supervisor.hex]
if {![file isfile $supervisor_hex]} {
    error "QUAL gate: PicoRV32 supervisor firmware missing; run make -C firmware supervisor"
}
add_files -norecurse $supervisor_hex
set_property file_type {Memory Initialization Files} [get_files $supervisor_hex]

set header_files [concat \
    [glob -nocomplain [file join $root_dir rtl top *.vh]] \
    [glob -nocomplain [file join $root_dir rtl fuzzy_extractor *.vh]]]
if {[llength $header_files] > 0} {
    add_files -norecurse $header_files
    set_property file_type {Verilog Header} [get_files $header_files]
}
set_property include_dirs [list \
    $frozen_dir \
    [file join $root_dir rtl top] \
    [file join $root_dir rtl common] \
    [file join $root_dir rtl hash_core] \
    [file join $root_dir rtl kyber ref] \
    [file join $root_dir rtl fuzzy_extractor]] [get_filesets sources_1]

# Same shell XDC as final: same clocks, pins, single-clock discipline.
set board_xdc [file join $root_dir constraints edge_puf64_zynq_operational_final_100mhz.xdc]
if {![file isfile $board_xdc]} { error "QUAL constraint missing: $board_xdc" }
add_files -fileset constrs_1 -norecurse [list $board_xdc]

set_property top $final_top [get_filesets sources_1]
set_property top_auto_set false [get_filesets sources_1]
# NOTE: set_property generic REPLACES the whole generic list: exactly ONE
# call.  Qualification profile: diagnostic failure codes (like the gen1
# diag) + NONRELEASE readout + 0x71 INFO marker.  Mapping/anchor stay at
# the gen1 RTL defaults (tag 0x81b5, gen 0x01, provisioned anchor).
set_property generic {DIAGNOSTIC_FAILURE_CODES=1 QUALIFICATION_NONRELEASE=1 QUAL_INFO_MARKER=8'h71} [get_filesets sources_1]
update_compile_order -fileset sources_1
if {[llength [get_ips -quiet]] != 0 || [llength [get_files -all -quiet *.xci]] != 0} {
    error "Generated Xilinx IP unexpectedly entered the QUAL project"
}
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
        if {!$ok} { error "QUAL gate: forbidden source in project: $bad ($hits)" }
    }
}
puts "QUAL_PROJECT=[file join $build_dir ${project_name}.xpr]"
puts "QUAL_TOP=$final_top"
puts "QUAL_SUFFIX=$suffix"
puts "QUAL_PROFILE=QUALIFICATION_NONRELEASE_DIAGFAIL1_INFO71_GEN1"
close_project
