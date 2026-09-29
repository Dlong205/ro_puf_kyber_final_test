# Program exactly one XC7Z020 with the macro-V2 characterization image ONLY.
# This script can never program a golden/operational bitstream: the bit path
# is fixed to the V2 char build.  Reports PROGRAM_PASS on success.
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
set bit_file [file join $root_dir build puf64_macrov2_characterization \
    puf64_macrov2_char_zynq7020.runs impl_1 Puf64_MacroV2_Characterization_Top.bit]
set EXPECTED_SHA "cfc72674b654d1f44d5fcb0eed8ed7dc51b2b27a7f8ed9283c7ad6d1878699bd"
if {![file isfile $bit_file]} { error "Macro-V2 char bitstream not found: $bit_file" }
source [file join $script_dir ro_physical_common.tcl]
set actual_sha [ro_sha256_file $bit_file]
if {$actual_sha ne $EXPECTED_SHA} {
    error "Macro-V2 bitstream SHA mismatch: expected=$EXPECTED_SHA actual=$actual_sha (refusing to program)"
}
puts "R4_PROGRAM_BITSTREAM_SHA_OK=$actual_sha"

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
puts "R4_PROGRAM_DEVICE part=[get_property PART $device] idcode=[get_property IDCODE $device]"
set_property PROGRAM.FILE $bit_file $device
program_hw_devices $device
refresh_hw_device $device
puts "PUF64_MACROV2_PROGRAM_PASS device=$device bitstream=$bit_file sha=$actual_sha"
close_hw_manager
