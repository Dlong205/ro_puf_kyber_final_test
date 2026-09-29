# OPERATIONAL_INFLUENCE_FINGERPRINT_V1 exporter (R6.1).
#
# Covers what the macro-internal fingerprint cannot: the physical environment
# that the gen2 stop report proved to influence PUF offsets
# (OPERATIONAL_OFFSET_NOT_BOUNDED):
#   MCELL  macro cells with FULL hierarchical names (no prefix stripping;
#          equivalence across images is by exact match, not by hiding
#          hierarchy deltas) + placement/routing/lock state
#   MNET   macro-internal nets (TAP/chain/Q): ROUTE + IS_ROUTE_FIXED
#   BOUND  every net crossing the macro boundary: ROUTE + lock + endpoints
#   CLK    MMCM config + BUFG placement + clock-net routes + reset sync regs
#   SCHED  scheduler cells (placement-sensitive, TIER-1)
#   SNIFF  qualification-sniffer cells incl. BRAM (capture proves loads)
#   TELOAD telemetry-net fanout (netlist load proof, placement-independent)
#   NEIGH  neighbor cells inside macro bbox +/-12 slices (supply/routing
#          influence cone approximation)
#   SRC/GEN appended afterwards by scripts/hash_operational_sources.py
#          (source/xdc/firmware/mapping hashes + top generic values).
#
# Comparator modes (compare_puf64_operational_influence_fingerprint.py):
#   ab      exact match on every compared line (R6.2 A/B reproducibility).
#           Identity lines (DCP_SHA / build labels) are informational only.
#   bridge  TIER-0 sections exact (MCELL/MNET/BOUND/CLK/TELOAD/SRC);
#           TIER-1 (SCHED/SNIFF/NEIGH) and GEN reported as diff stats;
#           the final confirmation campaign (R6.6/R6.7) is the binding gate.
#
# Usage (inside an open routed design, or standalone on a routed DCP):
#   vivado -mode batch -nolog -nojournal \
#     -source scripts/export_puf64_operational_influence_fingerprint.tcl \
#     -tclargs <routed.dcp|OPEN> <output.tsv> <top> <macro-prefix>
#   <routed.dcp> = checkpoint path, or OPEN if a design is already open.
#   <macro-prefix> e.g. u_operational_uart/u_chain/u_puf64_core/u_macro
set_param general.maxThreads 1
set script_dir [file dirname [file normalize [info script]]]
set root_dir [file normalize [file join $script_dir ..]]
source [file join $script_dir ro_physical_common.tcl]

if {[llength $argv] < 4} {
    error "usage: export_puf64_operational_influence_fingerprint.tcl <routed.dcp|OPEN> <output.tsv> <top> <macro-prefix>"
}
set checkpoint [lindex $argv 0]
set out_path [file normalize [lindex $argv 1]]
set exp_top [lindex $argv 2]
set macro_pre [lindex $argv 3]
# Core prefix = macro prefix minus trailing /u_macro.
if {![string match "*/u_macro" $macro_pre]} {
    error "R6 influence: macro prefix must end in /u_macro: $macro_pre"
}
set core_pre [string range $macro_pre 0 end-8]
set sched_pre "${core_pre}/u_puf64_scheduler"
set sniff_pre "${core_pre}/u_qual_sniffer"

if {$checkpoint ne "OPEN"} {
    set checkpoint [file normalize $checkpoint]
    if {![file isfile $checkpoint]} { error "R6 influence: DCP missing: $checkpoint" }
    set dcp_sha [ro_sha256_file $checkpoint]
    open_checkpoint $checkpoint
} else {
    set dcp_sha "OPEN_DESIGN_[get_property TOP [current_design]]"
}
set actual_top [get_property TOP [current_design]]
if {$actual_top ne $exp_top} {
    error "R6 influence: top is $actual_top, expected $exp_top"
}

proc r6_norm {s} {
    if {$s eq ""} { return "-" }
    return [ro_normalize_space $s]
}

file mkdir [file dirname $out_path]
set ch [open $out_path w]
puts $ch "OPERATIONAL_INFLUENCE_FINGERPRINT_V1"
puts $ch "IDS\tdcp_sha=$dcp_sha"
puts $ch "TOP\t$actual_top"
puts $ch "MACRO_PREFIX\t$macro_pre"

