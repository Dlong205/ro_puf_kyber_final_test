VERILATOR ?= verilator
TOP := ntt_multiplier_tb
EXE := V$(TOP)
MDIR := obj_dir

FLAGS := --cc --exe --timing --top-module $(TOP) --Mdir $(MDIR) \
	-CFLAGS "-std=c++17 -O2" \
	-Wno-WIDTH -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-fatal

SRCS := ../../rtl/common/generic_mult.sv ntt_multiplier_tb.sv ntt_multiplier_main.cpp

$(MDIR)/$(EXE): $(SRCS)
	$(VERILATOR) $(FLAGS) $(SRCS)
	$(MAKE) -C $(MDIR) -f V$(TOP).mk V$(TOP)

multiplier: $(MDIR)/$(EXE)
	@./$(MDIR)/$(EXE)

xilinx-ro-lint:
	$(VERILATOR) --lint-only --top-module kp_ro_cell \
		-Wno-fatal -Wno-UNOPTFLAT -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM \
		xilinx_lut6_l_stub.sv ../../rtl/puf/kp_ro_cell.sv \
		../../rtl/puf/kp_ro_cell_xilinx.sv

clean:
	rm -rf $(MDIR)

.PHONY: multiplier xilinx-ro-lint clean
