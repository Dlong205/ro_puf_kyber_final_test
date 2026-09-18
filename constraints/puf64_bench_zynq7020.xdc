## Zynq-7020 constraints for the C1-C4 diagnostic RO bench.
## Target: xc7z020clg400-2
create_clock -name clk_in_50mhz -period 20.0 [get_ports CLK50MHZ]
set_property -dict {PACKAGE_PIN N18 IOSTANDARD LVCMOS33} [get_ports CLK50MHZ]
create_generated_clock -name clk_sys_100mhz \
    -source [get_pins -hierarchical -filter {NAME =~ "*mmcm_i/CLKIN1"}] \
    -multiply_by 2 -divide_by 1 \
    [get_pins -hierarchical -filter {NAME =~ "*bufg_sys/O"}]

set_property -dict {PACKAGE_PIN W8 IOSTANDARD LVCMOS33} [get_ports UART_RXD]
set_property -dict {PACKAGE_PIN W9 IOSTANDARD LVCMOS33} [get_ports UART_TXD]
set_property -dict {PACKAGE_PIN G19 IOSTANDARD LVCMOS33} [get_ports {SW[0]}]
set_property -dict {PACKAGE_PIN G20 IOSTANDARD LVCMOS33} [get_ports {SW[1]}]
set_property -dict {PACKAGE_PIN K16 IOSTANDARD LVCMOS33} [get_ports {LED[0]}]
set_property -dict {PACKAGE_PIN J16 IOSTANDARD LVCMOS33} [get_ports {LED[1]}]

set_property ALLOW_COMBINATORIAL_LOOPS true [get_nets -quiet -hierarchical -filter {NAME =~ "*u_bench*ro_cell*/t*"}]
set_false_path -through [get_nets -quiet -hierarchical -filter {NAME =~ "*u_bench*ro_cell*/t*"}]
set_property DONT_TOUCH true [get_cells -quiet -hierarchical -filter {NAME =~ "*u_bench*ro_cell*/u_backend/LUT6_*"}]
set_property SEVERITY {Warning} [get_drc_checks LUTLP-1]
