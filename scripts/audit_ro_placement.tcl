# Compare each expected LOC/BEL against the current design. Merely checking
# that a cell is placed would also accept an unconstrained automatic placement.
proc audit_ro_placement {map_file} {
    set map_channel [open $map_file r]
    set map_text [read $map_channel]
    close $map_channel
    set expected [dict create]
    foreach line [split $map_text "\n"] {
        if {![string match "set_property *" $line]} { continue }
        # Braced NAME filter is part of the generated, literal XDC syntax.
        if {![regexp {^set_property (LOC|BEL) ([^ ]+) \[get_cells -hierarchical -filter \{NAME == "([^"]+)"\}\]$} $line unused prop value name]} {
            error "Unrecognized placement-map line: $line"
        }
        if {[dict exists $expected $name $prop]} {
            error "Duplicate $prop constraint for $name"
        }
        dict set expected $name $prop $value
    }
    if {[dict size $expected] != 128} {
        error "Expected exactly 128 mapped RO LUTs, got [dict size $expected]"
    }
    dict for {name props} $expected {
        set cell [get_cells -quiet -hierarchical -filter [format {NAME == "%s"} $name]]
        if {[llength $cell] != 1} {
            error "RO cell query must match exactly once: $name (got [llength $cell])"
        }
        foreach prop {BEL LOC} {
            if {![dict exists $props $prop]} { error "Missing $prop for $name" }
            set expected_value [dict get $props $prop]
            set actual_value [get_property $prop $cell]
            if {$actual_value ne $expected_value} {
                error "RO $prop mismatch: $name expected=$expected_value actual=$actual_value"
            }
        }
    }
    puts "PUF_EXACT_RO_PLACEMENT_PASS cells=128 properties=256"
}
