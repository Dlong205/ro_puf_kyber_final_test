# I4.2: expanded golden fingerprint from the qualified routed DCP.
# Must be run under Vivado 2020.1.  The golden DCP hash is pinned; the script
# refuses any other checkpoint so the golden fingerprint can never be
# regenerated from a new build.
#
# Usage:
#   vivado -mode batch -nolog -nojournal \
#     -source scripts/export_puf64_operational_expanded_fingerprint.tcl \
#     -tclargs <routed.dcp> <output.tsv>
set_param general.maxThreads 1
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
source [file join $script_dir ro_physical_common.tcl]

set GOLDEN_DCP_SHA "febefcc7129fdf42aae7c3be55875ed61f8cfb72562bbe8830d514628b2788e0"
set default_dcp [file join $root_dir build puf_allpairs64_characterization \
    puf_allpairs64_zynq7020.runs impl_1 Puf_AllPairs64_Characterization_Top_routed.dcp]
set default_out [file join $root_dir reports puf64_operational_preservation \
    golden_expanded_fingerprint.tsv]

set checkpoint $default_dcp
set out_path $default_out
if {[llength $argv] >= 1} { set checkpoint [file normalize [lindex $argv 0]] }
if {[llength $argv] >= 2} { set out_path [file normalize [lindex $argv 1]] }
if {![file isfile $checkpoint]} { error "I4 golden DCP missing: $checkpoint" }

set actual_sha [ro_sha256_file $checkpoint]
if {$actual_sha ne $GOLDEN_DCP_SHA} {
    error "I4 golden DCP hash mismatch: expected=$GOLDEN_DCP_SHA actual=$actual_sha file=$checkpoint"
}
puts "I4_GOLDEN_DCP_SHA_OK=$actual_sha"

open_checkpoint $checkpoint

# --- physical inventory: 256 RO LUT + 64 prescaler + 1088 ripple stages ---
set ro_luts [get_cells -quiet -hierarchical \
    -filter {NAME =~ "*u_puf*ro_cell*/u_backend/LUT6_*"}]
set presc [get_cells -quiet -hierarchical \
    -filter {NAME =~ "*counter/presc_fdce" && REF_NAME == "FDCE"}]
set stages [get_cells -quiet -hierarchical \
    -filter {REF_NAME == "FDCE" && NAME =~ "*stage*ff*"}]
if {[llength $ro_luts] != 256} { error "I4 golden gate: expected 256 RO LUTs, found [llength $ro_luts]" }
if {[llength $presc] != 64} { error "I4 golden gate: expected 64 prescalers, found [llength $presc]" }
if {[llength $stages] != 1088} { error "I4 golden gate: expected 1088 ripple stages, found [llength $stages]" }

# Relative path: strip everything through the qualified u_puf/ macro so the
# operational candidate (different hierarchy prefix) compares exactly.  Names
# outside the macro (synthesis-inferred ripple INV LUT1s whose flat instance
# names sit at top level) are recorded verbatim instead of erroring.
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
puts $ch "GOLDEN_DCP_SHA\t$actual_sha"
puts $ch "SUMMARY\tro_luts=256\tprescaler=64\tripple_stages=1088"

foreach cell [lsort -dictionary [concat $ro_luts $presc $stages]] {
    set ref [get_property REF_NAME $cell]
    set init [get_property INIT $cell]
    set loc [get_property LOC $cell]
    set bel [get_property BEL $cell]
    if {$ref eq "" || $loc eq "" || $bel eq ""} {
        close $ch
        error "I4 golden gate: missing placement for $cell REF=$ref LOC=$loc BEL=$bel"
    }
    if {$init eq ""} { set init "-" }
    set pinmap [join [ro_actual_input_pin_map $cell] ,]
    if {$pinmap eq ""} {
        # FDCE cells have no LUT pin map; record lock state explicitly.
        set pinmap "-"
    }
    set lockpins [get_property LOCK_PINS $cell]
    if {$lockpins eq ""} { set lockpins "-" } else { set lockpins [ro_normalize_space $lockpins] }
    puts $ch "CELL\t[i4_relative $cell]\t$ref\t$init\t$loc\t$bel\t$pinmap\t$lockpins"
}

