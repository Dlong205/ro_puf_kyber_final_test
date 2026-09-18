## B5 narrow route lock for the RO->prescaler tap net only.
set_property FIXED_ROUTE { { CLBLL_L_B CLBLL_LOGIC_OUTS9  { WW4BEG1 ER1BEG1 CLK1 CLBLM_M_CLK }  IMUX_L18 CLBLL_LL_B2 }  } [get_nets -hierarchical -filter {NAME == "u_bench/ro_tap"}]
set_property IS_ROUTE_FIXED true [get_nets -hierarchical -filter {NAME == "u_bench/ro_tap"}]
