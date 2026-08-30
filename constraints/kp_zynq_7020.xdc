## Zynq 7020 Constraints for KP-PUF (kp_puf_top, 264-bit)
## Target: xc7z020clg400-2

## PL Clock (Assume 50MHz for typical Chinese Zynq boards, pin N18)
create_clock -period 20.0 [get_ports CLK100MHZ]
set_property -dict {PACKAGE_PIN N18 IOSTANDARD LVCMOS33} [get_ports CLK100MHZ]

## UART (Mapped to J24 Expansion Header Pins 11 and 13)
set_property -dict {PACKAGE_PIN W8 IOSTANDARD LVCMOS33} [get_ports UART_RXD]
set_property -dict {PACKAGE_PIN W9 IOSTANDARD LVCMOS33} [get_ports UART_TXD]

## Switches (PL_KEY)
set_property -dict {PACKAGE_PIN G19 IOSTANDARD LVCMOS33} [get_ports {SW[0]}]
set_property -dict {PACKAGE_PIN G20 IOSTANDARD LVCMOS33} [get_ports {SW[1]}]

## LEDs (PL_LED)
set_property -dict {PACKAGE_PIN K16 IOSTANDARD LVCMOS33} [get_ports {LED[0]}]
set_property -dict {PACKAGE_PIN J16 IOSTANDARD LVCMOS33} [get_ports {LED[1]}]

## Combinatorial-loop constraints for all 32 Ring Oscillators.
## Vivado 2020.1 XDC does not accept Tcl `if`, so use direct quiet queries.
## Post-synthesis audit: feedback query = 128 nets, LUT query = 128 cells.
set_property ALLOW_COMBINATORIAL_LOOPS true [get_nets -quiet -hierarchical -filter {NAME =~ "*u_puf*ring*/t*"}]
set_false_path -through [get_nets -quiet -hierarchical -filter {NAME =~ "*u_puf*ring*/t*"}]

## LUT pin locking for repeatable RO routing.
set_property LOCK_PINS {I0:A6 I1:A5 I2:A4 I3:A3 I4:A2 I5:A1} [get_cells -quiet -hierarchical -filter {NAME =~ "*u_puf*ring*LUT6*"}]
set_property DONT_TOUCH true [get_cells -quiet -hierarchical -filter {NAME =~ "*u_puf*ring*LUT6*"}]

## The intentional RO feedback loops require a scoped LUTLP-1 waiver.
set_property SEVERITY {Warning} [get_drc_checks LUTLP-1]
