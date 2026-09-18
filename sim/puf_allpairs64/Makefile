VERILATOR ?= verilator
TOP := tb_kp_puf_allpairs64
OBJ := obj_dir

.PHONY: sim clean

# PUF64 candidate pool: 64 ROs / C(64,2)=2016 unordered pairs.  Shares the
# parameterized kp_puf_allpairs_top; only this 64-RO configuration is checked
# here, the 32-RO baseline stays in sim/puf_allpairs.
sim:
	$(VERILATOR) --binary --timing -j 1 --threads 1 \
		--top-module $(TOP) --Mdir $(OBJ) \
		-Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD -Wno-MULTIDRIVEN \
		-DKP_RO_BEHAVIORAL \
		../../rtl/puf/kp_ro_cell.sv \
		../../rtl/puf/kp_ro_cell_model.sv \
		../../rtl/puf/kp_ro_prescaler.sv \
		../../rtl/puf/kp_puf_cells.sv \
		../../rtl/puf/kp_puf_control.sv \
		../../rtl/puf/kp_puf_allpairs_top.sv \
		tb_kp_puf_allpairs64.sv
	./$(OBJ)/V$(TOP)

clean:
	rm -rf $(OBJ)