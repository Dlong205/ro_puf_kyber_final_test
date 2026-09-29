# R5-shell: operational-V2 construction project (NON-RELEASE, never programmed).
# Proves macro import + timing + fingerprint flow in the full operational
# design before R4 produces the real mapping.  The scheduler mapping resolves
# to the construction placeholder ONLY via include_dirs order; the golden
# puf64_mapping_data.vh is untouched.  Checked by
# scripts/check_operational_v2_construction.py.
set_param general.maxThreads 1
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
set build_dir [file join $root_dir build puf64_operational_v2]
set project_name puf64_operational_v2_zynq7020
set placeholder_dir [file join $root_dir rtl puf v2_construction_placeholder]

file mkdir $build_dir
if {![file isfile [file join $placeholder_dir puf64_mapping_data.vh]]} {
    error "R5-shell gate: placeholder mapping missing"
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
    [file join $root_dir rtl top kdf_keccak_compact.sv] \
    [file join $root_dir rtl top edge_seed_controller.sv] \
    [file join $root_dir rtl top edge_kem_scrub_controller.sv] \
    [file join $root_dir rtl top edge_control_plane.sv] \
    [file join $root_dir rtl top edge_mlkem_core.sv] \
    [file join $root_dir rtl top edge_puf64_operational_chain_v2.sv] \
    [file join $root_dir rtl top edge_puf64_operational_uart_v2.sv] \
    [file join $root_dir rtl top edge_kcv_anchor.sv] \
    [file join $root_dir rtl top Edge_Puf64_Zynq_Operational_V2_100MHz_Top.sv]]

foreach pattern [list \
        [file join $root_dir rtl hash_core *.v] \
        [file join $root_dir rtl kyber ref *.v] \
        [file join $root_dir rtl fuzzy_extractor *.v] \
        [file join $root_dir rtl fuzzy_extractor *.sv]] {
    foreach source [glob -nocomplain $pattern] { lappend sources $source }
}
foreach source $sources {
    if {![file isfile $source]} { error "R5-shell required RTL source missing: $source" }
}
add_files -norecurse $sources

set header_files [concat \
    [glob -nocomplain [file join $root_dir rtl top *.vh]] \
    [glob -nocomplain [file join $root_dir rtl fuzzy_extractor *.vh]]]
if {[llength $header_files] > 0} {
    add_files -norecurse $header_files
    set_property file_type {Verilog Header} [get_files $header_files]
}
# Placeholder include dir FIRST so the shell resolves the NON-RELEASE
# mapping; the golden file stays on disk untouched.
set_property include_dirs [list \
    $placeholder_dir \
    [file join $root_dir rtl top] \
    [file join $root_dir rtl common] \
    [file join $root_dir rtl hash_core] \
    [file join $root_dir rtl kyber ref] \
    [file join $root_dir rtl fuzzy_extractor]] [get_filesets sources_1]

set board_xdc [file join $root_dir constraints edge_puf64_zynq_operational_v2_100mhz.xdc]
if {![file isfile $board_xdc]} { error "R5-shell constraint missing: $board_xdc" }
add_files -fileset constrs_1 -norecurse [list $board_xdc]

set_property top Edge_Puf64_Zynq_Operational_V2_100MHz_Top [get_filesets sources_1]
set_property top_auto_set false [get_filesets sources_1]
update_compile_order -fileset sources_1
if {[llength [get_ips -quiet]] != 0 || [llength [get_files -all -quiet *.xci]] != 0} {
    error "Generated Xilinx IP unexpectedly entered the R5-shell project"
}
puts "R5_SHELL_PROJECT=[file join $build_dir ${project_name}.xpr]"
puts "R5_SHELL_TOP=Edge_Puf64_Zynq_Operational_V2_100MHz_Top"
puts "R5_SHELL_MAPPING=PLACEHOLDER_NONRELEASE"
close_project
