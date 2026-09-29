# Compare two independently generated PicoRV32 final routed checkpoints.
# Metadata hashes may differ; logical topology, clock model and mandatory CPU
# structure must be identical, and both images must meet timing/route gates.
set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir audit_picorv32_final.tcl]

if {[llength $argv] != 2} {
    error "usage: compare_picorv32_final_repro.tcl <A.dcp> <B.dcp>"
}

proc repro_snapshot {dcp tag} {
    open_checkpoint $dcp
    if {[get_property TOP [current_design]] ne "Edge_Puf64_Zynq_PicoRV32_Final_100MHz_Top"} {
        error "REPRO gate: $tag has wrong top"
    }
    picorv32_final_audit "u_operational_uart/u_rv32_supervisor"

    set cells {}
    foreach c [get_cells -quiet -hierarchical] {
        lappend cells "${c}|[get_property REF_NAME $c]"
    }
    set nets [lsort -dictionary [get_nets -quiet -hierarchical]]
    set clocks {}
    foreach c [lsort -dictionary [get_clocks -quiet]] {
        lappend clocks "${c}|[get_property PERIOD $c]|[get_property WAVEFORM $c]"
    }
    if {[llength [get_clocks -quiet macro_clk]] != 0} {
        error "REPRO gate: $tag contains stale macro_clk"
    }
    set paths [get_timing_paths -quiet -max_paths 1 -delay_type max]
    if {[llength $paths] != 1 || [get_property SLACK [lindex $paths 0]] < 0.0} {
        error "REPRO gate: $tag fails setup timing"
    }
    set failed [get_nets -quiet -hierarchical -filter {ROUTE_STATUS == UNROUTED || ROUTE_STATUS == PARTIAL}]
    if {[llength $failed] != 0} {
        error "REPRO gate: $tag has [llength $failed] incomplete routes"
    }
    set snapshot [list [lsort -dictionary $cells] $nets $clocks]
    puts "PICORV32_REPRO_${tag}_PASS cells=[llength $cells] nets=[llength $nets] clocks=[llength $clocks] setup_slack=[get_property SLACK [lindex $paths 0]]"
    close_design
    return $snapshot
}

set a [repro_snapshot [file normalize [lindex $argv 0]] A]
set b [repro_snapshot [file normalize [lindex $argv 1]] B]
if {[lindex $a 0] ne [lindex $b 0]} { error "REPRO gate: A/B cell topology differs" }
if {[lindex $a 1] ne [lindex $b 1]} { error "REPRO gate: A/B net topology differs" }
if {[lindex $a 2] ne [lindex $b 2]} { error "REPRO gate: A/B clock model differs" }
puts "PICORV32_REPRO_TOPOLOGY_CLOCK_MATCH"
