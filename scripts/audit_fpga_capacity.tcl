# Fail immediately after synthesis when the design cannot fit the selected
# FPGA.  Vivado otherwise waits until place_design to raise DRC UTLZ-1.

proc report_and_audit_fpga_capacity {report_path} {
    report_utilization -file $report_path

    set channel [open $report_path r]
    set report_text [read $channel]
    close $channel

    if {![regexp -line \
            {^\| Slice LUTs\*[^|]*\|[[:space:]]*([0-9]+)[[:space:]]*\|[[:space:]]*([0-9]+)[[:space:]]*\|[[:space:]]*([0-9]+)[[:space:]]*\|} \
            $report_text unused used_luts fixed_luts available_luts]} {
        error "Unable to parse Slice LUT capacity from $report_path"
    }

    if {$used_luts > $available_luts} {
        error "FPGA LUT capacity exceeded after synthesis: used=$used_luts available=$available_luts"
    }

    puts "FPGA_SYNTH_CAPACITY_AUDIT=PASS slice_luts_used=$used_luts fixed=$fixed_luts available=$available_luts"
}
