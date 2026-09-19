VERILATOR ?= verilator
TOP := tb_edge_puf64_operational_core
OBJ := obj_dir

.PHONY: sim clean

sim:
	$(VERILATOR) --binary --timing -j 1 --threads 1 \
		--top-module $(TOP) --Mdir $(OBJ) \
		-Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD -Wno-UNUSEDSIGNAL \
		-Wno-PINCONNECTEMPTY -Wno-PROCASSINIT -Wno-SYNCASYNCNET \
		-Wno-UNDRIVEN -Wno-UNUSEDPARAM -Wno-MULTIDRIVEN \
		-I../../rtl/top -I../../rtl/common -I../../rtl/hash_core \
		-I../../rtl/kyber/ref -I../fuzzy_extractor/rtl_tcq0 \
		../../rtl/common/generic_blk_mem_wrapper.sv \
		../../rtl/common/generic_c_shift_ram_wrapper.sv \
		../../rtl/common/generic_dist_mem_wrapper.sv \
		../../rtl/common/generic_bram.sv ../../rtl/common/generic_mult.sv \
		../../rtl/common/generic_fifo.sv \
		../../rtl/hash_core/ALGORITHM.v ../../rtl/hash_core/THETA1.v \
		../../rtl/hash_core/THETA2_RHO_PI.v ../../rtl/hash_core/CHI1.v \
		../../rtl/hash_core/CHI2.v ../../rtl/hash_core/Chi_3_Iota.v \
		../../rtl/hash_core/IOTA.v ../../rtl/hash_core/RC.v \
		../../rtl/hash_core/ADDER.v \
		../../rtl/kyber/ref/sha3_shake_core.v \
		../fuzzy_extractor/rtl_tcq0/bch_blank_ecc.v \
		../fuzzy_extractor/rtl_tcq0/bch_chien.v \
		../fuzzy_extractor/rtl_tcq0/bch_encode.v \
		../fuzzy_extractor/rtl_tcq0/bch_error_tmec.v \
		../fuzzy_extractor/rtl_tcq0/bch_math.v \
		../fuzzy_extractor/rtl_tcq0/bch_sigma_bma_serial.v \
		../fuzzy_extractor/rtl_tcq0/bch_syndrome.v \
		../fuzzy_extractor/rtl_tcq0/bch_syndrome_method1.v \
		../fuzzy_extractor/rtl_tcq0/bch_syndrome_method2.v \
		../fuzzy_extractor/rtl_tcq0/buff.v \
		../fuzzy_extractor/rtl_tcq0/compare_cla.v \
		../fuzzy_extractor/rtl_tcq0/compare_cla_xilinx.v \
		../fuzzy_extractor/rtl_tcq0/fifo.v \
		../fuzzy_extractor/rtl_tcq0/matrix.v \
		../fuzzy_extractor/rtl_tcq0/util.v \
		../fuzzy_extractor/rtl_tcq0/xilinx_decoder.v \
		../fuzzy_extractor/rtl_tcq0/xilinx_encode.v \
		../fuzzy_extractor/rtl_tcq0/fuzzy_extractor.sv \
		../fuzzy_extractor/xilinx_carry4_stub.v \
		../../rtl/top/edge_root_binding.sv \
		../../rtl/puf/kp_puf64_mapping_scheduler.sv \
		../../rtl/top/edge_puf64_operational_core.sv \
		$(TOP).sv
	./$(OBJ)/V$(TOP)

clean:
	rm -rf $(OBJ)
