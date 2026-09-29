# I4.2: candidate expanded fingerprint (operational hierarchy).
# Same V1 format as the golden exporter; the hierarchy prefix is stripped to
# ro[...]/... relative paths so the comparison is prefix-insensitive but
# physical-exact.  Run under Vivado 2020.1 after implementation.
#
# Usage:
#   vivado -mode batch -nolog -nojournal \
#     -source scripts/export_puf64_operational_candidate_fingerprint.tcl \
#     -tclargs <candidate_routed.dcp> <output.tsv>
set_param general.maxThreads 1
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
source [file join $script_dir ro_physical_common.tcl]

if {[llength $argv] < 2} {
    error "usage: export_puf64_operational_candidate_fingerprint.tcl <routed.dcp> <output.tsv>"
}
set checkpoint [file normalize [lindex $argv 0]]
set out_path [file normalize [lindex $argv 1]]
if {![file isfile $checkpoint]} { error "I4 candidate DCP missing: $checkpoint" }
set dcp_sha [ro_sha256_file $checkpoint]
puts "I4_CANDIDATE_DCP_SHA=$dcp_sha"

open_checkpoint $checkpoint

# Operational physical prefix must exist exactly once per physical cell.
set prefix_cells [get_cells -quiet -hierarchical \
    -filter {NAME =~ "*u_operational_uart/u_chain/u_puf64_core/u_puf64_physical/u_puf*"}]
if {[llength $prefix_cells] == 0} {
    error "I4 hierarchy gate: operational physical prefix not found in netlist"
}

set ro_luts [get_cells -quiet -hierarchical \
    -filter {NAME =~ "*u_puf*ro_cell*/u_backend/LUT6_*"}]
set presc [get_cells -quiet -hierarchical \
    -filter {NAME =~ "*counter/presc_fdce" && REF_NAME == "FDCE"}]
set stages [get_cells -quiet -hierarchical \
    -filter {REF_NAME == "FDCE" && NAME =~ "*stage*ff*"}]
if {[llength $ro_luts] != 256} { error "I4 candidate gate: expected 256 RO LUTs, found [llength $ro_luts]" }
if {[llength $presc] != 64} { error "I4 candidate gate: expected 64 prescalers, found [llength $presc]" }
if {[llength $stages] != 1088} { error "I4 candidate gate: expected 1088 ripple stages, found [llength $stages]" }

proc i4_relative {full} {
    set idx [string first "u_puf/" $full]
    if {$idx < 0} { return $full }
    return [string range $full [expr {$idx + 6}] end]
}
proc i4_clock_class {net} {
    set pins [get_pins -quiet -leaf -of_objects [get_nets -quiet -segments $net]]
    set cells [get_cells -quiet -of_objects $pins]
    foreach cell $cells {
        set ref [get_property REF_NAME $cell]
        if {$ref eq "BUFG" || $ref eq "BUFGCTRL" || $ref eq "BUFH" || \
            $ref eq "BUFHCE" || $ref eq "BUFR"} {
            return "GLOBAL_BUFFER:$ref"
        }
    }
    return "LOCAL_ROUTE"
}

file mkdir [file dirname $out_path]
set ch [open $out_path w]
puts $ch "I4_EXPANDED_FINGERPRINT_V1"
puts $ch "CANDIDATE_DCP_SHA\t$dcp_sha"
puts $ch "SUMMARY\tro_luts=256\tprescaler=64\tripple_stages=1088"

