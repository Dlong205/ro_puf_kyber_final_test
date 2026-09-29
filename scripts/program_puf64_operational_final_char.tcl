# Program exactly one XC7Z020 with the R7 final-char image (NONRELEASE,
# bench-only characterization build of the final top: telemetry readout on,
# INFO marker 0x71, same frozen macro/mapping/anchor as release).
# The caller must provide the exact expected BIT SHA-256 (no default).
# Usage:
#   vivado -mode batch -nolog -nojournal \
#     -source scripts/program_puf64_operational_final_char.tcl \
#     -tclargs <expected-bitstream-sha256>
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
source [file join $script_dir ro_physical_common.tcl]

if {[llength $argv] != 1 || ![regexp {^[0-9a-f]{64}$} [lindex $argv 0]]} {
    error "usage: program_puf64_operational_final_char.tcl <expected-bitstream-sha256>"
}
set expected_sha [lindex $argv 0]
puts "FINAL_CHAR_PROGRAM_NONRELEASE_WARNING: bench characterization image, never a release"
set bit_file [file join $root_dir build puf64_operational_final_char \
    puf64_operational_final_char_zynq7020.runs impl_1 \
    Edge_Puf64_Zynq_Operational_Final_100MHz_Top.bit]
if {![file isfile $bit_file]} { error "Final-char bitstream missing: $bit_file" }
set actual_sha [ro_sha256_file $bit_file]
if {$actual_sha ne $expected_sha} {
    error "Final-char SHA mismatch: expected=$expected_sha actual=$actual_sha"
}
puts "FINAL_CHAR_PROGRAM_SHA_OK=$actual_sha"

open_hw_manager
connect_hw_server
set targets [get_hw_targets -quiet]
if {[llength $targets] != 1} {
    close_hw_manager
    error "Expected exactly one JTAG target, found [llength $targets]"
}
current_hw_target [lindex $targets 0]
open_hw_target [lindex $targets 0]
set devices [get_hw_devices -quiet -filter {PART =~ "xc7z020*"}]
if {[llength $devices] != 1} {
    close_hw_manager
    error "Expected exactly one XC7Z020, found [llength $devices]"
}
set device [lindex $devices 0]
current_hw_device $device
refresh_hw_device $device
puts "FINAL_CHAR_PROGRAM_DEVICE part=[get_property PART $device] idcode=[get_property IDCODE $device]"
set_property PROGRAM.FILE $bit_file $device
program_hw_devices $device
refresh_hw_device $device
puts "FINAL_CHAR_PROGRAM_PASS device=$device sha=$actual_sha"
close_hw_manager
