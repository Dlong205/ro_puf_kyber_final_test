# R2 macro-V2 expanded fingerprint (LUT1-aware).  Works on the OOC routed
# macro DCP and on any routed design that imported it (V2 characterization /
# operational): hierarchy prefixes are stripped to ro[...]/... relative paths
# so all three prove the same fingerprint.  Run under Vivado 2020.1:
#
#   vivado -mode batch -nolog -nojournal \
#     -source scripts/export_puf64_macro_v2_fingerprint.tcl \
#     -tclargs <routed.dcp> <output.tsv> <sha-label>
set_param general.maxThreads 1
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
source [file join $script_dir ro_physical_common.tcl]

if {[llength $argv] < 3} {
    error "usage: export_puf64_macro_v2_fingerprint.tcl <routed.dcp> <output.tsv> <sha-label>"
}
set checkpoint [file normalize [lindex $argv 0]]
set out_path [file normalize [lindex $argv 1]]
set sha_label [lindex $argv 2]
if {![file isfile $checkpoint]} { error "R2 fingerprint: DCP missing: $checkpoint" }
set dcp_sha [ro_sha256_file $checkpoint]
puts "R2_FINGERPRINT_DCP_SHA=$dcp_sha"

open_checkpoint $checkpoint

set ro_luts [get_cells -quiet -hierarchical -filter {NAME =~ "*ro_cell*/u_backend/LUT6_*"}]
set presc [get_cells -quiet -hierarchical -filter {NAME =~ "*counter/presc_fdce" && REF_NAME == "FDCE"}]
set stages [get_cells -quiet -hierarchical -filter {REF_NAME == "FDCE" && NAME =~ "*stage*ff*"}]
set inv_p [get_cells -quiet -hierarchical -filter {REF_NAME == "LUT1" && NAME =~ "*inv_presc*"}]
set inv_s [get_cells -quiet -hierarchical -filter {REF_NAME == "LUT1" && NAME =~ "*stage*inv*"}]
if {[llength $ro_luts] != 256} { error "R2 fingerprint: expected 256 RO LUTs, found [llength $ro_luts]" }
if {[llength $presc] != 64} { error "R2 fingerprint: expected 64 prescalers, found [llength $presc]" }
if {[llength $stages] != 1088} { error "R2 fingerprint: expected 1088 ripple stages, found [llength $stages]" }
if {[llength $inv_p] != 64} { error "R2 fingerprint: expected 64 prescaler INVs, found [llength $inv_p]" }
if {[llength $inv_s] != 1088} { error "R2 fingerprint: expected 1088 stage INVs, found [llength $inv_s]" }

