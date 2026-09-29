set dcp [lindex $argv 0]
open_checkpoint $dcp
set all [get_cells -quiet -hierarchical -filter {NAME =~ "*u_kcv_anchor"}]
puts "SYNTH_ANCHOR_EXACT=[llength $all]"
foreach c $all { puts "ANCHOR=$c REF=[get_property REF_NAME $c]" }
close_design
puts "DONE"