# Standalone routed-DCP check for the mandatory PicoRV32 control plane.
# Usage: vivado -mode batch -source check_picorv32_final_netlist.tcl -tclargs <dcp>
set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir audit_picorv32_final.tcl]

if {[llength $argv] != 1} {
    error "usage: check_picorv32_final_netlist.tcl <routed.dcp>"
}
set dcp [file normalize [lindex $argv 0]]
if {![file isfile $dcp]} { error "routed DCP not found: $dcp" }
open_checkpoint $dcp
if {[get_property TOP [current_design]] ne "Edge_Puf64_Zynq_PicoRV32_Final_100MHz_Top"} {
    error "PICORV32 gate: wrong routed top"
}
picorv32_final_audit "u_operational_uart/u_rv32_supervisor"
close_design
