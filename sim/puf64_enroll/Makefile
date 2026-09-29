VERILATOR ?= verilator
OBJ := obj_dir
FE_DIR := ../fuzzy_extractor/rtl_tcq0
FE_STAMP := $(FE_DIR)/.stamp

.PHONY: sim reconstruct-vector clean

sim: $(FE_STAMP)
	mkdir -p $(OBJ)
	$(VERILATOR) --binary --timing -j 1 --threads 1 \
		--top-module tb_puf64_enroll --Mdir $(OBJ) \
		-Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD -Wno-MULTIDRIVEN \
		-Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL -Wno-DECLFILENAME \
		-Wno-PINCONNECTEMPTY -Wno-SYNCASYNCNET \
		-I$(FE_DIR) \
		-I../../rtl/common -I../../rtl/hash_core -I../../rtl/kyber/ref -I../../rtl/top \
		$(FE_DIR)/bch_blank_ecc.v \
		$(FE_DIR)/bch_chien.v \
		$(FE_DIR)/bch_encode.v \
		$(FE_DIR)/bch_error_tmec.v \
		$(FE_DIR)/bch_math.v \
		$(FE_DIR)/bch_sigma_bma_serial.v \
		$(FE_DIR)/bch_syndrome.v \
		$(FE_DIR)/bch_syndrome_method1.v \
		$(FE_DIR)/bch_syndrome_method2.v \
		$(FE_DIR)/buff.v \
		$(FE_DIR)/compare_cla.v \
		$(FE_DIR)/compare_cla_xilinx.v \
		$(FE_DIR)/fifo.v \
		$(FE_DIR)/matrix.v \
		$(FE_DIR)/util.v \
		$(FE_DIR)/xilinx_decoder.v \
		$(FE_DIR)/xilinx_encode.v \
		$(FE_DIR)/fuzzy_extractor.sv \
		../fuzzy_extractor/xilinx_carry4_stub.v \
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
		../../rtl/top/edge_root_binding.sv \
		tb_puf64_enroll.sv
	./$(OBJ)/Vtb_puf64_enroll

reconstruct-vector: $(FE_STAMP)
	mkdir -p $(OBJ)_reconstruct
	$(VERILATOR) --binary --timing -j 1 --threads 1 \
		--top-module tb_puf64_reconstruct_vector --Mdir $(OBJ)_reconstruct \
		-Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD -Wno-MULTIDRIVEN \
		-Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL -Wno-DECLFILENAME \
		-Wno-PINCONNECTEMPTY -Wno-SYNCASYNCNET \
		-I$(FE_DIR) \
		-I../../rtl/common -I../../rtl/hash_core -I../../rtl/kyber/ref -I../../rtl/top \
		$(FE_DIR)/bch_blank_ecc.v \
		$(FE_DIR)/bch_chien.v \
		$(FE_DIR)/bch_encode.v \
		$(FE_DIR)/bch_error_tmec.v \
		$(FE_DIR)/bch_math.v \
		$(FE_DIR)/bch_sigma_bma_serial.v \
		$(FE_DIR)/bch_syndrome.v \
		$(FE_DIR)/bch_syndrome_method1.v \
		$(FE_DIR)/bch_syndrome_method2.v \
		$(FE_DIR)/buff.v \
		$(FE_DIR)/compare_cla.v \
		$(FE_DIR)/compare_cla_xilinx.v \
		$(FE_DIR)/fifo.v \
		$(FE_DIR)/matrix.v \
		$(FE_DIR)/util.v \
		$(FE_DIR)/xilinx_decoder.v \
		$(FE_DIR)/xilinx_encode.v \
		$(FE_DIR)/fuzzy_extractor.sv \
		../fuzzy_extractor/xilinx_carry4_stub.v \
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
		../../rtl/top/edge_root_binding.sv \
		tb_puf64_reconstruct_vector.sv
	./$(OBJ)_reconstruct/Vtb_puf64_reconstruct_vector

$(FE_STAMP):
	$(MAKE) -C ../fuzzy_extractor rtl_tcq0/.stamp

clean:
	rm -rf $(OBJ) $(OBJ)_reconstruct
	rm -f enroll_result_helper.hex enroll_result_key.hex enroll_result_kcv.hex
