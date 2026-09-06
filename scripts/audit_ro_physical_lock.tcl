# Post-route audit for the complete RC1 RO physical lock.

source [file join [file dirname [file normalize [info script]]] \
    ro_physical_common.tcl]

proc audit_ro_physical_lock {golden_fingerprint actual_fingerprint} {
    if {![file exists $golden_fingerprint]} {
        error "Golden RO fingerprint not found: $golden_fingerprint"
    }

    set inventory [ro_collect_physical_inventory]
    set endpoint_cells [dict get $inventory endpoint_cells]
    set ro_nets [dict get $inventory ro_nets]
    if {[llength $endpoint_cells] != 136} {
        error "Expected 136 fixed endpoint cells, found [llength $endpoint_cells]"
    }

    foreach cell $endpoint_cells {
        if {![get_property IS_LOC_FIXED $cell] ||
            ![get_property IS_BEL_FIXED $cell]} {
            error "RO endpoint placement is not fixed: $cell"
        }
        if {[get_property LOCK_PINS $cell] eq ""} {
            error "RO endpoint input pins are not locked: $cell"
        }
    }

    foreach net $ro_nets {
        if {![get_property IS_ROUTE_FIXED $net]} {
            error "RO route is not fixed: $net"
        }
        if {[get_property FIXED_ROUTE $net] eq "" ||
            [get_property ROUTE $net] eq ""} {
            error "RO route is empty or only partially constrained: $net"
        }
        if {[ro_normalize_space [get_property FIXED_ROUTE $net]] ne
            [ro_normalize_space [get_property ROUTE $net]]} {
            error "Actual route differs from FIXED_ROUTE: $net"
        }
    }

    file mkdir [file dirname $actual_fingerprint]
    ro_write_physical_fingerprint $actual_fingerprint $inventory

    ro_compare_physical_fingerprints $golden_fingerprint $actual_fingerprint

    puts "RO_PHYSICAL_LOCK_AUDIT=PASS"
    puts "RO_FIXED_ENDPOINT_CELL_COUNT=[llength $endpoint_cells]"
    puts "RO_FIXED_NET_COUNT=[llength $ro_nets]"
}
