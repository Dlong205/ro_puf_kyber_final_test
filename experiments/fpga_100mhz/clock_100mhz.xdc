create_clock -name sys_clk -period 10.000 [get_ports clk]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