# ---- MCELL: full-hierarchy macro cells ----
set ro_luts [get_cells -quiet -hierarchical -filter "NAME =~ \"*${macro_pre}/u_bench/*ro_cell*/u_backend/LUT6_*\""]
set presc [get_cells -quiet -hierarchical -filter "NAME =~ \"*${macro_pre}/u_bench/*counter/presc_fdce\" && REF_NAME == \"FDCE\""]
set stages [get_cells -quiet -hierarchical -filter "REF_NAME == \"FDCE\" && NAME =~ \"*${macro_pre}/u_bench/*stage*ff*\""]
set inv_p [get_cells -quiet -hierarchical -filter "REF_NAME == \"LUT1\" && NAME =~ \"*${macro_pre}/u_bench/*inv_presc*\""]
set inv_s [get_cells -quiet -hierarchical -filter "REF_NAME == \"LUT1\" && NAME =~ \"*${macro_pre}/u_bench/*stage*inv*\""]
if {[llength $ro_luts] != 256 || [llength $presc] != 64 || \
    [llength $stages] != 1088 || [llength $inv_p] != 64 || \
    [llength $inv_s] != 1088} {
    close $ch
    error "R6 influence: macro inventory ro=[llength $ro_luts] pr=[llength $presc] st=[llength $stages] invp=[llength $inv_p] invs=[llength $inv_s]"
}
foreach cell [lsort -dictionary [concat $ro_luts $presc $stages $inv_p $inv_s]] {
    set ref [get_property REF_NAME $cell]
    set init [r6_norm [get_property INIT $cell]]
    set loc [get_property LOC $cell]
    set bel [get_property BEL $cell]
    if {$ref eq "" || $loc eq "" || $bel eq ""} {
        close $ch
        error "R6 influence: macro cell missing placement: $cell"
    }
    set pinmap [join [ro_actual_input_pin_map $cell] ,]
    if {$pinmap eq ""} { set pinmap "-" }
    set lockpins [r6_norm [get_property LOCK_PINS $cell]]
    set isloc [get_property IS_LOC_FIXED $cell]
    set isbel [get_property IS_BEL_FIXED $cell]
    puts $ch "MCELL\t$cell\t$ref\t$init\t$loc\t$bel\t$pinmap\t$lockpins\tisloc=$isloc\tisbel=$isbel"
}

# ---- MNET: TAP + chain + Q internal nets ----
proc r6_netline {tag net} {
    set route [ro_normalize_space [get_property ROUTE $net]]
    if {$route eq ""} { return "UNROUTED" }
    set isrf [get_property IS_ROUTE_FIXED $net]
    return "route=$route\tisroutefixed=$isrf"
}
set mnet_n 0
foreach p [lsort -dictionary $presc] {
    set cpin [get_pins -quiet -of_objects $p -filter {REF_PIN_NAME == "C"}]
    set net [lindex [get_nets -quiet -of_objects $cpin] 0]
    set line [r6_netline TAP $net]
    if {$line eq "UNROUTED"} { close $ch; error "R6 influence: TAP unrouted: $net" }
    puts $ch "MNET\tTAP\t$net\t$line"
    incr mnet_n
}
foreach s [lsort -dictionary $stages] {
    set cpin [get_pins -quiet -of_objects $s -filter {REF_PIN_NAME == "C"}]
    set net [lindex [get_nets -quiet -of_objects $cpin] 0]
    set line [r6_netline CHAIN $net]
    if {$line eq "UNROUTED"} { close $ch; error "R6 influence: CHAIN unrouted: $net" }
    puts $ch "MNET\tCHAIN\t$net\t$line"
    incr mnet_n
}
foreach qp [lsort -dictionary [get_pins -quiet -of_objects [concat $presc $stages] -filter {REF_PIN_NAME == "Q"}]] {
    foreach net [get_nets -quiet -of_objects $qp] {
        set line [r6_netline Q $net]
        if {$line eq "UNROUTED"} { close $ch; error "R6 influence: Q unrouted: $net" }
        puts $ch "MNET\tQ\t$net\t$line"
        incr mnet_n
    }
}
puts $ch "MNET_COUNT\t$mnet_n"