# 64 RO-output -> prescaler clock routes (ro_tap nets).
foreach p [lsort -dictionary $presc] {
    set cpin [get_pins -quiet -of_objects $p -filter {REF_PIN_NAME == "C"}]
    if {$cpin eq ""} { close $ch; error "I4 golden gate: no C pin on $p" }
    set nets [get_nets -quiet -of_objects $cpin]
    if {[llength $nets] != 1} { close $ch; error "I4 golden gate: prescaler C net ambiguous on $p: $nets" }
    set net [lindex $nets 0]
    set route [ro_normalize_space [get_property ROUTE $net]]
    if {$route eq ""} { close $ch; error "I4 golden gate: ro_tap not routed: $net" }
    set allpins [lsort -dictionary [get_pins -quiet -leaf -of_objects [get_nets -quiet -segments $net]]]
    set driver ""
    foreach pin $allpins {
        if {[get_property DIRECTION $pin] eq "OUT"} { lappend driver $pin }
    }
    if {[llength $driver] != 1} { close $ch; error "I4 golden gate: ro_tap driver != 1 on $net: $driver" }
    set sinks {}
    foreach pin $allpins {
        if {[get_property DIRECTION $pin] eq "IN"} { lappend sinks $pin }
    }
    set relnet [i4_relative $net]
    set reldriver [i4_relative [lindex $driver 0]]
    set relsinks {}
    foreach s $sinks { lappend relsinks [i4_relative $s] }
    set class [i4_clock_class $net]
    if {[string match "GLOBAL_BUFFER:*" $class]} { close $ch; error "I4 golden gate: ro_tap uses global buffer: $net $class" }
    puts $ch "TAP\t$relnet\tdriver=$reldriver\tsinks=[join [lsort -dictionary $relsinks] ,]\troute=$route\tclass=$class"
}

# Full internal ripple clock routes: presc Q -> stage[0] C, stage[n] Q ->
# stage[n+1] C.  Synthesis implements each `~Q' inversion as a LUT1, so the
# stage-C (chain) net is driven by that LUT1/O while the FDCE Q drives the
# LUT1/I0 net.  Both segments are recorded: the chain net plus its upstream Q
# source, so the fingerprint covers the complete physical clock path.
set ripple_count 0
foreach s [lsort -dictionary $stages] {
    set cpin [get_pins -quiet -of_objects $s -filter {REF_PIN_NAME == "C"}]
    if {$cpin eq ""} { close $ch; error "I4 golden gate: no C pin on $s" }
    set nets [get_nets -quiet -of_objects $cpin]
    if {[llength $nets] != 1} { close $ch; error "I4 golden gate: ripple C net ambiguous on $s" }
    set net [lindex $nets 0]
    set route [ro_normalize_space [get_property ROUTE $net]]
    if {$route eq ""} { close $ch; error "I4 golden gate: ripple net not routed: $net" }
    set allpins [lsort -dictionary [get_pins -quiet -leaf -of_objects [get_nets -quiet -segments $net]]]
    set driver ""
    foreach pin $allpins {
        if {[get_property DIRECTION $pin] eq "OUT"} { lappend driver $pin }
    }
    if {[llength $driver] != 1} { close $ch; error "I4 golden gate: ripple driver != 1 on $net" }
    set class [i4_clock_class $net]
    if {[string match "GLOBAL_BUFFER:*" $class]} { close $ch; error "I4 golden gate: ripple net uses global buffer: $net" }
    set drvpin [lindex $driver 0]
    set drvcell [get_cells -quiet -of_objects $drvpin]
    set drvref [get_property REF_NAME $drvcell]
    set upstream "-"
    set qroute "-"
    if {[string match "LUT*" $drvref]} {
        set inpin [get_pins -quiet -of_objects $drvcell -filter {DIRECTION == IN}]
        if {[llength $inpin] != 1} { close $ch; error "I4 golden gate: ripple INV input ambiguous on $drvcell: $inpin" }
        set inet [lindex [get_nets -quiet -of_objects [lindex $inpin 0]] 0]
        set qroute [ro_normalize_space [get_property ROUTE $inet]]
        if {$qroute eq ""} { close $ch; error "I4 golden gate: ripple Q net not routed: $inet" }
        set qpins [get_pins -quiet -leaf -of_objects [get_nets -quiet -segments $inet]]
        foreach qp $qpins {
            if {[get_property DIRECTION $qp] eq "OUT"} { set upstream [i4_relative $qp] }
        }
        if {$upstream eq "-" || [file tail $upstream] ne "Q"} {
            close $ch; error "I4 golden gate: ripple upstream is not an FDCE Q: $inet ($upstream)"
        }
    } elseif {$drvref eq "FDCE"} {
        set upstream [i4_relative $drvpin]
        set qroute $route
    } else {
        close $ch; error "I4 golden gate: unexpected ripple driver $drvpin ($drvref)"
    }
    set relnet [i4_relative $net]
    set reldriver [i4_relative $drvpin]
    puts $ch "RIPPLE\t$relnet\tdriver=${reldriver}(${drvref})\tsink=[i4_relative $cpin]\troute=$route\tclass=$class\tupstream=$upstream\tqroute=$qroute"
    incr ripple_count
}
if {$ripple_count != 1088} { close $ch; error "I4 golden gate: expected 1088 ripple routes, found $ripple_count" }
close $ch
puts "I4_GOLDEN_EXPANDED_FINGERPRINT=$out_path"
puts "I4_GOLDEN_CELLS=256+64+1088 TAP=64 RIPPLE=1088"
close_design
