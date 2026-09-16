VERILATOR ?= verilator
TOP := tb_kp_puf_allpairs
OBJ := obj_dir

.PHONY: sim clean

sim:
	$(VERILATOR) --binary --timing -j 1 --threads 1 \
		--top-module $(TOP) --Mdir $(OBJ) \
		-Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD -Wno-MULTIDRIVEN \
		-DKP_RO_BEHAVIORAL \
		../../rtl/puf/kp_ro_cell.sv \
		../../rtl/puf/kp_ro_cell_model.sv \
		../../rtl/puf/kp_puf_cells.sv \
		../../rtl/puf/kp_puf_control.sv \
		../../rtl/puf/kp_puf_allpairs_top.sv \
		tb_kp_puf_allpairs.sv
	./$(OBJ)/V$(TOP)

clean:
	rm -rf $(OBJ)