foreach cell [lsort -dictionary [concat $ro_luts $presc $stages]] {
    set ref [get_property REF_NAME $cell]
    set init [get_property INIT $cell]
    set loc [get_property LOC $cell]
    set bel [get_property BEL $cell]
    if {$ref eq "" || $loc eq "" || $bel eq ""} {
        close $ch
        error "I4 candidate gate: missing placement for $cell"
    }
    if {$init eq ""} { set init "-" }
    set pinmap [join [ro_actual_input_pin_map $cell] ,]
    if {$pinmap eq ""} { set pinmap "-" }
    set lockpins [get_property LOCK_PINS $cell]
    if {$lockpins eq ""} { set lockpins "-" } else { set lockpins [ro_normalize_space $lockpins] }
    puts $ch "CELL\t[i4_relative $cell]\t$ref\t$init\t$loc\t$bel\t$pinmap\t$lockpins"
}
foreach p [lsort -dictionary $presc] {
    set cpin [get_pins -quiet -of_objects $p -filter {REF_PIN_NAME == "C"}]
    set nets [get_nets -quiet -of_objects $cpin]
    set net [lindex $nets 0]
    set route [ro_normalize_space [get_property ROUTE $net]]
    if {$route eq ""} { close $ch; error "I4 candidate gate: ro_tap not routed: $net" }
    set allpins [lsort -dictionary [get_pins -quiet -leaf -of_objects [get_nets -quiet -segments $net]]]
    set driver ""
    foreach pin $allpins {
        if {[get_property DIRECTION $pin] eq "OUT"} { lappend driver $pin }
    }
    set sinks {}
    foreach pin $allpins {
        if {[get_property DIRECTION $pin] eq "IN"} { lappend sinks $pin }
    }
    if {[llength $driver] != 1} { close $ch; error "I4 candidate gate: ro_tap driver != 1 on $net: $driver" }
    if {[string first "ro_cell" [lindex $driver 0]] < 0} { close $ch; error "I4 candidate gate: ro_tap driver is not an RO cell: [lindex $driver 0]" }
    set relsinks {}
    foreach s $sinks { lappend relsinks [i4_relative $s] }
    set tclass [i4_clock_class $net]
    if {[string match "GLOBAL_BUFFER:*" $tclass]} { close $ch; error "I4 candidate gate: ro_tap uses global buffer: $net" }
    puts $ch "TAP\t[i4_relative $net]\tdriver=[i4_relative [lindex $driver 0]]\tsinks=[join [lsort -dictionary $relsinks] ,]\troute=$route\tclass=$tclass"
}
set ripple_count 0
foreach s [lsort -dictionary $stages] {
    set cpin [get_pins -quiet -of_objects $s -filter {REF_PIN_NAME == "C"}]
    set nets [get_nets -quiet -of_objects $cpin]
    set net [lindex $nets 0]
    set route [ro_normalize_space [get_property ROUTE $net]]
    if {$route eq ""} { close $ch; error "I4 candidate gate: ripple net not routed: $net" }
    set allpins [lsort -dictionary [get_pins -quiet -leaf -of_objects [get_nets -quiet -segments $net]]]
    set driver ""
    foreach pin $allpins {
        if {[get_property DIRECTION $pin] eq "OUT"} { lappend driver $pin }
    }
    if {[llength $driver] != 1} { close $ch; error "I4 candidate gate: ripple driver != 1 on $net" }
    set class [i4_clock_class $net]
    if {[string match "GLOBAL_BUFFER:*" $class]} { close $ch; error "I4 candidate gate: ripple net uses global buffer: $net" }
    set drvpin [lindex $driver 0]
    set drvcell [get_cells -quiet -of_objects $drvpin]
    set drvref [get_property REF_NAME $drvcell]
    set upstream "-"
    set qroute "-"
    if {[string match "LUT*" $drvref]} {
        set inpin [get_pins -quiet -of_objects $drvcell -filter {DIRECTION == IN}]
        if {[llength $inpin] != 1} { close $ch; error "I4 candidate gate: ripple INV input ambiguous on $drvcell: $inpin" }
        set inet [lindex [get_nets -quiet -of_objects [lindex $inpin 0]] 0]
        set qroute [ro_normalize_space [get_property ROUTE $inet]]
        if {$qroute eq ""} { close $ch; error "I4 candidate gate: ripple Q net not routed: $inet" }
        set qpins [get_pins -quiet -leaf -of_objects [get_nets -quiet -segments $inet]]
        foreach qp $qpins {
            if {[get_property DIRECTION $qp] eq "OUT"} { set upstream [i4_relative $qp] }
        }
        if {$upstream eq "-" || [file tail $upstream] ne "Q"} {
            close $ch; error "I4 candidate gate: ripple upstream is not an FDCE Q: $inet ($upstream)"
        }
    } elseif {$drvref eq "FDCE"} {
        set upstream [i4_relative $drvpin]
        set qroute $route
    } else {
        close $ch; error "I4 candidate gate: unexpected ripple driver $drvpin ($drvref)"
    }
    puts $ch "RIPPLE\t[i4_relative $net]\tdriver=[i4_relative $drvpin]($drvref)\tsink=[i4_relative $cpin]\troute=$route\tclass=$class\tupstream=$upstream\tqroute=$qroute"
    incr ripple_count
}
if {$ripple_count != 1088} { close $ch; error "I4 candidate gate: expected 1088 ripple routes, found $ripple_count" }
close $ch
puts "I4_CANDIDATE_EXPANDED_FINGERPRINT=$out_path"
close_design
