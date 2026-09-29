# Routed-netlist proof for the mandatory, non-secret PicoRV32 supervisor.
# Source this file, then call picorv32_final_audit <supervisor hierarchy>.

proc picorv32_final_audit {hier} {
    set cpu_cells [get_cells -quiet -hierarchical -filter "NAME =~ ${hier}/u_cpu/*"]
    if {[llength $cpu_cells] < 100} {
        error "PICORV32 gate: CPU logic missing or unexpectedly small ([llength $cpu_cells] cells)"
    }

    set cpu_regs [get_cells -quiet -hierarchical -filter "NAME =~ ${hier}/u_cpu/cpuregs*/*"]
    if {[llength $cpu_regs] == 0} {
        error "PICORV32 gate: CPU register file missing"
    }

    set fw_cells [get_cells -quiet -hierarchical -filter "NAME =~ ${hier}/u_firmware/*"]
    set fw_bram [filter $fw_cells {REF_NAME =~ RAMB36* || REF_NAME =~ RAMB18*}]
    if {[llength $fw_bram] != 1} {
        error "PICORV32 gate: expected exactly one firmware BRAM, got [llength $fw_bram]"
    }

    set trap_nets [get_nets -quiet -hierarchical -filter "NAME =~ ${hier}/cpu_trap*"]
    if {[llength $trap_nets] != 1} {
        error "PICORV32 gate: cpu_trap status net missing"
    }
    set auth_cells [get_cells -quiet -hierarchical -filter "NAME == ${hier}/authorized_start_reg"]
    set ready_cells [get_cells -quiet -hierarchical -filter "NAME == ${hier}/cpu_ready_reg"]
    set pending_cells [get_cells -quiet -hierarchical -filter "NAME == ${hier}/request_pending_reg"]
    if {[llength $auth_cells] != 1 || [llength $ready_cells] != 1 ||
        [llength $pending_cells] != 1} {
        error "PICORV32 gate: authorization state registers missing auth=[llength $auth_cells] ready=[llength $ready_cells] pending=[llength $pending_cells]"
    }

    # The CPU is a control-plane only. Secret-bearing blocks must remain
    # outside its hierarchy; this catches accidental hierarchy migration in
    # addition to the source-level port allowlist gate.
    foreach forbidden {u_puf64_core u_fe u_kcv u_kdf u_mlkem shared_secret response} {
        set hits [get_cells -quiet -hierarchical -filter "NAME =~ ${hier}/*${forbidden}*"]
        if {[llength $hits] != 0} {
            error "PICORV32 gate: secret/datapath cell entered CPU supervisor hierarchy: $forbidden"
        }
    }

    puts "PICORV32_NETLIST_PROOF_PASS cpu_cells=[llength $cpu_cells] cpu_regs=[llength $cpu_regs] firmware_bram=[llength $fw_bram]"
}
