# Phase B connectivity gate for the PUF64 single-RO microbenchmark.
# Fails the build when the RO -> prescaler -> counter clock path is not a
# single, non-constant, fully routed connection in the real netlist.
proc check_ro_microbench_connectivity {stage} {
    set presc [get_cells -quiet -hierarchical -filter {NAME =~ "*presc_fdce" && DONT_TOUCH == 1}]
    if {[llength $presc] != 1} {
        error "MICROBENCH $stage: expected exactly 1 DONT_TOUCH prescaler FDCE, found [llength $presc]"
    }
    set presc [lindex $presc 0]

    set c_pin [get_pins -quiet -of_objects $presc -filter {REF_PIN_NAME == "C"}]
    if {[llength $c_pin] != 1} {
        error "MICROBENCH $stage: prescaler C pin not found on $presc"
    }
    set tap_nets [get_nets -quiet -of_objects $c_pin]
    if {[llength $tap_nets] != 1} {
        error "MICROBENCH $stage: prescaler C is not driven by exactly one net: $tap_nets"
    }
    set tap_net [lindex $tap_nets 0]

    set drivers [get_pins -quiet -of_objects $tap_net -filter {DIRECTION == OUT}]
    if {[llength $drivers] != 1} {
        error "MICROBENCH $stage: ro_tap must have exactly one driver, found [llength $drivers]"
    }
    set driver_cell [get_cells -quiet -of_objects [lindex $drivers 0]]
    set driver_ref [get_property REF_NAME $driver_cell]
    if {$driver_ref eq "GND" || $driver_ref eq "VCC" || $driver_ref eq "TIEOFF" || $driver_ref eq "GND_0"} {
        error "MICROBENCH $stage: ro_tap is driven by constant $driver_ref"
    }
    if {![string match "LUT*" $driver_ref] && ![string match "kp_ro_cell*" $driver_ref]} {
        error "MICROBENCH $stage: ro_tap driver is not an RO cell: $driver_cell ($driver_ref)"
    }
    set ro_luts [get_cells -quiet -hierarchical -filter {NAME =~ "*u_bench*ro0*/LUT6_*" && DONT_TOUCH == 1}]
    if {[llength $ro_luts] != 4} {
        error "MICROBENCH $stage: expected 4 DONT_TOUCH RO LUTs, found [llength $ro_luts]"
    }

    set q_pin [get_pins -quiet -of_objects $presc -filter {REF_PIN_NAME == "Q"}]
    set q_net [get_nets -quiet -of_objects $q_pin]
    if {[llength $q_net] != 1} {
        error "MICROBENCH $stage: prescaler Q net not found"
    }
    set q_net [lindex [get_nets -quiet -of_objects $q_pin] 0]
    if {$q_net eq ""} {
        error "MICROBENCH $stage: prescaler Q net not found"
    }
    set q_loads [get_pins -quiet -of_objects $q_net -filter {DIRECTION == IN}]
    set clock_loads 0
    set enable_path 0
    foreach pin $q_loads {
        set rn [get_property REF_PIN_NAME $pin]
        if {$rn eq "C"} {
            incr clock_loads
        }
        set lc [get_cells -quiet -of_objects $pin]
        if {[llength $lc] == 1 && [string match "LUT*" [get_property REF_NAME $lc]]} {
            set enable_path 1
        }
    }
    if {$clock_loads < 1 && $enable_path == 0} {
        error "MICROBENCH $stage: prescaler Q neither clocks nor enables a counter"
    }

    if {$stage eq "route"} {
        set route [get_property ROUTE $tap_net]
        if {$route eq ""} {
            error "MICROBENCH $stage: ro_tap is not routed"
        }
        set status [report_route_status -return_string]
        if {[regexp {routing errors\s*:\s*([1-9][0-9]*)} $status]} {
            error "MICROBENCH $stage: routing errors present"
        }
    }

    set clock_prims [get_cells -quiet -hierarchical -filter {REF_NAME =~ "BUFG*" || REF_NAME =~ "BUFH*" || REF_NAME =~ "BUFR*"}]
    foreach cp $clock_prims {
        set din [get_pins -quiet -of_objects $cp -filter {DIRECTION == IN}]
        set innet [get_nets -quiet -of_objects $din]
        if {[string match "*u_bench*" $innet]} {
            error "MICROBENCH $stage: RO/prescaler net promoted to [get_property REF_NAME $cp]: $innet"
        }
    }
    set bufgs [get_cells -quiet -hierarchical -filter {REF_NAME =~ "BUFG*"}]
    puts "MICROBENCH ${stage}_BUFG_COUNT=[llength $bufgs]"

    set stage_ffs [get_cells -quiet -hierarchical \
        -filter {REF_NAME == "FDCE" && DONT_TOUCH == 1 && NAME =~ "*u_bench*stage*"}]
    if {[llength $stage_ffs] == 0} {
        error "MICROBENCH $stage: no ripple counter stages found"
    }
    foreach ff $stage_ffs {
        set cpin [get_pins -quiet -of_objects $ff -filter {REF_PIN_NAME == "C"}]
        set cnet [get_nets -quiet -of_objects $cpin]
        set loads [get_pins -quiet -of_objects $cnet -filter {REF_PIN_NAME == "C"}]
        if {[llength $loads] > 1} {
            error "MICROBENCH $stage: ripple clock net fanout > 1: $cnet"
        }
    }
    puts "MICROBENCH ${stage}_RIPPLE_STAGES=[llength $stage_ffs]"

    puts "MICROBENCH ${stage}_PASS prescaler=$presc tap=$tap_net driver=$driver_cell Qclk=$clock_loads Qen=$enable_path stages=[llength $stage_ffs]"
}
