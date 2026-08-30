# Vivado TCL Script for Kyber-512 KAT Verification
# Usage: vivado -mode batch -source run_kat.tcl

# 1. Create project (if not exists)
if {[catch {project_open POWER_OPTIMIZE.xpr}]} {
    create_project KAT_Verification ./kat_project -part xc7a100tcsg324-1
    set_property target_language Verilog [current_project]
}

# 2. Add TCHES Kyber reference sources
set kyber_ref_files {
    ../../rtl/kyber/ref/Kyber_Server.v
    ../../rtl/kyber/ref/Kyber_Client.v
    ../../rtl/kyber/ref/NTT_core_Server.v
    ../../rtl/kyber/ref/NTT_core_Client.v
    ../../rtl/kyber/ref/butterfly_Server.v
    ../../rtl/kyber/ref/butterfly_Client.v
    ../../rtl/kyber/ref/hash_core_Server.txt
    ../../rtl/kyber/ref/hash_core_Client.v
    ../../rtl/kyber/ref/pattern.v
    ../../rtl/kyber/ref/reduc.v
    ../../rtl/kyber/ref/LUT.v
    ../../rtl/kyber/ref/encode_Server.v
    ../../rtl/kyber/ref/encode_Client.v
    ../../rtl/kyber/ref/decode_Server.v
    ../../rtl/kyber/ref/decode_Client.v
    ../../rtl/kyber/ref/LUT.v
    ../../rtl/kyber/ref/reduc.v
}

# Add design sources
foreach f $kyber_ref_files {
    if {[file exists $f]} {
        add_files -norecurse $f
    } else {
        puts "WARNING: File not found: $f"
    }
}

# Add testbench
add_files -fileset sim_1 ../../sim/kyber/tb_kyber_kat.sv
add_files ../../sim/kyber/PQCkemKAT_1632.rsp

# Set top module for simulation
set_property top tb_kyber_kat [get_filesets sim_1]

# Set simulation properties
set_property target_simulator Vivado [current_project]
set_property xsim.simulate.runtime 1000000 [current_project]

# 3. Create simulation run
launch_simulation

# 4. Run simulation for sufficient time
run 2000000 ns

# Check results
# The testbench will print PASS/FAIL to Tcl console

# Close simulation
close_sim