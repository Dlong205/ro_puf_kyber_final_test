# Program exactly one connected XC7A35T with the volatile diagnostic image.
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
set bit_file [file join $root_dir build arty_puf_characterization \
    puf_characterization_arty_a7_35t.runs impl_1 Puf_Characterization_Top.bit]
if {![file isfile $bit_file]} {error "Arty PUF bitstream missing: $bit_file"}

open_hw_manager
connect_hw_server
set targets [get_hw_targets -quiet]
if {[llength $targets] != 1} {error "Expected one JTAG target"}
current_hw_target [lindex $targets 0]
open_hw_target
set devices [get_hw_devices -quiet -filter {PART =~ "xc7a35t*"}]
if {[llength $devices] != 1} {error "Expected one XC7A35T"}
set device [lindex $devices 0]
current_hw_device $device
refresh_hw_device $device
set_property PROGRAM.FILE $bit_file $device
program_hw_devices $device
refresh_hw_device $device
puts "ARTY_PUF_PROGRAM_PASS device=$device bitstream=$bit_file"
close_hw_manager
