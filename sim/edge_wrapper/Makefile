.PHONY: all kcv clean

all:
	verilator --binary --timing -j 1 --Mdir obj_dir \
		--top-module tb_edge_puf_mlkem_handoff -Wall -Wno-fatal \
		-Wno-DECLFILENAME -Wno-TIMESCALEMOD -Wno-UNUSEDSIGNAL \
		-Wno-PINCONNECTEMPTY -Wno-PROCASSINIT -Wno-SYNCASYNCNET \
		../../rtl/top/edge_puf_mlkem_core.sv tb_edge_puf_mlkem_handoff.sv
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

clean:
	rm -rf obj_dir obj_dir_kcv
