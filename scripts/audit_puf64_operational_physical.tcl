# I4.2/I5.1 shared audit: operational physical preservation checks.
# Sourced by build_puf64_operational.tcl (and post-provision rebuild).  Every
# proc fails closed with an `error` on mismatch; callers must not catch these
# to downgrade them to warnings.
source [file join [file dirname [file normalize [info script]]] ro_physical_common.tcl]

proc i4_audit_hierarchy {} {
    set prefix "u_operational_uart/u_chain/u_puf64_core/u_puf64_physical/u_puf"
    set cells [get_cells -quiet -hierarchical -filter "NAME =~ \"*${prefix}*\""]
    if {[llength $cells] == 0} {
        error "I4 hierarchy gate: physical prefix missing: $prefix"
    }
    # Legacy / characterization tops must not exist in this netlist.
    foreach bad [list "Kyber_System_Top" "Puf_AllPairs64_Characterization_Top" \
            "Puf_AllPairs_Characterization_Top" "Puf_Characterization_Top"] {
        set hits [get_cells -quiet -hierarchical -filter "NAME =~ \"*${bad}*\""]
        if {[llength $hits] != 0} {
            error "I4 top gate: forbidden hierarchy present: $bad ($hits)"
        }
    }
    set top [get_property TOP [current_design]]
    if {$top ne "Edge_Puf64_Zynq_Operational_100MHz_Top"} {
        error "I4 top gate: active top is $top, expected Edge_Puf64_Zynq_Operational_100MHz_Top"
    }
    puts "I4_HIERARCHY=PASS cells=[llength $cells]"
}

proc i4_audit_inventory {} {
    set ro_luts [get_cells -quiet -hierarchical \
        -filter {NAME =~ "*u_puf*ro_cell*/u_backend/LUT6_*"}]
    set presc [get_cells -quiet -hierarchical \
        -filter {NAME =~ "*counter/presc_fdce" && REF_NAME == "FDCE"}]
    set stages [get_cells -quiet -hierarchical \
        -filter {REF_NAME == "FDCE" && NAME =~ "*stage*ff*"}]
    if {[llength $ro_luts] != 256} {
        error "I4 inventory gate: expected 256 RO LUTs, found [llength $ro_luts]"
    }
    if {[llength $presc] != 64} {
        error "I4 inventory gate: expected 64 prescalers, found [llength $presc]"
    }
    if {[llength $stages] != 1088} {
        error "I4 inventory gate: expected 1088 ripple stages, found [llength $stages]"
    }
    # No physical cone folded to a constant or pruned: every LUT/FDCE must
    # still be present with LOC/BEL after synthesis and implementation.
    foreach cell [concat $ro_luts $presc $stages] {
        if {[get_property LOC $cell] eq "" || [get_property BEL $cell] eq ""} {
            error "I4 prune gate: missing LOC/BEL (folded/pruned?): $cell"
        }
        if {[get_property REF_NAME $cell] eq ""} {
            error "I4 prune gate: missing REF_NAME: $cell"
        }
    }
    puts "I4_INVENTORY=PASS ro=256 presc=64 ripple=1088"
    return [list $ro_luts $presc $stages]
}

proc i4_audit_no_global_clocks {ro_luts presc stages} {
    set checked 0
    foreach p $presc {
        set cpin [get_pins -quiet -of_objects $p -filter {REF_PIN_NAME == "C"}]
        set nets [get_nets -quiet -of_objects $cpin]
        foreach net $nets {
            set pins [get_pins -quiet -leaf -of_objects [get_nets -quiet -segments $net]]
            foreach cell [get_cells -quiet -of_objects $pins] {
                set ref [get_property REF_NAME $cell]
                if {$ref eq "BUFG" || $ref eq "BUFGCTRL" || $ref eq "BUFH" || \
                    $ref eq "BUFHCE" || $ref eq "BUFR"} {
                    error "I4 clock gate: ro_tap net $net reaches $ref via $cell"
                }
            }
            incr checked
        }
    }
    foreach s $stages {
        set cpin [get_pins -quiet -of_objects $s -filter {REF_PIN_NAME == "C"}]
        set nets [get_nets -quiet -of_objects $cpin]
        foreach net $nets {
            set pins [get_pins -quiet -leaf -of_objects [get_nets -quiet -segments $net]]
            foreach cell [get_cells -quiet -of_objects $pins] {
                set ref [get_property REF_NAME $cell]
                if {$ref eq "BUFG" || $ref eq "BUFGCTRL" || $ref eq "BUFH" || \
                    $ref eq "BUFHCE" || $ref eq "BUFR"} {
                    error "I4 clock gate: ripple net $net reaches $ref via $cell"
                }
            }
            incr checked
        }
    }
    # RO ring nets themselves must also stay local.
    foreach cell $ro_luts {
        set opin [get_pins -quiet -of_objects $cell -filter {DIRECTION == OUT}]
        set nets [get_nets -quiet -of_objects $opin]
        foreach net $nets {
            set pins [get_pins -quiet -leaf -of_objects [get_nets -quiet -segments $net]]
            foreach ec [get_cells -quiet -of_objects $pins] {
                set ref [get_property REF_NAME $ec]
                if {$ref eq "BUFG" || $ref eq "BUFGCTRL" || $ref eq "BUFH" || \
                    $ref eq "BUFHCE" || $ref eq "BUFR"} {
                    error "I4 clock gate: RO net $net reaches $ref via $ec"
                }
            }
        }
    }
    puts "I4_CLOCK_RESOURCE=PASS checked_clock_nets=$checked"
}

