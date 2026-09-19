VERILATOR ?= verilator
TOP := tb_puf64_ro_bench
OBJ := obj_dir
NUM_RO ?= 8

.PHONY: sim sim64 sim_status sim_status_% clean
STATUS_SCENARIOS := stable timeout zero overflow

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

# Injected-status regression: replace the two leaf cells with test doubles so
# the production FSM is exercised in stable/timeout/zero/overflow states.
sim_status:
	@for s in $(STATUS_SCENARIOS); do \
		echo "=== injected-status scenario: $$s ==="; \
		$(MAKE) --no-print-directory sim_status_$$s || exit $$?; \
	done

sim_status_%: SCENARIO = $(shell echo $* | tr a-z A-Z)
sim_status_%:
	$(VERILATOR) --binary --timing -j 1 --threads 1 \
		--top-module tb_puf64_ro_bench_status --Mdir obj_dir_status_$* \
		-Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD -Wno-MULTIDRIVEN \
		-DTB_SCENARIO_$(SCENARIO) \
		../../rtl/debug/puf64_ro_bench.sv \
		status_stubs.sv tb_puf64_ro_bench_status.sv
	./obj_dir_status_$*/Vtb_puf64_ro_bench_status

clean:
	rm -rf $(OBJ) obj_dir_status_*
