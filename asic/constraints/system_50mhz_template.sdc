# Preliminary block-level constraint for Kyber_System_Asic_Top.
# This file is intentionally incomplete and MUST NOT be used as sign-off SDC.
# IO delays, uncertainty, transition/capacitance, operating conditions,
# generated/RO clocks, test modes and reset recovery/removal must be completed
# against the selected PDK, pad ring and integration environment.

create_clock -name clk_sys -period 20.000 [get_ports clk_i]

# rst_ni is asynchronously asserted and synchronously released inside the top.
# Do not blanket-false-path reset recovery/removal checks.  Add tool/library-
# specific reset constraints only after the reset and pad cells are selected.