proc i4_audit_ro_tap_endpoints {presc} {
    foreach p $presc {
        set cpin [get_pins -quiet -of_objects $p -filter {REF_PIN_NAME == "C"}]
        set nets [get_nets -quiet -of_objects $cpin]
        if {[llength $nets] != 1} {
            error "I4 tap gate: prescaler C net ambiguous on $p"
        }
        set net [lindex $nets 0]
        set allpins [get_pins -quiet -leaf -of_objects [get_nets -quiet -segments $net]]
        set drivers {}
        set sinks {}
        foreach pin $allpins {
            if {[get_property DIRECTION $pin] eq "OUT"} { lappend drivers $pin } else { lappend sinks $pin }
        }
        if {[llength $drivers] != 1} {
            error "I4 tap gate: ro_tap $net must have exactly one RO driver, found $drivers"
        }
        if {[string first "ro_cell" [lindex $drivers 0]] < 0} {
            error "I4 tap gate: ro_tap $net driver is not an RO cell: [lindex $drivers 0]"
        }
        set found 0
        foreach s $sinks {
            if {$s eq $cpin} { set found 1 }
        }
        if {!$found} {
            error "I4 tap gate: prescaler C pin not in tap sinks: $p $net"
        }
        if {[get_property ROUTE $net] eq ""} {
            error "I4 tap gate: ro_tap not routed: $net"
        }
    }
    puts "I4_TAP_ENDPOINTS=PASS presc=64"
}

proc i4_audit_route_complete {{status_file ""}} {
    set unrouted [get_nets -quiet -hierarchical -filter {ROUTE == "" && TYPE != "GROUND" && TYPE != "POWER"}]
    # The check above is advisory; the authoritative gate is report_route_status.
    if {$status_file eq ""} {
        set status_file [file join [file dirname [file normalize [info script]]] .. reports puf64_operational_preservation post_route_status.rpt]
    }
    report_route_status -file $status_file
    set ch [open $status_file r]
    set data [read $ch]
    close $ch
    if {[regexp -nocase {partial|unrouted|RTSTAT|conflict} $data]} {
        error "I4 route gate: partial route / RTSTAT / conflict detected (see $status_file)"
    }
    puts "I4_ROUTE_STATUS=PASS"
}

proc i4_audit_timing_100mhz {report_path} {
    report_timing_summary -file $report_path -max_paths 10
    set ch [open $report_path r]
    set data [read $ch]
    close $ch
    # Any negative slack line fails the 100 MHz gate.
    if {[regexp {(-[0-9]+\.[0-9]+)} $data]} {
        set wns "unknown"
        if {[regexp -nocase {WNS[^0-9-]*(-[0-9.]+)} $data _ wns] && [string is double $wns] && $wns < 0} {
            error "I4 timing gate: 100 MHz WNS negative ($wns) (see $report_path)"
        }
        if {[regexp {(VIOLATED|Timing constraints are not met)} $data]} {
            error "I4 timing gate: timing violated (see $report_path)"
        }
    }
    if {[regexp {(VIOLATED|Timing constraints are not met)} $data]} {
        error "I4 timing gate: timing violated (see $report_path)"
    }
    puts "I4_TIMING_100MHZ=PASS report=$report_path"
}

