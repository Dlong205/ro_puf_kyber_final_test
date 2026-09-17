## Zynq-7020 laboratory Edge image: 50 MHz board oscillator, 100 MHz core.
set_property -dict {PACKAGE_PIN N18 IOSTANDARD LVCMOS33} [get_ports CLK50MHZ]
create_clock -name clk_in_50 -period 20.000 -waveform {0.000 10.000} [get_ports CLK50MHZ]

set_property -dict {PACKAGE_PIN W8 IOSTANDARD LVCMOS33} [get_ports UART_RXD]
set_property -dict {PACKAGE_PIN W9 IOSTANDARD LVCMOS33} [get_ports UART_TXD]
set_property -dict {PACKAGE_PIN G19 IOSTANDARD LVCMOS33} [get_ports {SW[0]}]
set_property -dict {PACKAGE_PIN G20 IOSTANDARD LVCMOS33} [get_ports {SW[1]}]
set_property -dict {PACKAGE_PIN K16 IOSTANDARD LVCMOS33} [get_ports {LED[0]}]
set_property -dict {PACKAGE_PIN J16 IOSTANDARD LVCMOS33} [get_ports {LED[1]}]

## The generated 100 MHz clock is derived automatically through PLLE2_BASE.
## Intentional RO loops are audited again by the implementation script.
set_property SEVERITY {Warning} [get_drc_checks LUTLP-1]
