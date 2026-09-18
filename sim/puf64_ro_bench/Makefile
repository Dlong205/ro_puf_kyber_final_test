VERILATOR ?= verilator
TOP := tb_puf64_ro_bench
OBJ := obj_dir
NUM_RO ?= 8

.PHONY: sim sim64 clean

sim:
	$(VERILATOR) --binary --timing -j 1 --threads 1 \
		--top-module $(TOP) --Mdir $(OBJ) \
		-Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD -Wno-MULTIDRIVEN \
		-DKP_RO_BEHAVIORAL -GNUM_RO=$(NUM_RO) \
		../../rtl/debug/puf64_ro_bench.sv \
		../../rtl/debug/kp_ripple_counter.sv \
		../../rtl/puf/kp_ro_cell.sv \
		../../rtl/puf/kp_ro_cell_model.sv \
		../../sim/cells/unisim_cells.sv \
		tb_puf64_ro_bench.sv
	./$(OBJ)/V$(TOP)

sim64:
	$(MAKE) sim NUM_RO=64

clean:
	rm -rf $(OBJ)
