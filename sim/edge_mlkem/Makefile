VERILATOR ?= verilator
TOP := tb_edge_mlkem_core
MDIR := obj_dir
EXE := $(MDIR)/V$(TOP)

COMMON := ../../rtl/common/generic_blk_mem_wrapper.sv \
          ../../rtl/common/generic_c_shift_ram_wrapper.sv \
          ../../rtl/common/generic_dist_mem_wrapper.sv \
          ../../rtl/common/generic_bram.sv ../../rtl/common/generic_mult.sv \
          ../../rtl/common/generic_fifo.sv
HASH := ../../rtl/hash_core/ALGORITHM.v ../../rtl/hash_core/THETA1.v \
        ../../rtl/hash_core/THETA2_RHO_PI.v ../../rtl/hash_core/CHI1.v \
        ../../rtl/hash_core/CHI2.v ../../rtl/hash_core/Chi_3_Iota.v \
        ../../rtl/hash_core/IOTA.v ../../rtl/hash_core/RC.v \
        ../../rtl/hash_core/ADDER.v
KYBER := ../../rtl/kyber/ref/Kyber_Server.v \
         ../../rtl/kyber/ref/Kyber_Client.v \
         ../../rtl/kyber/ref/NTT_core_Server.v \
         ../../rtl/kyber/ref/NTT_core_Client.v \
         ../../rtl/kyber/ref/butterfly_Server.v \
         ../../rtl/kyber/ref/butterfly_Client.v \
         ../../rtl/kyber/ref/hash_core_Server.v \
         ../../rtl/kyber/ref/hash_core_Client.v \
         ../../rtl/kyber/ref/sha3_shake_core.v \
         ../../rtl/kyber/ref/keccak_f1600_server.v \
         ../../rtl/kyber/ref/keccak_f1600_client.v \
         ../../rtl/kyber/ref/encode_Server.v \
         ../../rtl/kyber/ref/encode_Client.v \
         ../../rtl/kyber/ref/decode_Server.v \
         ../../rtl/kyber/ref/decode_Client.v \
         ../../rtl/kyber/ref/decode_keccak.v \
         ../../rtl/kyber/ref/fifo_wrappers.v ../../rtl/kyber/ref/LUT.v \
         ../../rtl/kyber/ref/mux4to2.v ../../rtl/kyber/ref/pattern.v \
         ../../rtl/kyber/ref/reduc.v
CONTROL := ../../rtl/top/kdf_keccak.sv \
           ../../rtl/top/edge_seed_controller.sv \
           ../../rtl/top/edge_kem_scrub_controller.sv \
           ../../rtl/top/edge_control_plane.sv \
           ../../rtl/top/edge_mlkem_core.sv
RTL := $(COMMON) $(HASH) $(KYBER) $(CONTROL)

$(EXE): $(RTL) tb_edge_mlkem_core.sv
	$(VERILATOR) --binary --timing -j 1 --Mdir $(MDIR) --top-module $(TOP) \
		-I../../rtl/common -I../../rtl/hash_core -I../../rtl/kyber/ref \
		-Wno-fatal -Wno-WIDTH -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL \
		-Wno-CASEINCOMPLETE -Wno-MULTIDRIVEN -Wno-UNSIGNED \
		-Wno-EOFNEWLINE -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND \
		-Wno-MODDUP -Wno-TIMESCALEMOD -Wno-BLKANDNBLK \
		-Wno-IMPLICIT -Wno-IMPLICITSTATIC -Wno-CASEOVERLAP \
		-Wno-CASEX $(RTL) tb_edge_mlkem_core.sv

run: $(EXE)
	@$(EXE)

invalid: $(EXE)
	@$(EXE) +INVALID_CT

check: run invalid

clean:
	rm -rf $(MDIR)

.PHONY: check run invalid clean
