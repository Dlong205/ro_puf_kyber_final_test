# Create the isolated RO-PUF diagnostic project for Arty A7-35 Rev. D/E.
set_param general.maxThreads 1
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
set build_dir [file join $root_dir build arty_puf_characterization]
set project_name puf_characterization_arty_a7_35t

file mkdir $build_dir
create_project $project_name $build_dir -part xc7a35ticsg324-1L -force
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
    if {![file exists $source]} {error "Missing source: $source"}
}
add_files -norecurse $sources
add_files -fileset constrs_1 -norecurse \
    [file join $root_dir constraints puf_characterization_arty_a7_35t.xdc]

set_property top Puf_Characterization_Top [get_filesets sources_1]
set_property top_auto_set false [get_filesets sources_1]
set_property generic {UART_CLKS_PER_BIT=868} [get_filesets sources_1]
update_compile_order -fileset sources_1

if {[llength [get_ips -quiet]] != 0 ||
    [llength [get_files -all -quiet *.xci]] != 0} {
    error "Generated Xilinx IP unexpectedly entered the Arty PUF project"
}
puts "ARTY_PUF_PROJECT=[file join $build_dir ${project_name}.xpr]"
puts "PART=[get_property PART [current_project]] UART_CLKS_PER_BIT=868"
close_project
