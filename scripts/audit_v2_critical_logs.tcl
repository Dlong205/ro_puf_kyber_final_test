# Generic project-flow critical-warning log gate for V2 images (pure TCL).
# Same proven algorithm as the I4/R2 gates, parameterized: scans runme.log
# files, expects exactly <exp_count> warnings of <exp_id> from <exp_src> with
# RO set <idx_lo>..<idx_hi> under <hier_token>, and zero unexpected.
# Usage (under tclsh or Vivado):
#   source scripts/audit_v2_critical_logs.tcl
#   v2_audit_critical_logs $log_list "Synth 8-295" "kp_ro_cell_xilinx.sv" \
#       "u_macro/u_bench/" 64 0 63
proc v2_audit_critical_logs {log_list exp_id exp_src hier_token exp_count idx_lo idx_hi} {
    set blocks {}
    foreach log_path $log_list {
        if {![file isfile $log_path]} {
            error "V2 log gate: run log missing: $log_path"
        }
        set ch [open $log_path r]
        set lines [split [read $ch] "\n"]
        close $ch
        set current ""
        foreach line $lines {
            if {[string match "*CRITICAL WARNING*" $line] && ![string match "#*" $line]} {
                if {$current ne ""} { lappend blocks [list $log_path $current] }
                set current $line
            } elseif {$current ne ""} {
                append current "\n$line"
            }
        }
        if {$current ne ""} { lappend blocks [list $log_path $current] }
    }
    set unexpected {}
    set n_expected 0
    set idx_seen [dict create]
    foreach pair $blocks {
        lassign $pair src_log block
        set first [lindex [split $block "\n"] 0]
        if {[string match "*$exp_id*" $first] && [string match "*$exp_src*" $first]} {
            if {![string match "*Found timing loop*" $block] && \
                    ![string match "*Inferred a:*${hier_token}*" $block]} {
                lappend unexpected "$src_log :: $first"
                continue
            }
            foreach {full src} [regexp -all -inline {([\w./-]+\.sv):[0-9]+} $block] {
                if {[file tail $src] ne $exp_src} {
                    error "V2 log gate: $exp_id block cites foreign source $src"
                }
            }
            set found_any 0
            foreach {full sub} [regexp -all -inline {\\?ro\[([0-9]+)\]} $block] {
                set found_any 1
                if {$sub < $idx_lo || $sub > $idx_hi} {
                    error "V2 log gate: block names RO $sub outside $idx_lo..$idx_hi"
                }
                dict set idx_seen $sub 1
            }
            if {!$found_any} {
                error "V2 log gate: block names no RO: [string range $first 0 160]"
            }
            foreach line [split $block "\n"] {
                if {[string match {*ro\[*} $line] && \
                        ![string match "*${hier_token}*" $line]} {
                    error "V2 log gate: RO loop line outside $hier_token: [string range $line 0 200]"
                }
            }
            incr n_expected
        } else {
            lappend unexpected "$src_log :: $first"
        }
    }
    if {$n_expected != $exp_count} {
        error "V2 log gate: expected $exp_count $exp_id warnings, found $n_expected"
    }
    for {set k $idx_lo} {$k <= $idx_hi} {incr k} {
        if {![dict exists $idx_seen $k]} {
            error "V2 log gate: RO index $k missing from the $exp_id set"
        }
    }
    if {[llength $unexpected] != 0} {
        error "V2 log gate: [llength $unexpected] unexpected critical warnings, first: [lindex $unexpected 0]"
    }
    puts "V2_CRITICAL_WARNINGS: $exp_count expected RO-loop warnings, 0 unexpected critical warnings"
}
