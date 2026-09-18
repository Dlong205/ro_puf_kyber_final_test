# Create the Phase B PUF64 single-RO microbenchmark project for Zynq-7020.
set_param general.maxThreads 1
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
set build_dir [file join $root_dir build puf64_microbench]
set project_name puf64_microbench_zynq7020

file mkdir $build_dir
create_project $project_name $build_dir -part xc7z020clg400-2 -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

set sources [list \
    [file join $root_dir rtl top Puf64_Ro_Microbench_Zynq_Top.sv] \
    [file join $root_dir rtl debug puf64_ro_microbench.sv] \
    [file join $root_dir rtl puf kp_ro_cell.sv] \
    [file join $root_dir rtl puf kp_ro_cell_xilinx.sv] \
    [file join $root_dir rtl puf uart_rx.v] \
    [file join $root_dir rtl puf uart_tx.v]]
foreach source $sources {
    if {![file exists $source]} { error "Missing microbench source: $source" }
}
add_files -norecurse $sources
add_files -fileset constrs_1 -norecurse [list \
    [file join $root_dir constraints puf64_microbench_zynq7020.xdc]]

set placement_xdc [file join $root_dir constraints puf64_microbench_placement.xdc]
if {[info exists ::env(PUF64_MICROBENCH_PLACEMENT)] &&
    $::env(PUF64_MICROBENCH_PLACEMENT) eq "1" && [file exists $placement_xdc]} {
    add_files -fileset constrs_1 -norecurse [list $placement_xdc]
    puts "PUF64_MICROBENCH_PLACEMENT=applied:$placement_xdc"
} else {
    puts "PUF64_MICROBENCH_PLACEMENT=auto-place"
}

set lockpins_xdc [file join $root_dir constraints puf64_microbench_lockpins.xdc]
if {[info exists ::env(PUF64_MICROBENCH_LOCKPINS)] &&
    $::env(PUF64_MICROBENCH_LOCKPINS) eq "1" && [file exists $lockpins_xdc]} {
    add_files -fileset constrs_1 -norecurse [list $lockpins_xdc]
    puts "PUF64_MICROBENCH_LOCKPINS=applied:$lockpins_xdc"
} else {
    puts "PUF64_MICROBENCH_LOCKPINS=none"
}

set route_xdc [file join $root_dir constraints puf64_microbench_route.xdc]
if {[info exists ::env(PUF64_MICROBENCH_ROUTE)] &&
    $::env(PUF64_MICROBENCH_ROUTE) eq "1" && [file exists $route_xdc]} {
    add_files -fileset constrs_1 -norecurse [list $route_xdc]
    puts "PUF64_MICROBENCH_ROUTE=applied:$route_xdc"
} else {
    puts "PUF64_MICROBENCH_ROUTE=none"
}

set_property top Puf64_Ro_Microbench_Zynq_Top [get_filesets sources_1]
set_property top_auto_set false [get_filesets sources_1]
update_compile_order -fileset sources_1
if {[llength [get_ips -quiet]] != 0 || [llength [get_files -all -quiet *.xci]] != 0} {
    error "Generated Xilinx IP unexpectedly entered the microbench project"
}
puts "PUF64_MICROBENCH_PROJECT=[file join $build_dir ${project_name}.xpr]"
close_project
