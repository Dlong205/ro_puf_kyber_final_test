# Create the C1-C4 diagnostic RO bench project (NUM_RO via -tclargs).
set_param general.maxThreads 1
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
set build_dir [file join $root_dir build puf64_bench]
set project_name puf64_bench_zynq7020
set num_ro 4
if {[llength $argv] > 0} { set num_ro [lindex $argv 0] }

file mkdir $build_dir
create_project $project_name $build_dir -part xc7z020clg400-2 -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

set sources [list \
    [file join $root_dir rtl top Puf64_Ro_Bench_Zynq_Top.sv] \
    [file join $root_dir rtl debug puf64_ro_bench.sv] \
    [file join $root_dir rtl debug kp_ripple_counter.sv] \
    [file join $root_dir rtl debug puf64_bench_diag.sv] \
    [file join $root_dir rtl puf kp_ro_cell.sv] \
    [file join $root_dir rtl puf kp_ro_cell_xilinx.sv] \
    [file join $root_dir rtl puf uart_rx.v] \
    [file join $root_dir rtl puf uart_tx.v]]
foreach source $sources {
    if {![file exists $source]} { error "Missing bench source: $source" }
}
add_files -norecurse $sources
add_files -fileset constrs_1 -norecurse [list \
    [file join $root_dir constraints puf64_bench_zynq7020.xdc]]

set wrapper [file join $build_dir puf64_bench_top.sv]
set fh [open $wrapper w]
puts $fh "module puf64_bench_top ("
puts $fh "    input  wire       CLK50MHZ,"
puts $fh "    input  wire [1:0] SW,"
puts $fh "    input  wire       UART_RXD,"
puts $fh "    output wire       UART_TXD,"
puts $fh "    output wire [1:0] LED"
puts $fh ");"
puts $fh "    Puf64_Ro_Bench_Zynq_Top #(.NUM_RO($num_ro)) u_core ("
puts $fh "        .CLK50MHZ(CLK50MHZ), .SW(SW), .UART_RXD(UART_RXD),"
puts $fh "        .UART_TXD(UART_TXD), .LED(LED));"
puts $fh "endmodule"
close $fh
add_files -norecurse [list $wrapper]
foreach {flag stem} {
    PUF64_BENCH_PLACEMENT puf64_bench_placement
    PUF64_BENCH_LOCKPINS puf64_bench_lockpins
    PUF64_BENCH_ROUTE puf64_bench_route
} {
    set path [file join $root_dir constraints ${stem}_n${num_ro}.xdc]
    if {[info exists ::env($flag)] && $::env($flag) eq "1" && [file exists $path]} {
        add_files -fileset constrs_1 -norecurse [list $path]
        puts "PUF64_BENCH_${flag}=applied"
    } else {
        puts "PUF64_BENCH_${flag}=none"
    }
}
set_property top puf64_bench_top [get_filesets sources_1]
set_property top_auto_set false [get_filesets sources_1]
update_compile_order -fileset sources_1
puts "PUF64_BENCH_PROJECT=[file join $build_dir ${project_name}.xpr] num_ro=$num_ro"
close_project
