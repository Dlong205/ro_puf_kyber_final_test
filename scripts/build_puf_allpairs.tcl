# Build and audit the isolated 496-candidate characterization image.
set_param general.maxThreads 1
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
set project_file [file join $root_dir build puf_allpairs_characterization \
    puf_allpairs_zynq7020.xpr]
set report_dir [file join $root_dir reports puf_allpairs_characterization]
set placement_map [file join $root_dir constraints ro_placement_rc1_zynq7020.xdc]
set lock_xdc [file join $root_dir constraints ro_physical_lock_allpairs_zynq7020.xdc]
set golden_fingerprint [file join $root_dir constraints \
    ro_physical_fingerprint_allpairs_zynq7020.tsv]
source [file join $script_dir audit_ro_placement.tcl]
source [file join $script_dir ro_physical_common.tcl]

if {![file exists $project_file]} { error "All-pairs project not found" }
file mkdir $report_dir
open_project $project_file
set commit_hash [exec git -C $root_dir rev-parse HEAD]
set build_datetime [clock format [clock seconds] -gmt true -format "%Y-%m-%d %H:%M:%S UTC"]
puts "PUF_ALLPAIRS_BUILD_COMMIT=$commit_hash"
puts "PUF_ALLPAIRS_BUILD_DATETIME=$build_datetime"
set lock_in_cs [expr {[file exists $lock_xdc] &&
    [llength [get_files -quiet -of_objects [get_filesets constrs_1]]] > 0}]
puts "PUF_ALLPAIRS_LOCK_IN_PROJECT=$lock_in_cs"
reset_run synth_1
launch_runs synth_1 -jobs 1
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
puts "PUF_ALLPAIRS_SYNTH_STATUS=$synth_status"
if {![string match "*Complete*" $synth_status]} {
    error "All-pairs synthesis failed: $synth_status"
}

open_run synth_1
set ro_luts [get_cells -quiet -hierarchical -filter {NAME =~ "*u_puf*ring*LUT6*"}]
puts "PUF_ALLPAIRS_SYNTH_RO_LUT_COUNT=[llength $ro_luts]"
if {[llength $ro_luts] != 128} { error "Expected 128 RO LUTs" }
audit_ro_placement $placement_map
report_utilization -file [file join $report_dir post_synth_utilization.rpt]
close_design

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 1
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
puts "PUF_ALLPAIRS_IMPL_STATUS=$impl_status"
if {![string match "*Complete*" $impl_status]} {
    error "All-pairs implementation failed: $impl_status"
}

open_run impl_1
set placed_ro_luts [get_cells -quiet -hierarchical -filter {NAME =~ "*u_puf*ring*LUT6*"}]
puts "PUF_ALLPAIRS_ROUTE_RO_LUT_COUNT=[llength $placed_ro_luts]"
if {[llength $placed_ro_luts] != 128} { error "RO placement map incomplete" }
audit_ro_placement $placement_map
report_utilization -file [file join $report_dir post_route_utilization.rpt]
report_timing_summary -file [file join $report_dir post_route_timing.rpt]
report_route_status -file [file join $report_dir post_route_status.rpt]
report_drc -file [file join $report_dir post_route_drc.rpt]
report_methodology -file [file join $report_dir post_route_methodology.rpt]

set fingerprint_report [file join $report_dir ro_physical_fingerprint.tsv]
set inventory [ro_collect_physical_inventory]
ro_write_physical_fingerprint $fingerprint_report $inventory
set fingerprint_state OK
if {[file exists $golden_fingerprint]} {
    if {[catch {ro_compare_physical_fingerprints \
            $golden_fingerprint $fingerprint_report} compare_error]} {
        set fingerprint_state MISMATCH
        puts "PUF_ALLPAIRS_FINGERPRINT_ERROR=$compare_error"
    }
} else {
    set fingerprint_state NO-GOLDEN
}
puts "PUF_ALLPAIRS_FINGERPRINT_STATUS=$fingerprint_state"
close_design

set bitstream [file join $root_dir build puf_allpairs_characterization \
    puf_allpairs_zynq7020.runs impl_1 Puf_AllPairs_Characterization_Top.bit]
set routed_dcp [file join $root_dir build puf_allpairs_characterization \
    puf_allpairs_zynq7020.runs impl_1 Puf_AllPairs_Characterization_Top_routed.dcp]
set bitstream_sha [ro_sha256_file $bitstream]
set routed_dcp_sha [ro_sha256_file $routed_dcp]
set metadata_file [file join $report_dir build_metadata.tsv]
set metadata_channel [open $metadata_file w]
puts $metadata_channel "commit\t$commit_hash"
puts $metadata_channel "build_datetime\t$build_datetime"
puts $metadata_channel "bitstream_sha256\t$bitstream_sha"
puts $metadata_channel "routed_dcp_sha256\t$routed_dcp_sha"
puts $metadata_channel "lock_in_project\t$lock_in_cs"
puts $metadata_channel "fingerprint_status\t$fingerprint_state"
puts $metadata_channel "part\txc7z020clg400-2"
puts $metadata_channel "top\tPuf_AllPairs_Characterization_Top"
puts $metadata_channel "protocol\t2.0"
puts $metadata_channel "ref_cycles\t255"
close $metadata_channel
if {$fingerprint_state eq "MISMATCH"} {
    error "All-pairs build broke the accepted RO physical fingerprint"
}
close_project
