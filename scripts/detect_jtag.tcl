# Read-only inventory of connected FPGA devices.  This script never programs
# volatile configuration or flash.
open_hw_manager
connect_hw_server
set targets [get_hw_targets -quiet]
puts "JTAG_TARGET_COUNT=[llength $targets]"
foreach target $targets {
    puts "JTAG_TARGET=$target"
    current_hw_target $target
    if {[catch {open_hw_target $target} detail]} {
        puts "JTAG_OPEN_ERROR=$detail"
        continue
    }
    set devices [get_hw_devices -quiet]
    foreach device $devices {
        puts "JTAG_DEVICE=$device PART=[get_property PART $device]"
    }
    close_hw_target
}
close_hw_manager
