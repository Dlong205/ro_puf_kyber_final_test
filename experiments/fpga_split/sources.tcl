# Explicit shared dependencies. Executable with tclsh to list/hash inputs before
# Vivado starts. FPGA backends are selected by the normal (no ASIC/model) build.
namespace eval fpga_split {
    variable here [file dirname [file normalize [info script]]]
    variable root [file normalize [file join $here .. ..]]
    variable common {
        rtl/common/generic_bram.sv
        rtl/common/generic_fifo.sv
        rtl/common/generic_mult.sv
        rtl/common/generic_rom.sv
        rtl/common/generic_srl.sv
        rtl/common/generic_blk_mem_wrapper.sv
        rtl/common/generic_c_shift_ram_wrapper.sv
        rtl/common/generic_dist_mem_wrapper.sv
    }
    variable keccak {
        rtl/hash_core/ADDER.v rtl/hash_core/ALGORITHM.v
        rtl/hash_core/CHI1.v rtl/hash_core/CHI2.v
        rtl/hash_core/Chi_3_Iota.v rtl/hash_core/IOTA.v
        rtl/hash_core/RC.v rtl/hash_core/THETA1.v
        rtl/hash_core/THETA2_RHO_PI.v
        rtl/kyber/ref/keccak_f1600_client.v
        rtl/kyber/ref/keccak_f1600_server.v
    }
    variable kyber {
        rtl/kyber/ref/Kyber_Client.v rtl/kyber/ref/Kyber_Server.v
        rtl/kyber/ref/NTT_core_Client.v rtl/kyber/ref/NTT_core_Server.v
        rtl/kyber/ref/butterfly_Client.v rtl/kyber/ref/butterfly_Server.v
        rtl/kyber/ref/hash_core_Client.v rtl/kyber/ref/hash_core_Server.v
        rtl/kyber/ref/encode_Client.v rtl/kyber/ref/encode_Server.v
        rtl/kyber/ref/decode_Client.v rtl/kyber/ref/decode_Server.v
        rtl/kyber/ref/decode_keccak.v rtl/kyber/ref/fifo_wrappers.v
        rtl/kyber/ref/LUT.v rtl/kyber/ref/mux4to2.v
        rtl/kyber/ref/pattern.v rtl/kyber/ref/reduc.v
        rtl/kyber/ref/sha3_shake_core.v
        experiments/fpga_split/k2_ooc_tops.sv
    }
    variable fe {
        rtl/fuzzy_extractor/fuzzy_extractor.sv
        rtl/fuzzy_extractor/xilinx_encode.v rtl/fuzzy_extractor/xilinx_decoder.v
        rtl/fuzzy_extractor/bch_encode.v rtl/fuzzy_extractor/bch_blank_ecc.v
        rtl/fuzzy_extractor/bch_syndrome.v
        rtl/fuzzy_extractor/bch_syndrome_method1.v
        rtl/fuzzy_extractor/bch_syndrome_method2.v
        rtl/fuzzy_extractor/bch_sigma_bma_serial.v
        rtl/fuzzy_extractor/bch_error_tmec.v rtl/fuzzy_extractor/bch_chien.v
        rtl/fuzzy_extractor/bch_math.v rtl/fuzzy_extractor/compare_cla.v
        rtl/fuzzy_extractor/compare_cla_xilinx.v
        rtl/fuzzy_extractor/matrix.v rtl/fuzzy_extractor/util.v
        rtl/fuzzy_extractor/buff.v rtl/fuzzy_extractor/fifo.v
    }
    variable puf {
        rtl/puf/kp_ro_cell.sv rtl/puf/kp_ro_cell_xilinx.sv
        rtl/puf/kp_puf_cells.sv rtl/puf/kp_puf_control.sv
        rtl/puf/kp_puf_top.sv
    }
    variable tops [dict create client fpga_split_client_k2 \
        server fpga_split_server_k2 kdf kdf_keccak \
        fe fuzzy_extractor puf kp_puf_top]

    proc top {block} {
        variable tops
        if {![dict exists $tops $block]} {
            error "Unknown block '$block'; choose client, server, kdf, fe or puf"
        }
        return [dict get $tops $block]
    }

    proc sources {block} {
        variable root; variable common; variable keccak; variable kyber
        variable fe; variable puf
        top $block
        switch -- $block {
            client - server {set rel [concat $common $keccak $kyber]}
            kdf {set rel [concat $common $keccak {rtl/top/kdf_keccak.sv}]}
            fe {set rel $fe}
            puf {set rel $puf}
        }
        set result {}
        foreach name $rel {
            set path [file join $root $name]
            if {![file isfile $path]} {error "Missing source: $path"}
            lappend result $path
        }
        return $result
    }

    proc includes {} {
        variable root
        return [list [file join $root rtl common] \
            [file join $root rtl hash_core] \
            [file join $root rtl kyber ref] \
            [file join $root rtl fuzzy_extractor]]
    }

    proc inputs {block} {
        variable root; variable here
        set result [sources $block]
        switch -- $block {
            client - server - kdf {
                lappend result [file join $root rtl hash_core keccak_pkg.vh]
            }
            fe {
                # Hash every BCH header, including transitive include/function
                # dependencies, even if a parameter prunes some definitions.
                set result [concat $result [lsort [glob \
                    [file join $root rtl fuzzy_extractor *.vh]]]]
            }
        }
        foreach name {sources.tcl synth_block.tcl clock_50mhz.xdc run_ooc.sh} {
            lappend result [file join $here $name]
        }
        return $result
    }
}

if {[file normalize [info script]] eq [file normalize $argv0]} {
    if {[llength $argv] != 1} {error "usage: tclsh sources.tcl <block>"}
    foreach path [fpga_split::inputs [lindex $argv 0]] {puts $path}
}
