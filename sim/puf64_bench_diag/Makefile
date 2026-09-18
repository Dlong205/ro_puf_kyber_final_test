VERILATOR ?= verilator
TOP := tb_puf64_bench_diag
OBJ := obj_dir

.PHONY: sim clean

sim:
	$(VERILATOR) --binary --timing -j 1 --threads 1 \
		--top-module $(TOP) --Mdir $(OBJ) \
		-Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD -Wno-MULTIDRIVEN \
		../../rtl/debug/puf64_bench_diag.sv \
		tb_puf64_bench_diag.sv
	./$(OBJ)/V$(TOP)

clean:
	rm -rf $(OBJ)
