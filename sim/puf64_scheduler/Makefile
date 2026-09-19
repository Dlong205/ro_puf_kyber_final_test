VERILATOR ?= verilator
TOP := tb_kp_puf64_mapping_scheduler
OBJ := obj_dir

.PHONY: sim clean

sim:
	$(VERILATOR) --binary --timing -j 1 --threads 1 \
		--top-module $(TOP) --Mdir $(OBJ) \
		-Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD -Wno-MULTIDRIVEN \
		-Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL \
		-I../../rtl/top \
		../../rtl/puf/kp_puf64_mapping_scheduler.sv \
		$(TOP).sv
	./$(OBJ)/V$(TOP)

clean:
	rm -rf $(OBJ)
