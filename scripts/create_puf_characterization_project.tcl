# Create a small, isolated PUF characterization project for XC7Z020-2CLG400I.
# This project contains no ML-KEM logic and cannot overwrite the release build.

set_param general.maxThreads 1
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
set build_dir [file join $root_dir build puf_characterization]
set project_name puf_characterization_zynq7020

file mkdir $build_dir
create_project $project_name $build_dir -part xc7z020clg400-2 -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

set sources [list \
    [file join $root_dir rtl top Puf_Characterization_Top.sv] \
    [file join $root_dir rtl top puf_characterization_uart.sv] \
    [file join $root_dir rtl puf kp_ro_cell.sv] \
    [file join $root_dir rtl puf kp_ro_cell_xilinx.sv] \
    [file join $root_dir rtl puf kp_puf_cells.sv] \
    [file join $root_dir rtl puf kp_puf_control.sv] \
    [file join $root_dir rtl puf kp_puf_top.sv] \
    [file join $root_dir rtl puf uart_rx.v] \
    [file join $root_dir rtl puf uart_tx.v]]

foreach source $sources {
    if {![file exists $source]} {
        error "Required characterization source is missing: $source"
    }
}
add_files -norecurse $sources

set base_xdc [file join $root_dir constraints kp_zynq_7020.xdc]
set placement_xdc [file join $root_dir constraints ro_placement_rc1_zynq7020.xdc]
add_files -fileset constrs_1 -norecurse [list $base_xdc $placement_xdc]

set_property top Puf_Characterization_Top [get_filesets sources_1]
set_property top_auto_set false [get_filesets sources_1]
update_compile_order -fileset sources_1

if {[llength [get_ips -quiet]] != 0 ||
    [llength [get_files -all -quiet *.xci]] != 0} {
    error "Generated Xilinx IP unexpectedly entered the PUF project"
}

puts "PUF_CHARACTERIZATION_PROJECT=[file join $build_dir ${project_name}.xpr]"
puts "PART=[get_property PART [current_project]] TOP=[get_property TOP [get_filesets sources_1]]"
close_project
