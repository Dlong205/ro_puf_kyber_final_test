# Vivado non-project, isolated OOC synthesis. No implementation/bitstream.
set_param general.maxThreads 1
set here [file dirname [file normalize [info script]]]
source [file join $here sources.tcl]
if {[llength $argv] != 3} {
    error "usage: synth_block.tcl <block> <part> <absolute-output-directory>"
}
lassign $argv block part out_dir
set top [fpga_split::top $block]
if {![regexp {^xc7[A-Za-z0-9-]+$} $part]} {error "Invalid part string"}
if {[llength [get_parts -quiet $part]] != 1} {
    error "Exact target part not installed or ambiguous: $part"
}
set out_dir [file normalize $out_dir]
if {[file exists [file join $out_dir COMPLETE]]} {
    error "Completed output directory already exists: $out_dir"
}
file mkdir $out_dir
create_project -in_memory -part $part
set_property target_language Verilog [current_project]
set_property include_dirs [fpga_split::includes] [current_fileset]
foreach path [fpga_split::sources $block] {
    if {[file extension $path] eq ".sv"} {
        read_verilog -sv $path
    } else {
        read_verilog $path
    }
}
read_xdc [file join $here clock_50mhz.xdc]
synth_design -mode out_of_context -top $top -part $part \
    -flatten_hierarchy rebuilt
if {[llength [get_cells -hier -quiet -filter {IS_BLACKBOX == 1}]] != 0} {
    error "Unresolved black boxes in OOC design"
}
# All real top-level outputs are ports. In particular K/seed/key/PUF response
# must not be tied off just to make an artificial small resource estimate.
set required_bus [dict get [dict create client K server K edgecore shared_secret edgefull shared_secret kdf seed_out \
    seedctl seed_ fe key_out puf response] $block]
set observable [get_ports -quiet "${required_bus}*"]
set required_width [dict get [dict create client 256 server 256 edgecore 256 edgefull 256 kdf 512 \
    seedctl 512 fe 192 puf 264] $block]
if {[llength $observable] != $required_width} {
    error "Required output bus was lost: $required_bus"
}
if {$block in {puf edgefull}} {
    set ro_luts [get_cells -hier -quiet -filter \
        {NAME =~ "*ring*LUT6*"}]
    if {[llength $ro_luts] != 128} {
        error "Expected 128 physical Xilinx RO LUTs, got [llength $ro_luts]"
    }
}
report_utilization -file [file join $out_dir utilization.rpt]
report_utilization -hierarchical -hierarchical_depth 8 \
    -file [file join $out_dir hierarchy.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
    -file [file join $out_dir timing_preliminary.rpt]
check_timing -verbose -file [file join $out_dir check_timing.rpt]
write_checkpoint [file join $out_dir synthesized.dcp]
set fd [open [file join $out_dir metadata.tsv] w]
puts $fd "block\t$block"
puts $fd "top\t$top"
puts $fd "part\t$part"
puts $fd "clock_period_ns\t20.000"
puts $fd "flow\tsynthesis_out_of_context_only"
puts $fd "vivado\t[version -short]"
puts $fd "k\t[expr {$block in {client server edgecore edgefull} ? 2 : {not_applicable}}]"
puts $fd "puf_backend\t[expr {$block in {puf edgefull} ? {xilinx_lut} : {not_applicable}}]"
close $fd
set fd [open [file join $out_dir COMPLETE] w]
puts $fd "OOC_SYNTH_PASS block=$block top=$top part=$part"
close $fd
puts "FPGA_SPLIT_OOC_PASS block=$block top=$top part=$part"
close_project
