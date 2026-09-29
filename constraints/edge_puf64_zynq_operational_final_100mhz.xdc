## Operational FINAL (single-clock) Zynq-7020 constraints, macro-V2 edition.
## Target: xc7z020clg400-2.  Board pins identical to the V2 shell (board
## facts); hierarchy patterns target the V2 macro (u_macro/u_bench).
## No placement/route locks: the macro arrives via the frozen OOC DCP
## (bd0cd620..) with IS_*_FIXED locks applied post-import in the build
## script.  No FIXED_ROUTE.  Single-clock: only clk_in_50mhz + clk_sys_100mhz
## are defined here; the stale OOC macro_clk primary is removed post-import
## (reset_timing + read_xdc) in scripts/build_puf64_operational_final.tcl,
## shell constraint only, macro placement/routing untouched.

create_clock -name clk_in_50mhz -period 20.0 [get_ports CLK50MHZ]
set_property -dict {PACKAGE_PIN N18 IOSTANDARD LVCMOS33} [get_ports CLK50MHZ]

create_generated_clock -name clk_sys_100mhz \
    -source [get_pins mmcm_i/CLKIN1] -multiply_by 2 -divide_by 1 \
    [get_pins bufg_sys/O]

set_property -dict {PACKAGE_PIN W8 IOSTANDARD LVCMOS33} [get_ports UART_RXD]
set_property -dict {PACKAGE_PIN W9 IOSTANDARD LVCMOS33} [get_ports UART_TXD]
set_property -dict {PACKAGE_PIN K16 IOSTANDARD LVCMOS33} [get_ports {LED[0]}]
set_property -dict {PACKAGE_PIN J16 IOSTANDARD LVCMOS33} [get_ports {LED[1]}]

# RO-loop properties and false paths are applied by the build Tcl only after
# the frozen macro checkpoint has been imported. Keeping those object queries
# out of this XDC avoids false critical warnings when synthesis intentionally
# sees an empty macro black box.

## Only the intentional LUT feedback loops are waived.
set_property SEVERITY {Warning} [get_drc_checks LUTLP-1]
