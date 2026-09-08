# Create an isolated full-SoC project with the accepted RC1 RO physical lock.
# The normal release project and bitstream are never overwritten.

set_param general.maxThreads 1
set wrapper_dir [file dirname [file normalize [info script]]]
set wrapper_root [file normalize [file join $wrapper_dir ..]]
set run_id locked_a
if {[llength $argv] > 0} {
    set run_id [lindex $argv 0]
}
if {![regexp {^[A-Za-z0-9_-]+$} $run_id]} {
    error "Invalid reproducibility run id: $run_id"
}

set soc_build_dir_override [file join $wrapper_root build soc_repro $run_id]
set soc_project_name_override "kyber_ro_puf_${run_id}"
set soc_extra_constraints [list [file join $wrapper_root constraints \
    ro_physical_lock_rc1_zynq7020.xdc]]
source [file join $wrapper_dir create_project.tcl]
