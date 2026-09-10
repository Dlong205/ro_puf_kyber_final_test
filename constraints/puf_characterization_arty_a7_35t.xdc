## Arty A7-35 Rev. D/E characterization-only constraints.
## Pin mapping follows Digilent Arty-A7-35-Master.xdc.

set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports CLK100MHZ]
create_clock -add -name sys_clk_pin -period 10.000 -waveform {0 5} [get_ports CLK100MHZ]

## Configuration bank voltage on Arty A7.
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]

## USB-UART: FPGA RX is FT2232 TX; FPGA TX is FT2232 RX.
set_property -dict {PACKAGE_PIN A9 IOSTANDARD LVCMOS33} [get_ports UART_RXD]
set_property -dict {PACKAGE_PIN D10 IOSTANDARD LVCMOS33} [get_ports UART_TXD]

set_property -dict {PACKAGE_PIN A8 IOSTANDARD LVCMOS33} [get_ports {SW[0]}]
set_property -dict {PACKAGE_PIN C11 IOSTANDARD LVCMOS33} [get_ports {SW[1]}]
set_property -dict {PACKAGE_PIN H5 IOSTANDARD LVCMOS33} [get_ports {LED[0]}]
set_property -dict {PACKAGE_PIN J5 IOSTANDARD LVCMOS33} [get_ports {LED[1]}]

## The 32 physical ring oscillators intentionally contain 128 loop nets.
set_property ALLOW_COMBINATORIAL_LOOPS true [get_nets -quiet -hierarchical -filter {NAME =~ "*u_puf*ring*/t*"}]
set_false_path -through [get_nets -quiet -hierarchical -filter {NAME =~ "*u_puf*ring*/t*"}]
set_property LOCK_PINS {I0:A6 I1:A5 I2:A4 I3:A3 I4:A2 I5:A1} [get_cells -quiet -hierarchical -filter {NAME =~ "*u_puf*ring*LUT6*"}]
set_property DONT_TOUCH true [get_cells -quiet -hierarchical -filter {NAME =~ "*u_puf*ring*LUT6*"}]
set_property SEVERITY {Warning} [get_drc_checks LUTLP-1]
