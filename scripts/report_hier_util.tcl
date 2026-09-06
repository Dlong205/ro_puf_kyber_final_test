# Generate a hierarchical utilization report from an existing Vivado
# checkpoint.  Usage:
#   vivado -mode batch -source scripts/report_hier_util.tcl \
#     -tclargs <checkpoint.dcp> <report.rpt>

if {$argc != 2} {
    error "usage: report_hier_util.tcl <checkpoint.dcp> <report.rpt>"
}

set checkpoint [file normalize [lindex $argv 0]]
set report_path [file normalize [lindex $argv 1]]

open_checkpoint $checkpoint
report_utilization -hierarchical -hierarchical_depth 8 -file $report_path
close_design

