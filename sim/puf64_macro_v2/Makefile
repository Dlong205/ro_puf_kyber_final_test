VERILATOR ?= verilator
OBJ := obj_dir

.PHONY: sim sim-ripple sim-bench clean

# R1 macro-V2 equivalence (behavioral RO models; unisim stubs for the
# explicit LUT1/FDCE cells and the golden RO backend).
sim: sim-ripple sim-bench

sim-ripple:
	mkdir -p $(OBJ)/ripple
	$(VERILATOR) --binary --timing -j 1 --threads 1 \
		--top-module tb_ripple_v1v2 --Mdir $(OBJ)/ripple \
		-Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD -Wno-MULTIDRIVEN \
		-Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL \
		../../rtl/debug/kp_ripple_counter.sv \
		../../rtl/puf/kp_ripple_counter_v2.sv \
		unisim_stubs.sv \
		tb_ripple_v1v2.sv
	./$(OBJ)/ripple/Vtb_ripple_v1v2

sim-bench:
	mkdir -p $(OBJ)/bench
	$(VERILATOR) --binary --timing -j 1 --threads 1 \
		--top-module tb_bench_v1v2 --Mdir $(OBJ)/bench \
		-Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD -Wno-MULTIDRIVEN \
		-Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL \
		-DKP_RO_BEHAVIORAL \
		../../rtl/puf/kp_ro_cell.sv \
		../../rtl/puf/kp_ro_cell_model.sv \
		../../rtl/puf/kp_ro_cell_xilinx.sv \
		../../rtl/debug/kp_ripple_counter.sv \
		../../rtl/puf/kp_ripple_counter_v2.sv \
		../../rtl/debug/puf64_ro_bench.sv \
		../../rtl/puf/puf64_ro_bench_v2.sv \
		unisim_stubs.sv \
		tb_bench_v1v2.sv
	./$(OBJ)/bench/Vtb_bench_v1v2

clean:
	rm -rf $(OBJ)
