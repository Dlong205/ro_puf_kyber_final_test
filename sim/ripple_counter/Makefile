VERILATOR ?= verilator
TOP := tb_kp_ripple_counter
OBJ := obj_dir

.PHONY: sim clean

sim:
	$(VERILATOR) --binary --timing -j 1 --threads 1 \
		--top-module $(TOP) --Mdir $(OBJ) \
		-Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD -Wno-MULTIDRIVEN \
		../../rtl/debug/kp_ripple_counter.sv \
		tb_kp_ripple_counter.sv
	./$(OBJ)/V$(TOP)

clean:
	rm -rf $(OBJ)
