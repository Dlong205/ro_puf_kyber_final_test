## R2 macro-V2 OOC constraints (xc7z020clg400-2, Vivado 2020.1).
## The macro has no board pins; all ports stay unplaced (OOC boundary).
## RO loops are intentional: allow + cut them exactly like the board XDC.
## No FIXED_ROUTE anywhere in this flow.

create_clock -name macro_clk -period 10.0 [get_ports clk]

set_property ALLOW_COMBINATORIAL_LOOPS true \
    [get_nets -quiet -hierarchical -filter {NAME =~ "*ro_cell*/t*"}]
set_false_path -through \
    [get_nets -quiet -hierarchical -filter {NAME =~ "*ro_cell*/t*"}]

## Only the intentional LUT feedback loops are waived.
set_property SEVERITY {Warning} [get_drc_checks LUTLP-1]
