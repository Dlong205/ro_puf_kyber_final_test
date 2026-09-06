VERILATOR ?= verilator
TOP := tb_reset_sync
MDIR := obj_dir
EXE := $(MDIR)/V$(TOP)

$(EXE): tb_reset_sync.sv ../../rtl/asic/reset_sync_n.sv
	$(VERILATOR) --binary --timing -j 1 --Mdir $(MDIR) --top-module $(TOP) \
		-Wall -Wno-fatal ../../rtl/asic/reset_sync_n.sv tb_reset_sync.sv

reset-smoke: $(EXE)
	@$(EXE)

clean:
	rm -rf $(MDIR)

.PHONY: reset-smoke clean
