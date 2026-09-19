## I4 Zynq-7020 operational preservation shell.
## Target: xc7z020clg400-2. This is not a final release constraint set.

create_clock -name clk_in_50mhz -period 20.0 [get_ports CLK50MHZ]
set_property -dict {PACKAGE_PIN N18 IOSTANDARD LVCMOS33} [get_ports CLK50MHZ]

create_generated_clock -name clk_sys_100mhz \
    -source [get_pins mmcm_i/CLKIN1] -multiply_by 2 -divide_by 1 \
    [get_pins bufg_sys/O]

set_property -dict {PACKAGE_PIN W8 IOSTANDARD LVCMOS33} [get_ports UART_RXD]
set_property -dict {PACKAGE_PIN W9 IOSTANDARD LVCMOS33} [get_ports UART_TXD]
set_property -dict {PACKAGE_PIN K16 IOSTANDARD LVCMOS33} [get_ports {LED[0]}]
set_property -dict {PACKAGE_PIN J16 IOSTANDARD LVCMOS33} [get_ports {LED[1]}]

set_property ALLOW_COMBINATORIAL_LOOPS true \
    [get_nets -quiet -hierarchical -filter {NAME =~ "*u_puf64_physical/u_puf*ro_cell*/t*"}]
set_false_path -through \
    [get_nets -quiet -hierarchical -filter {NAME =~ "*u_puf64_physical/u_puf*ro_cell*/t*"}]
set_property DONT_TOUCH true \
    [get_cells -quiet -hierarchical -filter {NAME =~ "*u_puf64_physical/u_puf*ro_cell*/u_backend/LUT6_*"}]

## Only the intentional LUT feedback loops are waived.
set_property SEVERITY {Warning} [get_drc_checks LUTLP-1]
