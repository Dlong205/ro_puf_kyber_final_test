`ifndef _CONFIG_VH_
`define _CONFIG_VH_

`ifndef CONFIG_HAS_CARRY4
`ifdef KP_TARGET_ASIC
`define CONFIG_HAS_CARRY4 0
`else
`define CONFIG_HAS_CARRY4 1
`endif
`endif

`ifndef CONFIG_PIPELINE_LFSR
`define CONFIG_PIPELINE_LFSR 1
`endif

`ifndef CONFIG_CONST_OP
`define CONFIG_CONST_OP 1
`endif

`ifndef CONFIG_BERLEKAMP
`define CONFIG_BERLEKAMP 0
`endif


`ifndef LUT_SZ
`define CONFIG_LUT_SZ 6
`endif

`ifndef LUT_MAX_SZ
`define CONFIG_LUT_MAX_SZ 8
`endif

`endif
