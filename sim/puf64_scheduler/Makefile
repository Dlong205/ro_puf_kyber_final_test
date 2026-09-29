VERILATOR ?= verilator
TOP := tb_kp_puf64_mapping_scheduler
OBJ := obj_dir
# Active mapping generation: include dir wins over the stale legacy
# rtl/top copy. PUF64_MAPPING_G2=1 selects generation G2 (tag 0x005d).
ifeq ($(PUF64_MAPPING_G2),1)
MAPDIR := ../../rtl/puf/v2_mapping_g2
GOLDEN := 5d7cb7b01df33622c70229f326ea0e6cc50f601a4ea4d19ed194afe5a32f6056d8
else
MAPDIR := ../../rtl/puf/v2_mapping_frozen
GOLDEN := 572f0e71187ce4ab968955d4ea4e97cb15b1b9b89b2619b48de1864b6b076056d8
endif

.PHONY: sim clean

sim:
	$(VERILATOR) --binary --timing -j 1 --threads 1 \
		--top-module $(TOP) --Mdir $(OBJ) \
		-Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD -Wno-MULTIDRIVEN \
		-Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL \
		+define+PUF64_GOLDEN_HEX=$(GOLDEN) \
		-I$(MAPDIR) -I../../rtl/top \
		../../rtl/puf/kp_puf64_mapping_scheduler.sv \
		$(TOP).sv
	./$(OBJ)/V$(TOP)

clean:
	rm -rf $(OBJ)
