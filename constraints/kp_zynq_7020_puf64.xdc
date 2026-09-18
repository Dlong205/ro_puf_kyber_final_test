## Zynq 7020 Constraints for the PUF64 all-pairs characterization image.
## Target: xc7z020clg400-2
## LOCK_PINS is intentionally absent here: the counter-per-RO image must be
## placed first, then the accepted implementation exports LOC/BEL first and
## LOCK_PINS after, so RO input pins never collide on a slice.

## PL Clock (50MHz on this board, pin N18)
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

## Combinatorial-loop constraints for all 64 ring oscillators.
set_property ALLOW_COMBINATORIAL_LOOPS true [get_nets -quiet -hierarchical -filter {NAME =~ "*u_puf*ring*/t*"}]
set_false_path -through [get_nets -quiet -hierarchical -filter {NAME =~ "*u_puf*ring*/t*"}]

## Keep the physical oscillator cells.
set_property DONT_TOUCH true [get_cells -quiet -hierarchical -filter {NAME =~ "*u_puf*ring*LUT6_*"}]

## The intentional RO feedback loops require a scoped LUTLP-1 waiver.
set_property SEVERITY {Warning} [get_drc_checks LUTLP-1]
