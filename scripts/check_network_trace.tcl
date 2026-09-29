set dcp [lindex $argv 0]
open_checkpoint $dcp
set lut [get_cells -quiet -hierarchical -filter {NAME =~ "*u_scrub/squeeze_reg[1599]_i_1"}]
foreach c $lut {
    puts "LUT=$c REF=[get_property REF_NAME $c] INIT=[get_property INIT $c]"
    foreach pin [get_pins -quiet -of_objects $c -filter {DIRECTION == IN}] {
        set rp [get_property REF_PIN_NAME $pin]
        set sn [get_nets -quiet -of_objects $pin]
        set src "<none>"
        if {[llength $sn] == 1} {
            set s0 [lindex $sn 0]
            set src [get_property NAME $s0]
            set drv [get_pins -quiet -of_objects $s0 -filter {DIRECTION == OUT}]
            set drvcell "<none>"
            set drvref ""
            foreach d $drv {
                set cl [get_cells -quiet -of_objects $d]
                foreach cc $cl {
                    set drvcell $cc
                    set drvref [get_property REF_NAME $cc]
                }
            }
            puts "  IN $rp FROM $src DRIVER=$drvcell REF=$drvref"
        } else {
            puts "  IN $rp FROM CONST/FLAT (netcount=[llength $sn])"
        }
    }
}
close_design
puts "DONE"