# ---- BOUND: nets crossing the macro boundary ----
set macro_cell [get_cells -quiet $macro_pre]
if {[llength $macro_cell] != 1} { close $ch; error "R6 influence: macro instance not unique: $macro_pre" }
set bound_nets [dict create]
set resp_unconn 0
foreach pin [get_pins -quiet -of_objects $macro_cell] {
    set nets [get_nets -quiet -of_objects $pin]
    if {[llength $nets] == 0} {
        # The 2016-bit response bus is intentionally unconnected in the
        # operational core (proven pin-by-pin by macro_v2_audit_import);
        # count it here so the fingerprint states it explicitly.
        if {[string match "*response*" $pin]} { incr resp_unconn }
        continue
    }
    foreach net $nets { dict set bound_nets $net 1 }
}
set bound_n 0
dict for {net _} $bound_nets {
    set route [r6_norm [get_property ROUTE $net]]
    set isrf [get_property IS_ROUTE_FIXED $net]
    set allpins [lsort -dictionary [get_pins -quiet -leaf -of_objects [get_nets -quiet -segments $net]]]
    set driver "-"
    set sinks {}
    foreach p $allpins {
        if {[get_property DIRECTION $p] eq "OUT"} { set driver $p } else { lappend sinks $p }
    }
    puts $ch "BOUND\t$net\troute=$route\tisroutefixed=$isrf\tdriver=$driver\tsinks=[join $sinks ,]"
    incr bound_n
}
puts $ch "BOUND_RESPONSE_UNCONNECTED_PINS\t$resp_unconn"
puts $ch "BOUND_COUNT\t$bound_n"

# ---- CLK: MMCM + BUFG + clock nets + reset sync ----
set mmcm [get_cells -quiet -hierarchical -filter {REF_NAME =~ "MMCME2*"}]
if {[llength $mmcm] != 1} { close $ch; error "R6 influence: MMCM count != 1: $mmcm" }
set mmcm_props {}
foreach prop {LOC BANDWIDTH CLKFBOUT_MULT_F DIVCLK_DIVIDE CLKOUT0_DIVIDE_F CLKOUT0_DUTY_CYCLE CLKIN1_PERIOD COMPENSATION STARTUP_WAIT REF_JITTER1 CLKFBOUT_PHASE CLKOUT0_PHASE} {
    lappend mmcm_props "$prop=[r6_norm [get_property $prop $mmcm]]"
}
puts $ch "CLK\tMMCM\t$mmcm\t[join $mmcm_props \t]"
foreach bg [lsort -dictionary [get_cells -quiet -hierarchical -filter {REF_NAME == "BUFG"}]] {
    puts $ch "CLK\tBUFG\t$bg\tREF=[get_property REF_NAME $bg]\tLOC=[get_property LOC $bg]\tBEL=[get_property BEL $bg]"
}
foreach bg [lsort -dictionary [get_cells -quiet -hierarchical -filter {REF_NAME == "BUFG"}]] {
    foreach opin [get_pins -quiet -of_objects $bg -filter {DIRECTION == OUT}] {
        foreach net [get_nets -quiet -of_objects $opin] {
            set pins [get_pins -quiet -leaf -of_objects [get_nets -quiet -segments $net]]
            puts $ch "CLK\tCLKNET\t$net\troute=[r6_norm [get_property ROUTE $net]]\tendpoints=[llength $pins]"
        }
    }
}
foreach rc [lsort -dictionary [concat \
        [get_cells -quiet -hierarchical -filter {NAME =~ "*locked_sync*"}] \
        [get_cells -quiet -hierarchical -filter {NAME =~ "*reset_count*"}] \
        [get_cells -quiet -hierarchical -filter {NAME =~ "*reset_n*"}]]] {
    puts $ch "CLK\tRSTREG\t$rc\tREF=[get_property REF_NAME $rc]\tINIT=[r6_norm [get_property INIT $rc]]\tLOC=[get_property LOC $rc]\tBEL=[get_property BEL $rc]"
}

# ---- SCHED (TIER-1): scheduler placement ----
set sched_cells [get_cells -quiet -hierarchical -filter "NAME =~ \"*${sched_pre}/*\""]
if {[llength $sched_cells] == 0} { close $ch; error "R6 influence: scheduler hierarchy empty: $sched_pre" }
puts $ch "SCHED_COUNT\t[llength $sched_cells]"
foreach cell [lsort -dictionary $sched_cells] {
    puts $ch "SCHED\t$cell\tREF=[get_property REF_NAME $cell]\tINIT=[r6_norm [get_property INIT $cell]]\tLOC=[get_property LOC $cell]\tBEL=[get_property BEL $cell]"
}

