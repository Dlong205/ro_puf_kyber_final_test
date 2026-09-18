# Program exactly one XC7Z020 with the diagnostic all-pairs64 image.
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
set bit_file [file join $root_dir build puf_allpairs64_characterization \
    puf_allpairs64_zynq7020.runs impl_1 Puf_AllPairs64_Characterization_Top.bit]
if {![file isfile $bit_file]} { error "All-pairs64 bitstream not found: $bit_file" }

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
puts "PUF_ALLPAIRS64_PROGRAM_PASS device=$device bitstream=$bit_file"
close_hw_manager