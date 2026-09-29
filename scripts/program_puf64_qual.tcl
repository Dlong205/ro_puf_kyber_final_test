# R6.3 program the operational-qualification image (NONRELEASE, bench only).
# Exact-SHA gate: suffix A|B selects the R6.2-reproducible qual bitstream;
# the caller must also pass the expected SHA-256 (no default), so a stale or
# unreviewed bitstream fails closed.  Refuses the gen1/gen2/final SHAs by
# construction (only the qual run bitstreams are addressable here).
# Usage:
#   vivado -mode batch -nolog -nojournal \
#     -source scripts/program_puf64_qual.tcl \
#     -tclargs A a9ffce0e... (64 hex)
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
source [file join $script_dir ro_physical_common.tcl]

if {[llength $argv] != 2 || [lindex $argv 0] ni {"A" "B"} || \
    ![regexp {^[0-9a-f]{64}$} [lindex $argv 1]]} {
    error "usage: program_puf64_qual.tcl <A|B> <expected-bitstream-sha256>"
}
set suffix [lindex $argv 0]
set expected_sha [lindex $argv 1]
puts "QUAL_PROGRAM_NONRELEASE_WARNING: bench qualification image, never a release"
set bit_file [file join $root_dir build puf64_qual_${suffix} \
    puf64_qual_zynq7020_${suffix}.runs impl_1 \
    Edge_Puf64_Zynq_PicoRV32_Final_100MHz_Top.bit]
if {![file isfile $bit_file]} { error "Qual bitstream missing: $bit_file" }
set actual_sha [ro_sha256_file $bit_file]
if {$actual_sha ne $expected_sha} {
    error "Qual SHA mismatch: expected=$expected_sha actual=$actual_sha"
}
puts "QUAL_PROGRAM_SHA_OK=$actual_sha suffix=$suffix"

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
puts "QUAL_PROGRAM_DEVICE part=[get_property PART $device] idcode=[get_property IDCODE $device]"
set_property PROGRAM.FILE $bit_file $device
program_hw_devices $device
refresh_hw_device $device
puts "QUAL_PROGRAM_PASS device=$device sha=$actual_sha"
close_hw_manager
