# Create the isolated macro-V2 characterization project for Zynq-7020.
# NEW image: never touches the golden all-pairs64 project/bitstream.  The PUF
# macro enters ONLY as a black box (kp_puf64_macro_v2_bb.sv); the real macro
# RTL is never in this source list (bound later with read_checkpoint -cell).
set_param general.maxThreads 1
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
set build_dir [file join $root_dir build puf64_macrov2_characterization]
set project_name puf64_macrov2_char_zynq7020

file mkdir $build_dir
create_project $project_name $build_dir -part xc7z020clg400-2 -force
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

set sources [list \
    [file join $root_dir rtl top Puf64_MacroV2_Characterization_Top.sv] \
    [file join $root_dir rtl top puf_allpairs_uart_v2.sv] \
    [file join $root_dir rtl puf kp_puf64_macro_v2_bb.sv] \
    [file join $root_dir rtl puf uart_rx.v] \
    [file join $root_dir rtl puf uart_tx.v]]

foreach source $sources {
    if {![file exists $source]} { error "Missing macro-V2 char source: $source" }
}
add_files -norecurse $sources

set board_xdc [file join $root_dir constraints puf64_macrov2_char_zynq7020.xdc]
if {![file exists $board_xdc]} { error "Missing macro-V2 char XDC: $board_xdc" }
add_files -fileset constrs_1 -norecurse [list $board_xdc]

set_property top Puf64_MacroV2_Characterization_Top [get_filesets sources_1]
set_property top_auto_set false [get_filesets sources_1]
update_compile_order -fileset sources_1
if {[llength [get_ips -quiet]] != 0 || \
    [llength [get_files -all -quiet *.xci]] != 0} {
    error "Generated Xilinx IP unexpectedly entered the macro-V2 project"
}
# Fail closed if the real macro RTL (not the stub) entered synthesis.
foreach bad [list "*kp_puf64_macro_v2.sv" "*puf64_ro_bench_v2.sv" \
        "*kp_ripple_counter_v2.sv" "*Puf_AllPairs64_Characterization_Top.sv" \
        "*puf_allpairs_uart.sv" "*puf64_ro_bench.sv" "*kp_ripple_counter.sv"] {
    if {[llength [get_files -quiet $bad]] != 0} {
        # The stub matches *kp_puf64_macro_v2.sv too; allow exactly that one.
        set hits [get_files -quiet $bad]
        set ok 0
        if {$bad eq "*kp_puf64_macro_v2.sv" && [llength $hits] == 1 && \
            [string match "*_bb.sv" [lindex $hits 0]]} { set ok 1 }
        if {!$ok} { error "R3 gate: forbidden source in project: $bad ($hits)" }
    }
}
puts "R3_MACROV2_PROJECT=[file join $build_dir ${project_name}.xpr]"
puts "PART=[get_property PART [current_project]] TOP=[get_property TOP [get_filesets sources_1]]"
close_project