# ---- SNIFF (TIER-1): capture hardware presence + placement ----
set sniff_cells [get_cells -quiet -hierarchical -filter "NAME =~ \"*${sniff_pre}/*\""]
if {[llength $sniff_cells] == 0} { close $ch; error "R6 influence: sniffer hierarchy missing (superset broken): $sniff_pre" }
set bram_n 0
foreach cell $sniff_cells {
    set ref [get_property REF_NAME $cell]
    if {[string match "RAMB*" $ref]} { incr bram_n }
}
puts $ch "SNIFF_COUNT\t[llength $sniff_cells]\tBRAM=$bram_n"
if {$bram_n < 1} { close $ch; error "R6 influence: sniffer BRAM missing (capture trimmed?)" }
foreach cell [lsort -dictionary $sniff_cells] {
    puts $ch "SNIFF\t$cell\tREF=[get_property REF_NAME $cell]\tINIT=[r6_norm [get_property INIT $cell]]\tLOC=[get_property LOC $cell]\tBEL=[get_property BEL $cell]"
}

# ---- TELOAD: telemetry fanout (netlist load proof) ----
set tel_ports {telemetry_valid telemetry_index telemetry_pair_a telemetry_pair_b telemetry_count0 telemetry_count1 telemetry_stable telemetry_timeout telemetry_overflow_a telemetry_overflow_b telemetry_winner}
foreach tp $tel_ports {
    set pins [get_pins -quiet -of_objects $macro_cell -filter "REF_PIN_NAME == \"$tp\" || NAME =~ \"*/$tp*\""]
    if {[llength $pins] == 0} {
        puts $ch "TELOAD\t$tp\tMISSING_PIN"
        continue
    }
    foreach pin $pins {
        set nets [get_nets -quiet -of_objects $pin]
        if {[llength $nets] == 0} {
            puts $ch "TELOAD\t$tp\t$pin\tUNCONNECTED"
        } else {
            foreach net $nets {
                set allpins [lsort -dictionary [get_pins -quiet -leaf -of_objects [get_nets -quiet -segments $net]]]
                set driver "-"
                set sinks {}
                foreach p $allpins {
                    if {[get_property DIRECTION $p] eq "OUT"} { set driver $p } else { lappend sinks $p }
                }
                puts $ch "TELOAD\t$tp\t$net\tdriver=$driver\tsinks=[join $sinks ,]"
            }
        }
    }
}

# ---- NEIGH (TIER-1): neighbor influence box ----
set xs {} ; set ys {}
foreach cell [concat $ro_luts $presc $stages] {
    set loc [get_property LOC $cell]
    if {[regexp {SLICE_X([0-9]+)Y([0-9]+)} $loc -> x y]} {
        lappend xs $x ; lappend ys $y
    }
}
if {[llength $xs] == 0} { close $ch; error "R6 influence: no macro SLICE LOCs" }
set xmin [tcl::mathfunc::min {*}$xs] ; set xmax [tcl::mathfunc::max {*}$xs]
set ymin [tcl::mathfunc::min {*}$ys] ; set ymax [tcl::mathfunc::max {*}$ys]
set x0 [expr {$xmin - 12}] ; set x1 [expr {$xmax + 12}]
set y0 [expr {$ymin - 12}] ; set y1 [expr {$ymax + 12}]
puts $ch "NEIGH_BOX\tSLICE_X${x0}Y${y0}:SLICE_X${x1}Y${y1}"
set neigh_n 0
foreach cell [lsort -dictionary [get_cells -quiet -hierarchical -filter {LOC =~ "SLICE_*"}]] {
    if {[string first $macro_pre $cell] >= 0} { continue }
    set loc [get_property LOC $cell]
    if {![regexp {SLICE_X([0-9]+)Y([0-9]+)} $loc -> x y]} { continue }
    if {$x < $x0 || $x > $x1 || $y < $y0 || $y > $y1} { continue }
    puts $ch "NEIGH\t$cell\tREF=[get_property REF_NAME $cell]\tLOC=$loc\tBEL=[get_property BEL $cell]"
    incr neigh_n
}
puts $ch "NEIGH_COUNT\t$neigh_n"
puts $ch "R6_INFLUENCE_EXPORT_DONE"
close $ch
puts "R6_INFLUENCE_FINGERPRINT=$out_path"
puts "R6_INFLUENCE_TOP=$actual_top"
