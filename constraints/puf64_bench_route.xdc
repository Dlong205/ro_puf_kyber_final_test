## C2 narrow FIXED_ROUTE for each RO tap net.
set_property FIXED_ROUTE { { CLBLM_M_A CLBLM_LOGIC_OUTS12  { NW2BEG0 SR1BEG_S0 ER1BEG1 CLK1 CLBLM_M_CLK }  BYP_ALT0 BYP_BOUNCE0 IMUX36 CLBLM_L_D2 }  } [get_nets -hierarchical -filter {NAME == "u_bench/ro[0].counter/clk"}]
set_property IS_ROUTE_FIXED true [get_nets -hierarchical -filter {NAME == "u_bench/ro[0].counter/clk"}]
set_property FIXED_ROUTE { { CLBLM_M_A CLBLM_LOGIC_OUTS12  { SR1BEG1 CLK_L0 CLBLM_L_CLK }  WR1BEG1 BYP_ALT4 BYP_BOUNCE4 IMUX36 CLBLM_L_D2 }  } [get_nets -hierarchical -filter {NAME == "u_bench/ro[1].counter/clk"}]
set_property IS_ROUTE_FIXED true [get_nets -hierarchical -filter {NAME == "u_bench/ro[1].counter/clk"}]
set_property FIXED_ROUTE { { CLBLM_M_C CLBLM_LOGIC_OUTS14  { NR1BEG2 FAN_ALT5 FAN_BOUNCE5 CLK1 CLBLM_M_CLK }  SR1BEG3 IMUX40 CLBLM_M_D1 }  } [get_nets -hierarchical -filter {NAME == "u_bench/ro[2].counter/clk"}]
set_property IS_ROUTE_FIXED true [get_nets -hierarchical -filter {NAME == "u_bench/ro[2].counter/clk"}]
set_property FIXED_ROUTE { { CLBLM_L_C CLBLM_L_CMUX CLBLM_LOGIC_OUTS18  { NE2BEG0 WR1BEG1 CLK0 CLBLM_L_CLK }  IMUX41 CLBLM_L_D1 }  } [get_nets -hierarchical -filter {NAME == "u_bench/ro[3].counter/clk"}]
set_property IS_ROUTE_FIXED true [get_nets -hierarchical -filter {NAME == "u_bench/ro[3].counter/clk"}]
