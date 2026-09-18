.PHONY: all kcv gate record phase1 loopback e2e clean

all:
	verilator --binary --timing -j 1 --Mdir obj_dir \
		--top-module tb_edge_puf_mlkem_handoff -Wall -Wno-fatal \
		-Wno-DECLFILENAME -Wno-TIMESCALEMOD -Wno-UNUSEDSIGNAL \
		-Wno-PINCONNECTEMPTY -Wno-PROCASSINIT -Wno-SYNCASYNCNET \
		-I../../rtl/common -I../../rtl/hash_core -I../../rtl/kyber/ref \
		../../rtl/top/edge_puf_mlkem_core.sv \
		../../rtl/top/edge_root_binding.sv \
		tb_edge_puf_mlkem_handoff.sv
	./obj_dir/Vtb_edge_puf_mlkem_handoff

kcv:
	verilator --binary --timing -j 1 --Mdir obj_dir_kcv \
		--top-module tb_edge_root_binding -Wall -Wno-fatal \
		-Wno-DECLFILENAME -Wno-TIMESCALEMOD -Wno-UNUSEDSIGNAL \
		-Wno-PINCONNECTEMPTY -Wno-PROCASSINIT -Wno-SYNCASYNCNET \
		-I../../rtl/common -I../../rtl/hash_core -I../../rtl/kyber/ref \
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
		../../rtl/top/edge_root_binding.sv tb_edge_root_binding.sv
	./obj_dir_kcv/Vtb_edge_root_binding

gate:
	verilator --binary --timing -j 1 --Mdir obj_dir_gate \
		--top-module tb_edge_kcv_gate -Wall -Wno-fatal \
		-Wno-DECLFILENAME -Wno-TIMESCALEMOD -Wno-UNUSEDSIGNAL \
		-Wno-PINCONNECTEMPTY -Wno-PROCASSINIT -Wno-SYNCASYNCNET \
		-I../../rtl/common -I../../rtl/hash_core -I../../rtl/kyber/ref \
		../../rtl/top/edge_puf_mlkem_core.sv \
		../../rtl/top/edge_root_binding.sv \
		tb_edge_kcv_gate.sv
	./obj_dir_gate/Vtb_edge_kcv_gate

record:
	verilator --binary --timing -j 1 --Mdir obj_dir_record \
		--top-module tb_helper_record -Wall -Wno-fatal \
		-Wno-DECLFILENAME -Wno-TIMESCALEMOD -Wno-UNUSEDSIGNAL \
		-Wno-PINCONNECTEMPTY -Wno-PROCASSINIT -Wno-SYNCASYNCNET \
		-I../../rtl/top -I.. \
		../../rtl/top/helper_record.sv tb_helper_record.sv
	./obj_dir_record/Vtb_helper_record

phase1:
	verilator --binary --timing -j 1 --Mdir obj_dir_phase1 \
		--top-module tb_edge_phase1 -Wall -Wno-fatal \
		-Wno-DECLFILENAME -Wno-TIMESCALEMOD -Wno-UNUSEDSIGNAL \
		-Wno-PINCONNECTEMPTY -Wno-PROCASSINIT -Wno-SYNCASYNCNET \
		-Wno-UNDRIVEN \
		-I../../rtl/top -I../../rtl/common -I../../rtl/hash_core \
		-I../../rtl/kyber/ref \
		../../rtl/top/edge_puf_mlkem_core.sv \
		../../rtl/top/edge_root_binding.sv \
		tb_edge_phase1.sv
	./obj_dir_phase1/Vtb_edge_phase1

loopback:
	verilator --binary --timing -j 1 --Mdir obj_dir_loopback \
		--top-module tb_edge_enroll_loopback -Wall -Wno-fatal \
		-Wno-DECLFILENAME -Wno-TIMESCALEMOD -Wno-UNUSEDSIGNAL \
		-Wno-PINCONNECTEMPTY -Wno-PROCASSINIT -Wno-SYNCASYNCNET \
		-Wno-UNDRIVEN \
		-I../../rtl/top -I../../rtl/common -I../../rtl/hash_core \
		-I../../rtl/kyber/ref \
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
		../../rtl/puf/uart_rx.v ../../rtl/puf/uart_tx.v \
		../../rtl/top/helper_record.sv \
		../../rtl/top/edge_root_binding.sv \
		../../rtl/top/edge_puf_mlkem_core.sv \
		../../rtl/top/edge_uart_transport.sv \
		tb_edge_enroll_loopback.sv
	./obj_dir_loopback/Vtb_edge_enroll_loopback

e2e: ../fuzzy_extractor/rtl_tcq0/.stamp
	verilator --binary --timing -j 1 --Mdir obj_dir_e2e \
		--top-module tb_edge_phase1_e2e -Wall -Wno-fatal \
		-Wno-DECLFILENAME -Wno-TIMESCALEMOD -Wno-UNUSEDSIGNAL \
		-Wno-PINCONNECTEMPTY -Wno-PROCASSINIT -Wno-SYNCASYNCNET \
		-Wno-UNDRIVEN -Wno-UNUSEDPARAM \
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
		../../rtl/top/edge_puf_mlkem_core.sv \
		tb_edge_phase1_e2e.sv
	./obj_dir_e2e/Vtb_edge_phase1_e2e

clean:
	rm -rf obj_dir obj_dir_kcv obj_dir_gate obj_dir_record obj_dir_phase1 \
		obj_dir_loopback obj_dir_e2e