# Relative path: strip through the macro bench root.  V2 keeps every
# physical cell under u_bench/, so no flat names are expected; anything
# outside is recorded verbatim (exact compare still applies).
proc r2_relative {full} {
    set idx [string first "u_bench/" $full]
    if {$idx < 0} { return $full }
    return [string range $full [expr {$idx + 8}] end]
}
proc r2_clock_class {net} {
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
puts $ch "R2_MACRO_FINGERPRINT_V1"
puts $ch "$sha_label\t$dcp_sha"
puts $ch "SUMMARY\tro_luts=256\tprescaler=64\tripple_stages=1088\tinv_presc=64\tinv_stage=1088"

foreach cell [lsort -dictionary [concat $ro_luts $presc $stages $inv_p $inv_s]] {
    set ref [get_property REF_NAME $cell]
    set init [get_property INIT $cell]
    set loc [get_property LOC $cell]
    set bel [get_property BEL $cell]
    if {$ref eq "" || $loc eq "" || $bel eq ""} {
        close $ch
        error "R2 fingerprint: missing placement for $cell REF=$ref LOC=$loc BEL=$bel"
    }
    if {$init eq ""} { set init "-" }
    set pinmap [join [ro_actual_input_pin_map $cell] ,]
    if {$pinmap eq ""} { set pinmap "-" }
    set lockpins [get_property LOCK_PINS $cell]
    if {$lockpins eq ""} { set lockpins "-" } else { set lockpins [ro_normalize_space $lockpins] }
    puts $ch "CELL\t[r2_relative $cell]\t$ref\t$init\t$loc\t$bel\t$pinmap\t$lockpins"
}

foreach p [lsort -dictionary $presc] {
    set cpin [get_pins -quiet -of_objects $p -filter {REF_PIN_NAME == "C"}]
    if {$cpin eq ""} { close $ch; error "R2 fingerprint: no C pin on $p" }
    set nets [get_nets -quiet -of_objects $cpin]
    if {[llength $nets] != 1} { close $ch; error "R2 fingerprint: prescaler C net ambiguous on $p" }
    set net [lindex $nets 0]
    set route [ro_normalize_space [get_property ROUTE $net]]
    if {$route eq ""} { close $ch; error "R2 fingerprint: ro_tap not routed: $net" }
    set allpins [lsort -dictionary [get_pins -quiet -leaf -of_objects [get_nets -quiet -segments $net]]]
    set driver ""
    foreach pin $allpins {
        if {[get_property DIRECTION $pin] eq "OUT"} { lappend driver $pin }
    }
    if {[llength $driver] != 1} { close $ch; error "R2 fingerprint: ro_tap driver != 1 on $net" }
    if {[string first "ro_cell" [lindex $driver 0]] < 0} {
        close $ch; error "R2 fingerprint: ro_tap driver not an RO cell: [lindex $driver 0]"
    }
    set sinks {}
    foreach pin $allpins {
        if {[get_property DIRECTION $pin] eq "IN"} { lappend sinks $pin }
    }
    set relsinks {}
    foreach s $sinks { lappend relsinks [r2_relative $s] }
    set class [r2_clock_class $net]
    if {[string match "GLOBAL_BUFFER:*" $class]} { close $ch; error "R2 fingerprint: ro_tap uses global buffer: $net" }
    puts $ch "TAP\t[r2_relative $net]\tdriver=[r2_relative [lindex $driver 0]]\tsinks=[join [lsort -dictionary $relsinks] ,]\troute=$route\tclass=$class"
}

set ripple_count 0
foreach s [lsort -dictionary $stages] {
    set cpin [get_pins -quiet -of_objects $s -filter {REF_PIN_NAME == "C"}]
    if {$cpin eq ""} { close $ch; error "R2 fingerprint: no C pin on $s" }
    set nets [get_nets -quiet -of_objects $cpin]
    if {[llength $nets] != 1} { close $ch; error "R2 fingerprint: ripple C net ambiguous on $s" }
    set net [lindex $nets 0]
    set route [ro_normalize_space [get_property ROUTE $net]]
    if {$route eq ""} { close $ch; error "R2 fingerprint: ripple net not routed: $net" }
    set allpins [lsort -dictionary [get_pins -quiet -leaf -of_objects [get_nets -quiet -segments $net]]]
    set driver ""
    foreach pin $allpins {
        if {[get_property DIRECTION $pin] eq "OUT"} { lappend driver $pin }
    }
    if {[llength $driver] != 1} { close $ch; error "R2 fingerprint: ripple driver != 1 on $net" }
    set class [r2_clock_class $net]
    if {[string match "GLOBAL_BUFFER:*" $class]} { close $ch; error "R2 fingerprint: ripple net uses global buffer: $net" }
    set drvpin [lindex $driver 0]
    set drvcell [get_cells -quiet -of_objects $drvpin]
    set drvref [get_property REF_NAME $drvcell]
    set upstream "-"
    set qroute "-"
    if {[string match "LUT*" $drvref]} {
        set inpin [get_pins -quiet -of_objects $drvcell -filter {DIRECTION == IN}]
        if {[llength $inpin] != 1} { close $ch; error "R2 fingerprint: ripple INV input ambiguous on $drvcell" }
        set inet [lindex [get_nets -quiet -of_objects [lindex $inpin 0]] 0]
        set qroute [ro_normalize_space [get_property ROUTE $inet]]
        if {$qroute eq ""} { close $ch; error "R2 fingerprint: ripple Q net not routed: $inet" }
        foreach qp [get_pins -quiet -leaf -of_objects [get_nets -quiet -segments $inet]] {
            if {[get_property DIRECTION $qp] eq "OUT"} { set upstream [r2_relative $qp] }
        }
        if {$upstream eq "-" || [file tail $upstream] ne "Q"} {
            close $ch; error "R2 fingerprint: ripple upstream not an FDCE Q: $inet ($upstream)"
        }
    } elseif {$drvref eq "FDCE"} {
        set upstream [r2_relative $drvpin]
        set qroute $route
    } else {
        close $ch; error "R2 fingerprint: unexpected ripple driver $drvpin ($drvref)"
    }
    puts $ch "RIPPLE\t[r2_relative $net]\tdriver=[r2_relative $drvpin](${drvref})\tsink=[r2_relative $cpin]\troute=$route\tclass=$class\tupstream=$upstream\tqroute=$qroute"
    incr ripple_count
}
if {$ripple_count != 1088} { close $ch; error "R2 fingerprint: expected 1088 ripple routes, found $ripple_count" }
close $ch
puts "R2_MACRO_FINGERPRINT=$out_path"
puts "R2_MACRO_CELLS=256+64+1088+64+1088 TAP=64 RIPPLE=1088"
close_design