# I4.2a critical-warning log gate.  Never uses get_msg_config of the open-DCP
# session (it only counts current-session messages).  Scans the persisted run
# logs instead:
#   synth_1/runme.log, impl_1/runme.log
# Expected set: exactly 64x `Synth 8-295` RO timing loops, one per RO index
# 0..63, each inside u_puf64_physical/u_puf from kp_ro_cell_xilinx.sv.  The
# 8-295 ID is NOT blanket-ignored: a loop outside the physical RO cone, a
# missing/duplicate RO index, or any other critical warning fails the build.
# After the timing fix, `Timing 38-282` must be absent (it lands in the
# unexpected set).  Report wording is exact:
#   64 expected RO-loop warnings, 0 unexpected critical warnings.
proc i4_audit_log_critical_warnings {build_dir stage} {
    set synth_log [file join $build_dir puf64_operational_zynq7020.runs synth_1 runme.log]
    set impl_log [file join $build_dir puf64_operational_zynq7020.runs impl_1 runme.log]
    if {![file isfile $synth_log]} {
        error "I4 critical-warning gate: synth run log missing: $synth_log"
    }
    set ch [open $synth_log r]
    set synth_lines [split [read $ch] "\n"]
    close $ch
    set unexpected {}
    # Partition the synth log into CRITICAL WARNING blocks.
    set blocks {}
    set current ""
    foreach line $synth_lines {
        if {[string match "*CRITICAL WARNING*" $line]} {
            if {$current ne ""} { lappend blocks $current }
            set current $line
        } elseif {$current ne ""} {
            append current "\n$line"
        }
    }
    if {$current ne ""} { lappend blocks $current }
    set n_expected 0
    set idx_seen [dict create]
    foreach block $blocks {
        set first [lindex [split $block "\n"] 0]
        if {[string match "*Synth 8-295*" $first] && \
                [string match "*kp_ro_cell_xilinx.sv*" $first]} {
            # Vivado's Inferred-disable line and the reported loop body can
            # name different ROs, so confinement is verified globally over
            # the whole block, not per-line: every loop cell must sit in the
            # physical RO macro, every source ref must be the RO cell source,
            # and every named RO index must fall in 0..63.
            # The final 8-295 of a synth log can be truncated after its
            # "Inferred a:" line (synth moves on to hierarchy rebuild), so a
            # block qualifies with either the loop body or an in-macro
            # Inferred RO.  Confinement below still applies to all content.
            if {![string match "*Found timing loop*" $block] && \
                    ![string match "*Inferred a:*u_puf64_physical/u_puf/*" $block]} {
                lappend unexpected $first
                continue
            }
            foreach {full src} [regexp -all -inline {([\w./-]+\.sv):[0-9]+} $block] {
                if {[file tail $src] ne "kp_ro_cell_xilinx.sv"} {
                    error "I4 critical-warning gate: 8-295 block cites foreign source $src (possible loop outside the RO cone)"
                }
            }
            set found_any 0
            foreach {full sub} [regexp -all -inline {\\?ro\[([0-9]+)\]} $block] {
                set found_any 1
                if {$sub < 0 || $sub > 63} {
                    error "I4 critical-warning gate: 8-295 block names RO index $sub outside 0..63"
                }
                dict set idx_seen $sub 1
            }
            if {!$found_any} {
                error "I4 critical-warning gate: 8-295 block names no RO index: [string range $first 0 160]"
            }
            foreach line [split $block "\n"] {
                if {[string match {*ro\[*} $line] && \
                        ![string match "*u_puf64_physical/u_puf/*" $line]} {
                    error "I4 critical-warning gate: RO loop line outside the physical macro: [string range $line 0 200]"
                }
            }
            incr n_expected
        } else {
            lappend unexpected $first
        }
    }
    if {$n_expected != 64} {
        error "I4 critical-warning gate: expected 64 Synth 8-295 RO-loop warnings, found $n_expected"
    }
    for {set k 0} {$k < 64} {incr k} {
        if {![dict exists $idx_seen $k]} {
            error "I4 critical-warning gate: RO index $k missing from the 8-295 set"
        }
    }
    # Global backstop (synth log only; impl cannot create loops): every
    # indexed ro[N] mention anywhere in the log -- including INFO-level
    # elaboration dumps outside warning blocks -- must fall in 0..63.
    foreach line $synth_lines {
        foreach {full sub} [regexp -all -inline {\\?ro\[([0-9]+)\]} $line] {
            if {$sub < 0 || $sub > 63} {
                error "I4 critical-warning gate: RO index $sub outside 0..63 in synth log: [string range $line 0 200]"
            }
        }
    }
    if {$stage eq "impl"} {
        if {![file isfile $impl_log]} {
            error "I4 critical-warning gate: impl run log missing: $impl_log"
        }
        set ch [open $impl_log r]
        set impl_data [read $ch]
        close $ch
        foreach line [split $impl_data "\n"] {
            if {[string match "*CRITICAL WARNING*" $line]} {
                lappend unexpected $line
            }
        }
    }
    if {[llength $unexpected] != 0} {
        error "I4 critical-warning gate: [llength $unexpected] unexpected critical warnings, first: [lindex $unexpected 0]"
    }
    puts "I4_CRITICAL_WARNINGS: 64 expected RO-loop warnings, 0 unexpected critical warnings"
}
