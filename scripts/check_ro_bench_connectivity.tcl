# C1-C4 topology/resource assertions for the diagnostic RO bench.
proc check_ro_bench_connectivity {stage num_ro} {
    set ro_luts [get_cells -quiet -hierarchical \
        -filter {NAME =~ "*u_bench*ro_cell*/u_backend/LUT6_*" && DONT_TOUCH == 1}]
    if {[llength $ro_luts] != 4 * $num_ro} {
        error "BENCH $stage: expected [expr {4*$num_ro}] RO LUTs, found [llength $ro_luts]"
    }
    set presc [get_cells -quiet -hierarchical \
        -filter {NAME =~ "*presc_fdce" && DONT_TOUCH == 1}]
    if {[llength $presc] != $num_ro} {
        error "BENCH $stage: expected $num_ro prescaler FDCEs, found [llength $presc]"
    }
    set stages [get_cells -quiet -hierarchical \
        -filter {REF_NAME == "FDCE" && DONT_TOUCH == 1 && NAME =~ "*stage*ff*"}]
    if {[llength $stages] != $num_ro * 16} {
        error "BENCH $stage: expected [expr {$num_ro*16}] ripple stages, found [llength $stages]"
    }
    set clock_prims [get_cells -quiet -hierarchical \
        -filter {REF_NAME =~ "BUFG*" || REF_NAME =~ "BUFH*" || REF_NAME =~ "BUFR*"}]
    foreach cp $clock_prims {
        set din [get_pins -quiet -of_objects $cp -filter {DIRECTION == IN}]
        set innet [get_nets -quiet -of_objects $din]
        if {[string match "*u_bench*" $innet]} {
            error "BENCH $stage: bench net promoted to [get_property REF_NAME $cp]: $innet"
        }
    }
    set bufgs [get_cells -quiet -hierarchical -filter {REF_NAME =~ "BUFG*"}]
    puts "BENCH ${stage}_BUFG_COUNT=[llength $bufgs]"

    foreach p $presc {
        set cpin [get_pins -quiet -of_objects $p -filter {REF_PIN_NAME == "C"}]
        set cnet [get_nets -quiet -of_objects $cpin]
        set drivers [get_pins -quiet -of_objects $cnet -filter {DIRECTION == OUT}]
        if {[llength $drivers] != 1} {
            error "BENCH $stage: prescaler clock must have exactly 1 driver: $cnet"
        }
    }
    if {$stage eq "route"} {
        if {[regexp {routing errors\s*:\s*([1-9][0-9]*)} [report_route_status -return_string]]} {
            error "BENCH $stage: routing errors present"
        }
    }
    puts "BENCH ${stage}_PASS num_ro=$num_ro ro_luts=[llength $ro_luts] presc=[llength $presc] stages=[llength $stages]"
}
