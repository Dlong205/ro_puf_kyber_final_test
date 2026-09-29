# Shared post-import gate for V2 black-box macro reuse (char + operational).
# Call after read_checkpoint -cell, before place/route:
#   source scripts/audit_macro_v2_import.tcl
#   macro_v2_audit_import "u_macro"
# (target_prefix = black-box instance name; macro bench root is u_bench/.)
# Fails closed on: missing/doubled target, inventory drift, lost LOC/BEL,
# missing TAP/ripple routes, endpoint mismatch, global buffers, floating
# macro ports.  Pure Vivado TCL (no side effects on files).
source [file join [file dirname [file normalize [info script]]] ro_physical_common.tcl]

proc macro_v2_audit_import {target_prefix {allow_unconnected_response 0}} {
    set targets [get_cells -quiet $target_prefix]
    if {[llength $targets] != 1} {
        error "V2 import gate: target $target_prefix must exist exactly once, found [llength $targets]"
    }
    set pat "*${target_prefix}/u_bench/*"
    set ro [get_cells -quiet -hierarchical -filter "NAME =~ \"${pat}ro_cell*/u_backend/LUT6_*\""]
    set pr [get_cells -quiet -hierarchical -filter "NAME =~ \"${pat}counter/presc_fdce\" && REF_NAME == \"FDCE\""]
    set st [get_cells -quiet -hierarchical -filter "REF_NAME == \"FDCE\" && NAME =~ \"${pat}stage*ff*\""]
    set ip [get_cells -quiet -hierarchical -filter "REF_NAME == \"LUT1\" && NAME =~ \"${pat}inv_presc*\""]
    set is [get_cells -quiet -hierarchical -filter "REF_NAME == \"LUT1\" && NAME =~ \"${pat}stage*inv*\""]
    if {[llength $ro] != 256 || [llength $pr] != 64 || [llength $st] != 1088 || \
        [llength $ip] != 64 || [llength $is] != 1088} {
        error "V2 import gate: inventory ro=[llength $ro] pr=[llength $pr] st=[llength $st] invp=[llength $ip] invs=[llength $is]"
    }
    foreach cell [concat $ro $pr $st $ip $is] {
        if {[get_property LOC $cell] eq "" || [get_property BEL $cell] eq ""} {
            error "V2 import gate: lost LOC/BEL: $cell"
        }
    }
    puts "V2_IMPORT place ro=256 pr=64 st=1088 invp=64 invs=1088 all LOC/BEL"
    foreach cell $ro {
        if {[get_property INIT $cell] eq ""} {
            error "V2 import gate: RO LUT lost INIT: $cell"
        }
        if {[join [ro_actual_input_pin_map $cell] ,] eq ""} {
            error "V2 import gate: RO LUT lost pin map: $cell"
        }
    }
    set tap_missing 0
    foreach p $pr {
        set cpin [get_pins -quiet -of_objects $p -filter {REF_PIN_NAME == "C"}]
        set net [lindex [get_nets -quiet -of_objects $cpin] 0]
        if {[ro_normalize_space [get_property ROUTE $net]] eq ""} { incr tap_missing; continue }
        foreach pin [get_pins -quiet -leaf -of_objects [get_nets -quiet -segments $net]] {
            set ref [get_property REF_NAME [get_cells -quiet -of_objects $pin]]
            if {$ref eq "BUFG" || $ref eq "BUFGCTRL" || $ref eq "BUFH" || \
                $ref eq "BUFHCE" || $ref eq "BUFR"} {
                error "V2 import gate: TAP net $net touches $ref"
            }
        }
        set ndrv 0
        foreach pin [get_pins -quiet -leaf -of_objects [get_nets -quiet -segments $net]] {
            if {[get_property DIRECTION $pin] eq "OUT"} { incr ndrv }
        }
        if {$ndrv != 1} { error "V2 import gate: TAP $net drivers=$ndrv" }
    }
    set rip_missing 0
    foreach s $st {
        set cpin [get_pins -quiet -of_objects $s -filter {REF_PIN_NAME == "C"}]
        set net [lindex [get_nets -quiet -of_objects $cpin] 0]
        if {[ro_normalize_space [get_property ROUTE $net]] eq ""} { incr rip_missing }
    }
    if {$tap_missing != 0} { error "V2 import gate: $tap_missing TAP routes missing" }
    if {$rip_missing != 0} { error "V2 import gate: $rip_missing ripple routes missing" }
    puts "V2_IMPORT routes tap=64 ripple=1088 present, tap endpoints+clock clean"
    set floating {}
    foreach pin [get_pins -quiet -of_objects [get_cells $target_prefix]] {
        if {[llength [get_nets -quiet -of_objects $pin]] == 0} {
            lappend floating $pin
        }
    }
    # The operational core consumes telemetry only; the 2016-bit response bus
    # is intentionally unconnected there (Vivado may list the collapsed bus
    # pin alongside its bits: allow bare "response" plus response[0..2015]).
    set n_resp_bits 0
    set nonresp {}
    set bare_bus 0
    foreach pin $floating {
        set tail [file tail $pin]
        if {[regexp {^response\[([0-9]+)\]$} $tail -> idx]} {
            if {![string is integer -strict $idx] || $idx < 0 || $idx > 2015} {
                error "V2 import gate: response index out of range: $tail"
            }
            incr n_resp_bits
        } elseif {$tail eq "response"} {
            incr bare_bus
        } else {
            lappend nonresp $tail
        }
    }
    if {!$allow_unconnected_response && [llength $floating] != 0} {
        error "V2 import gate: [llength $floating] floating pins on $target_prefix"
    }
    # The operational core consumes telemetry except pair_a/pair_b/winner:
    # the scheduler declares tel_pair_a/b but never reads them, and never
    # reads the winner bit either (verified in kp_puf64_mapping_scheduler.sv:
    # only declarations, no loads).  The black box shields macro internals
    # from trimming; these are dead outputs by design.  Allowed only here,
    # as exactly this 13-pin set -- anything else fails closed.
    if {$allow_unconnected_response} {
        set allowed {}
        for {set k 0} {$k < 6} {incr k} {
            lappend allowed "telemetry_pair_a\[$k\]" "telemetry_pair_b\[$k\]"
        }
        lappend allowed "telemetry_winner"
        foreach pin $nonresp {
            if {[lsearch -exact $allowed $pin] < 0} {
                error "V2 import gate: unexpected floating pin: $pin (allowed: response bus + 13 documented telemetry pins)"
            }
        }
    } elseif {[llength $nonresp] != 0} {
        error "V2 import gate: non-response floating pins: [lsort -dictionary $nonresp]"
    }
    # Pins are unique per get_pins, so count + range proves the full bus.
    if {$allow_unconnected_response && ($n_resp_bits != 2016 || $bare_bus > 1)} {
        error "V2 import gate: response bus incomplete (bits=$n_resp_bits bare=$bare_bus)"
    }
    puts "V2_IMPORT ports_connected (floating=[llength $floating], nonresponse=[llength $nonresp])"
}
# Standard OOC-reuse preservation lock (called post-gates, pre-save).
# Sets IS_LOC_FIXED/IS_BEL_FIXED on every imported macro cell and
# IS_ROUTE_FIXED on every fully-internal macro net (TAP + chain + Q nets).
# This is Vivado's implementation lock, applied uniformly via TCL before
# place/route -- NOT a hand-written FIXED_ROUTE XDC and NOT a partial-route
# cure (there is no partial route at this point; the gate above proved it).
# Boundary-crossing nets (clocks in, telemetry/response out) stay flexible.
# If the router cannot honor the locks it errors -> fail closed, genuine.
proc macro_v2_lock_imported {target_prefix} {
    set pat "*${target_prefix}/u_bench/*"
    set cells [concat \
        [get_cells -quiet -hierarchical -filter "NAME =~ \"${pat}ro_cell*/u_backend/LUT6_*\""] \
        [get_cells -quiet -hierarchical -filter "NAME =~ \"${pat}counter/presc_fdce\" && REF_NAME == \"FDCE\""] \
        [get_cells -quiet -hierarchical -filter "REF_NAME == \"FDCE\" && NAME =~ \"${pat}stage*ff*\""] \
        [get_cells -quiet -hierarchical -filter "REF_NAME == \"LUT1\" && NAME =~ \"${pat}inv_presc*\""] \
        [get_cells -quiet -hierarchical -filter "REF_NAME == \"LUT1\" && NAME =~ \"${pat}stage*inv*\""]]
    if {[llength $cells] != 2560} {
        error "V2 lock gate: expected 2560 macro cells, found [llength $cells]"
    }
    foreach cell $cells {
        set_property IS_LOC_FIXED true $cell
        set_property IS_BEL_FIXED true $cell
    }
    # Fully-internal nets: TAP (presc C nets) + chain (stage C nets) + Q nets.
    set lock_nets [dict create]
    foreach p [get_cells -quiet -hierarchical -filter "NAME =~ \"${pat}counter/presc_fdce\" && REF_NAME == \"FDCE\""] {
        dict set lock_nets [lindex [get_nets -quiet -of_objects \
            [get_pins -quiet -of_objects $p -filter {REF_PIN_NAME == "C"}]] 0] 1
    }
    foreach s [get_cells -quiet -hierarchical -filter "REF_NAME == \"FDCE\" && NAME =~ \"${pat}stage*ff*\""] {
        dict set lock_nets [lindex [get_nets -quiet -of_objects \
            [get_pins -quiet -of_objects $s -filter {REF_PIN_NAME == "C"}]] 0] 1
    }
    # Route-lock Q only when its source cell is part of the LOC/BEL-locked
    # physical counter cone.  A hierarchy-wide Q query also catches movable
    # synchronous bench registers (a_s*/b_s*); fixing those routes while the
    # placer is free to move their drivers produces RTSTAT-2 route islands.
    set q_source_cells [concat \
        [get_cells -quiet -hierarchical -filter \
            "NAME =~ \"${pat}counter/presc_fdce\" && REF_NAME == \"FDCE\""] \
        [get_cells -quiet -hierarchical -filter \
            "REF_NAME == \"FDCE\" && NAME =~ \"${pat}stage*ff*\""]]
    set qpins [get_pins -quiet -of_objects $q_source_cells \
        -filter {REF_PIN_NAME == "Q"}]
    foreach qp $qpins {
        foreach net [get_nets -quiet -of_objects $qp] { dict set lock_nets $net 1 }
    }
    set n_locked 0
    dict for {net _} $lock_nets {
        # Only fully-internal nets: every leaf pin under the target.
        set internal 1
        foreach pin [get_pins -quiet -leaf -of_objects [get_nets -quiet -segments $net]] {
            if {[string first $target_prefix $pin] < 0} { set internal 0; break }
        }
        if {!$internal} { continue }
        if {[ro_normalize_space [get_property ROUTE $net]] eq ""} {
            error "V2 lock gate: internal net has no route: $net"
        }
        set_property IS_ROUTE_FIXED true $net
        incr n_locked
    }
    puts "V2_IMPORT_LOCK cells=2560 nets=$n_locked (internal TAP/chain/Q only)"
}
