# Validate that the accepted source DCP still reproduces the fingerprint from
# which the physical lock was exported. Application of the lock itself must be
# tested on a clean implementation; Vivado deliberately rejects changing
# LOCK_PINS on cells that are already placed in a routed checkpoint.

set_param general.maxThreads 1
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
set checkpoint [file join $root_dir build vivado \
    kyber_ro_puf_zynq7020.runs impl_1 Kyber_System_Top_routed.dcp]
set golden_fingerprint [file join $root_dir constraints \
    ro_physical_fingerprint_rc1_zynq7020.tsv]
set actual_fingerprint [file join $root_dir build ro_lock_validation \
    source_checkpoint_fingerprint.tsv]
if {[llength $argv] > 0} {
    set checkpoint [file normalize [lindex $argv 0]]
}
if {[llength $argv] > 1} {
    set actual_fingerprint [file normalize [lindex $argv 1]]
}
if {[llength $argv] > 2} {
    error "Usage: validate_ro_lock_checkpoint.tcl ?routed.dcp? ?output.tsv?"
}
if {![file isfile $checkpoint]} {
    error "Routed checkpoint not found: $checkpoint"
}

source [file join $script_dir ro_physical_common.tcl]
file mkdir [file dirname $actual_fingerprint]
open_checkpoint $checkpoint
set inventory [ro_collect_physical_inventory]
ro_write_physical_fingerprint $actual_fingerprint $inventory
ro_compare_physical_fingerprints $golden_fingerprint $actual_fingerprint
puts "RO_SOURCE_CHECKPOINT_LOCK_VALIDATION=PASS"
puts "RO_VALIDATED_CHECKPOINT=$checkpoint"
puts "RO_VALIDATED_FINGERPRINT=$actual_fingerprint"
close_design
