# Program exactly one XC7Z020 with the Phase B microbenchmark image.
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
set bit_file [file join $root_dir build puf64_microbench \
    puf64_microbench_zynq7020.runs impl_1 Puf64_Ro_Microbench_Zynq_Top.bit]
if {![file isfile $bit_file]} { error "Microbench bitstream not found: $bit_file" }

open_hw_manager
connect_hw_server
set hw_targets [get_hw_targets -quiet]
if {[llength $hw_targets] != 1} {
    close_hw_manager
    error "Expected exactly one JTAG target, found [llength $hw_targets]"
}
current_hw_target [lindex $hw_targets 0]
open_hw_target [lindex $hw_targets 0]
set devices [get_hw_devices -quiet -filter {PART =~ "xc7z020*"}]
if {[llength $devices] != 1} {
    close_hw_manager
    error "Expected exactly one XC7Z020, found [llength $devices]"
}
set device [lindex $devices 0]
current_hw_device $device
refresh_hw_device $device
set_property PROGRAM.FILE $bit_file $device
program_hw_devices $device
refresh_hw_device $device
puts "PUF64_MICROBENCH_PROGRAM_PASS device=$device bitstream=$bit_file"
close_hw_manager
