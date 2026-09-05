# Shared helpers for exporting and auditing the physical implementation of the
# 32 FPGA ring oscillators.  The inventory starts from the output pin of each
# physical RO LUT so hierarchical net aliases cannot be counted twice.

proc ro_normalize_space {value} {
    regsub -all {\s+} [string trim $value] { } normalized
    return $normalized
}

proc ro_sha256_file {path} {
    if {![file isfile $path]} {
        error "Cannot hash missing file: $path"
    }
    set output [exec sha256sum -- $path]
    set digest [lindex $output 0]
    if {![regexp {^[0-9a-f]{64}$} $digest]} {
        error "Unexpected sha256sum output for $path: $output"
    }
    return $digest
}

proc ro_find_route_net {cell} {
    set output_pins [get_pins -quiet -of_objects $cell \
        -filter {DIRECTION == OUT}]
    if {[llength $output_pins] != 1} {
        error "Expected one output pin on $cell, found [llength $output_pins]"
    }

    # A signal crossing hierarchy has several aliases (t3, o, ro_out...).
    # Select the canonical top net for that physical group so the exported
    # constraint resolves to one stable object on the next implementation.
    set route_nets [lsort -unique -dictionary [get_nets -quiet -segments \
        -top_net_of_hierarchical_group -of_objects $output_pins]]
    if {[llength $route_nets] != 1} {
        error "Expected one ROUTE-bearing net for $cell, found $route_nets"
    }
    return [lindex $route_nets 0]
}

proc ro_actual_input_pin_map {cell} {
    set mappings {}
    foreach pin [lsort -dictionary [get_pins -quiet -of_objects $cell \
            -filter {DIRECTION == IN}]] {
        set site_pins [get_site_pins -quiet -of_objects $pin]
        if {[llength $site_pins] == 0} {
            continue
        }
        if {[llength $site_pins] != 1} {
            error "Ambiguous site-pin mapping for $pin: $site_pins"
        }
        set logical_pin [file tail $pin]
        set physical_pin [file tail [lindex $site_pins 0]]
        lappend mappings "${logical_pin}:${physical_pin}"
    }
    return [lsort -dictionary $mappings]
}

proc ro_lock_input_pin_map {cell} {
    # LOCK_PINS uses LUT-relative A1..A6 names even when the selected BEL is a
    # B/C/D LUT. The fingerprint retains the true site pin (for example B6),
    # while this form is suitable for an XDC LOCK_PINS property.
    set mappings {}
    foreach mapping [ro_actual_input_pin_map $cell] {
        lassign [split $mapping :] logical_pin site_pin
        if {![regexp {^[A-D]([1-6])$} $site_pin unused pin_index]} {
            error "Unsupported LUT site pin for $cell: $site_pin"
        }
        lappend mappings "${logical_pin}:A${pin_index}"
    }
    return [lsort -dictionary $mappings]
}

proc ro_collect_physical_inventory {} {
    set ro_luts [lsort -dictionary [get_cells -quiet -hierarchical \
        -filter {NAME =~ "*u_puf*ring*LUT6*"}]]
    if {[llength $ro_luts] != 128} {
        error "Expected 128 physical RO LUTs, found [llength $ro_luts]"
    }

    set net_set [dict create]
    foreach cell $ro_luts {
        dict set net_set [ro_find_route_net $cell] 1
    }
    set ro_nets [lsort -dictionary [dict keys $net_set]]
    if {[llength $ro_nets] != 128} {
        error "Expected 128 unique physical RO nets, found [llength $ro_nets]"
    }

    set endpoint_set [dict create]
    foreach net $ro_nets {
        set segments [get_nets -quiet -segments $net]
        set leaf_pins [get_pins -quiet -leaf -of_objects $segments]
        foreach cell [get_cells -quiet -of_objects $leaf_pins] {
            dict set endpoint_set $cell 1
        }
    }
    set endpoint_cells [lsort -dictionary [dict keys $endpoint_set]]

    return [dict create \
        ro_luts $ro_luts \
        ro_nets $ro_nets \
        endpoint_cells $endpoint_cells]
}

proc ro_write_physical_fingerprint {path inventory} {
    set channel [open $path w]
    set ro_luts [dict get $inventory ro_luts]
    set ro_nets [dict get $inventory ro_nets]
    set endpoint_cells [dict get $inventory endpoint_cells]

    puts $channel "RO_PHYSICAL_FINGERPRINT_V2"
    puts $channel "SUMMARY\tro_luts=[llength $ro_luts]\tro_nets=[llength $ro_nets]\tendpoint_cells=[llength $endpoint_cells]"

    foreach cell $endpoint_cells {
        set ref_name [get_property REF_NAME $cell]
        set init [get_property INIT $cell]
        set loc [get_property LOC $cell]
        set bel [get_property BEL $cell]
        if {$ref_name eq "" || $init eq "" || $loc eq "" || $bel eq ""} {
            close $channel
            error "Endpoint cell inventory is incomplete: $cell REF=$ref_name INIT=$init LOC=$loc BEL=$bel"
        }
        set pin_map [join [ro_actual_input_pin_map $cell] ,]
        if {$pin_map eq ""} {
            close $channel
            error "Endpoint cell has no physical input-pin mapping: $cell"
        }
        puts $channel "CELL\t$cell\t$ref_name\t$init\t$loc\t$bel\t$pin_map"
    }

    foreach net $ro_nets {
        set segments [get_nets -quiet -segments $net]
        set pins [lsort -dictionary [get_pins -quiet -leaf -of_objects $segments]]
        set route [ro_normalize_space [get_property ROUTE $net]]
        if {$route eq ""} {
            close $channel
            error "RO net is not routed: $net"
        }
        puts $channel "NET\t$net\t[join $pins ,]\t$route"
    }
    close $channel
}

proc ro_compare_physical_fingerprints {golden_path actual_path} {
    set golden_channel [open $golden_path r]
    set golden [read $golden_channel]
    close $golden_channel
    set actual_channel [open $actual_path r]
    set actual [read $actual_channel]
    close $actual_channel

    if {$golden eq $actual} {
        return
    }

    set golden_lines [split $golden "\n"]
    set actual_lines [split $actual "\n"]
    set limit [expr {min([llength $golden_lines], [llength $actual_lines])}]
    for {set index 0} {$index < $limit} {incr index} {
        if {[lindex $golden_lines $index] ne [lindex $actual_lines $index]} {
            puts "RO_FINGERPRINT_EXPECTED=[lindex $golden_lines $index]"
            puts "RO_FINGERPRINT_ACTUAL=[lindex $actual_lines $index]"
            break
        }
    }
    error "RO physical fingerprint differs from the accepted RC1 baseline"
}
