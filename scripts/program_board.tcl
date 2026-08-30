# Program exactly one connected XC7Z020 device with the standalone bitstream.
# This changes only volatile FPGA configuration; it does not write QSPI flash.

set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
set bit_candidates [glob -nocomplain \
    [file join $root_dir build vivado kyber_ro_puf_zynq7020.runs impl_1 *.bit]]
if {[llength $bit_candidates] == 0 &&
    [file isfile [file join $root_dir Kyber_System_Top.bit]]} {
    set bit_candidates [list [file join $root_dir Kyber_System_Top.bit]]
}
if {[llength $bit_candidates] != 1} {
    error "Expected exactly one rebuilt or checked-in bitstream, found [llength $bit_candidates]"
}

open_hw_manager
connect_hw_server
set hw_targets [get_hw_targets -quiet]
if {[llength $hw_targets] != 1} {
    close_hw_manager
    error "Expected exactly one JTAG target, found [llength $hw_targets]. Check board power and JTAG cable."
}
current_hw_target [lindex $hw_targets 0]
open_hw_target [lindex $hw_targets 0]
set zynq_devices [get_hw_devices -quiet -filter {PART =~ "xc7z020*"}]
if {[llength $zynq_devices] != 1} {
    error "Expected exactly one XC7Z020 on JTAG, found [llength $zynq_devices]"
}

set device [lindex $zynq_devices 0]
current_hw_device $device
refresh_hw_device $device
set_property PROGRAM.FILE [lindex $bit_candidates 0] $device
program_hw_devices $device
refresh_hw_device $device
puts "PROGRAM_PASS device=$device bitstream=[lindex $bit_candidates 0]"
close_hw_manager
