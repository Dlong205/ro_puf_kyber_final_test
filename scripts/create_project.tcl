# Create a self-contained, pure-RTL Vivado project for XC7Z020-2CLG400I.
# No XCI, Block Design, Processing System, Clocking Wizard, or other generated
# Xilinx IP is used. FPGA primitives intentionally used by the RO/BCH RTL are
# ordinary RTL library primitives, not generated IP.

set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
set build_dir [file join $root_dir build vivado]
set project_name kyber_ro_puf_zynq7020

file mkdir $build_dir
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
    [file join $root_dir rtl kyber kyber_axi_wrapper.v] \
    [file join $root_dir rtl top kdf_keccak.sv] \
    [file join $root_dir rtl top Kyber_System_Top.sv] \
    [file join $root_dir rtl soc picorv32.v] \
    [file join $root_dir rtl soc soc_bram.v] \
    [file join $root_dir rtl soc soc_peripherals.sv] \
    [file join $root_dir rtl soc riscv_soc.sv] \
    [file join $root_dir rtl puf kp_ro_cell.sv] \
    [file join $root_dir rtl puf kp_puf_cells.sv] \
    [file join $root_dir rtl puf kp_puf_control.sv] \
    [file join $root_dir rtl puf kp_puf_top.sv] \
    [file join $root_dir rtl puf uart_rx.v] \
    [file join $root_dir rtl puf uart_tx.v]]

foreach pattern [list \
        [file join $root_dir rtl hash_core *.v] \
        [file join $root_dir rtl kyber ref *.v] \
        [file join $root_dir rtl fuzzy_extractor *.v] \
        [file join $root_dir rtl fuzzy_extractor *.sv]] {
    foreach source [glob -nocomplain $pattern] {
        lappend sources $source
    }
}

foreach source $sources {
    if {![file exists $source]} {
        error "Required RTL source is missing: $source"
    }
}
add_files -norecurse $sources

set header_files [glob -nocomplain [file join $root_dir rtl fuzzy_extractor *.vh]]
if {[llength $header_files] > 0} {
    add_files -norecurse $header_files
    set_property file_type {Verilog Header} [get_files $header_files]
}
set_property include_dirs [list \
    [file join $root_dir rtl fuzzy_extractor] \
    [file join $root_dir rtl common] \
    [file join $root_dir rtl hash_core] \
    [file join $root_dir rtl kyber ref]] [get_filesets sources_1]

set firmware_file [file join $root_dir firmware firmware.hex]
if {![file exists $firmware_file]} {
    error "Firmware image is missing: $firmware_file"
}
add_files -norecurse $firmware_file
set_property file_type {Memory Initialization Files} [get_files $firmware_file]

set constraint_file [file join $root_dir constraints kp_zynq_7020.xdc]
if {![file exists $constraint_file]} {
    error "Board constraint is missing: $constraint_file"
}
add_files -fileset constrs_1 -norecurse $constraint_file

set_property top Kyber_System_Top [get_filesets sources_1]
set_property top_auto_set false [get_filesets sources_1]
update_compile_order -fileset sources_1

set xci_files [get_files -all -quiet *.xci]
if {[llength $xci_files] != 0 || [llength [get_ips -quiet]] != 0} {
    error "Generated Xilinx IP unexpectedly entered the standalone project"
}

puts "STANDALONE_PROJECT=[file join $build_dir ${project_name}.xpr]"
puts "PART=[get_property PART [current_project]] TOP=[get_property TOP [get_filesets sources_1]] XCI=0 IP=0"
close_project
