VERILATOR = verilator
VERILATOR_FLAGS = --cc --exe --timing \
    -CFLAGS "-std=c++17 -O2" \
    -LDFLAGS "-lstdc++" \
    -I../../rtl/puf \
    -Wno-WIDTH -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL \
    -Wno-CASEINCOMPLETE -Wno-MULTITOP -Wno-MULTIDRIVEN \
    -Wno-UNSIGNED -Wno-EOFNEWLINE -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND \
    -Wno-MODDUP -Wno-TIMESCALEMOD -Wno-BLKANDNBLK -Wno-IMPLICIT -Wno-IMPLICITSTATIC \
    -Wno-CASEOVERLAP -Wno-CASEX -Wno-fatal \
    -DVERILATOR -DKP_RO_BEHAVIORAL

TOP_MODULE = tb_kp_puf_simple
SIM_EXE = V$(TOP_MODULE)

TB_CPP = tb_kp_puf_main.cpp
TB_SV  = tb_kp_puf.sv

RTL_SRCS = ../../rtl/puf/kp_ro_cell.sv \
           ../../rtl/puf/kp_ro_cell_model.sv \
           ../../rtl/puf/kp_puf_cells.sv \
           ../../rtl/puf/kp_puf_control.sv \
           ../../rtl/puf/kp_puf_top.sv

all: sim

obj_dir/$(SIM_EXE): $(TB_SV) $(RTL_SRCS) $(TB_CPP)
	$(VERILATOR) $(VERILATOR_FLAGS) --top-module $(TOP_MODULE) $(RTL_SRCS) $(TB_SV) $(TB_CPP)
	$(MAKE) -C obj_dir -f V$(TOP_MODULE).mk V$(TOP_MODULE)

sim: obj_dir/$(SIM_EXE)
	@echo "Running simulation..."
	@./obj_dir/$(SIM_EXE)

clean:
	rm -rf obj_dir *.vcd

.PHONY: all sim clean
