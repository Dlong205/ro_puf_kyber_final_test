# Inspect RO objects in the synthesized checkpoint without modifying it.
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
set checkpoint [file join $root_dir build vivado kyber_ro_puf_zynq7020.runs synth_1 Kyber_System_Top.dcp]
if {![file exists $checkpoint]} {
    error "Synthesis checkpoint not found: $checkpoint"
}

open_checkpoint $checkpoint
set ro_cells [get_cells -quiet -hierarchical -filter {NAME =~ "*u_puf*ring*"}]
set ro_luts [get_cells -quiet -hierarchical -filter {NAME =~ "*u_puf*ring*LUT6*"}]
set ro_nets [get_nets -quiet -hierarchical -filter {NAME =~ "*u_puf*ring*"}]
set ro_feedback_nets [get_nets -quiet -hierarchical -filter {NAME =~ "*u_puf*ring*/t*"}]
puts "RO_CELL_COUNT=[llength $ro_cells]"
puts "RO_LUT_COUNT=[llength $ro_luts]"
puts "RO_NET_COUNT=[llength $ro_nets]"
puts "RO_FEEDBACK_NET_COUNT=[llength $ro_feedback_nets]"
puts "RO_LUT_SAMPLE=[lrange $ro_luts 0 7]"
puts "RO_NET_SAMPLE=[lrange $ro_nets 0 15]"
foreach cell [lrange $ro_cells 0 7] {
    puts "RO_CELL_DETAIL=$cell REF=[get_property REF_NAME $cell]"
}
read_xdc [file join $root_dir constraints kp_zynq_7020.xdc]
set constrained_ro_nets [filter $ro_feedback_nets {ALLOW_COMBINATORIAL_LOOPS == 1}]
puts "RO_ALLOW_LOOP_COUNT=[llength $constrained_ro_nets]"
close_design
