# Create the isolated 64-RO/C(64,2) characterization project for Zynq-7020.
# The 32-RO baseline project/flow is untouched; this is a separate project tree
# so the PUF32 release image and its accepted lock stay intact.
set_param general.maxThreads 1
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
set build_dir [file join $root_dir build puf_allpairs64_characterization]
set project_name puf_allpairs64_zynq7020

file mkdir $build_dir
create_project $project_name $build_dir -part xc7z020clg400-2 -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

set sources [list \
    [file join $root_dir rtl top Puf_AllPairs64_Characterization_Top.sv] \
    [file join $root_dir rtl top puf_allpairs_uart.sv] \
    [file join $root_dir rtl puf kp_ro_cell.sv] \
    [file join $root_dir rtl puf kp_ro_cell_xilinx.sv] \
    [file join $root_dir rtl puf kp_puf_cells.sv] \
    [file join $root_dir rtl puf kp_puf_control.sv] \
    [file join $root_dir rtl puf kp_puf_allpairs_top.sv] \
    [file join $root_dir rtl puf uart_rx.v] \
    [file join $root_dir rtl puf uart_tx.v]]

foreach source $sources {
    if {![file exists $source]} { error "Missing all-pairs64 source: $source" }
}
add_files -norecurse $sources
set allpairs64_constraints [list \
    [file join $root_dir constraints kp_zynq_7020.xdc]]
set placement_xdc [file join $root_dir constraints ro_placement_puf64_zynq7020.xdc]
if {[file exists $placement_xdc]} {
    # Explicit 64-RO placement map produced in the lab after the first
    # accepted build; do not plant a lock before an implementation is approved.
    lappend allpairs64_constraints $placement_xdc
} else {
    puts "PUF_ALLPAIRS64_PLACEMENT=not-exported (baseline build path)"
}
set lock_xdc [file join $root_dir constraints ro_physical_lock_allpairs64_zynq7020.xdc]
if {[file exists $lock_xdc]} {
    lappend allpairs64_constraints $lock_xdc
} else {
    puts "PUF_ALLPAIRS64_LOCK_STATUS=not-exported (baseline build path)"
}
add_files -fileset constrs_1 -norecurse $allpairs64_constraints

set_property top Puf_AllPairs64_Characterization_Top [get_filesets sources_1]
set_property top_auto_set false [get_filesets sources_1]
update_compile_order -fileset sources_1
if {[llength [get_ips -quiet]] != 0 ||
    [llength [get_files -all -quiet *.xci]] != 0} {
    error "Generated Xilinx IP unexpectedly entered the all-pairs64 project"
}
puts "PUF_ALLPAIRS64_PROJECT=[file join $build_dir ${project_name}.xpr]"
puts "PART=[get_property PART [current_project]] TOP=[get_property TOP [get_filesets sources_1]]"
close_project