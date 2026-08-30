VERILATOR = verilator
VERILATOR_FLAGS = --cc --exe --timing \
    -CFLAGS "-std=c++17 -O2" \
    -LDFLAGS "-lstdc++" \
    -I$(SIM_RTL_DIR) \
    -Wno-WIDTH -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL \
    -Wno-CASEINCOMPLETE -Wno-MULTITOP -Wno-MULTIDRIVEN \
    -Wno-UNSIGNED -Wno-EOFNEWLINE -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND \
    -Wno-MODDUP -Wno-TIMESCALEMOD -Wno-BLKANDNBLK -Wno-IMPLICIT -Wno-IMPLICITSTATIC \
    -Wno-CASEOVERLAP -Wno-CASEX -Wno-fatal \
    -DVERILATOR

TOP_MODULE = tb_fuzzy_extractor
SIM_EXE = V$(TOP_MODULE)

TB_CPP = tb_fuzzy_extractor_main.cpp
TB_SV  = tb_fuzzy_extractor.sv

# Sim-only copy of the RTL with #TCQ intra-assignment delays stripped.
# TCQ is simulation-only delay (ignored by synthesis); stripping it keeps the
# Verilator run strictly edge-synchronous and avoids the delay machinery.
RTL_DIR = ../../rtl/fuzzy_extractor
SIM_RTL_DIR = rtl_tcq0
SIM_RTL_STAMP = $(SIM_RTL_DIR)/.stamp
SIM_RTL_INPUTS = $(wildcard $(RTL_DIR)/*.v $(RTL_DIR)/*.vh $(RTL_DIR)/*.sv)

RTL_SRCS = $(SIM_RTL_DIR)/bch_blank_ecc.v \
           $(SIM_RTL_DIR)/bch_chien.v \
           $(SIM_RTL_DIR)/bch_encode.v \
           $(SIM_RTL_DIR)/bch_error_tmec.v \
           $(SIM_RTL_DIR)/bch_math.v \
           $(SIM_RTL_DIR)/bch_sigma_bma_serial.v \
           $(SIM_RTL_DIR)/bch_syndrome.v \
           $(SIM_RTL_DIR)/bch_syndrome_method1.v \
           $(SIM_RTL_DIR)/bch_syndrome_method2.v \
           $(SIM_RTL_DIR)/buff.v \
           $(SIM_RTL_DIR)/compare_cla.v \
           $(SIM_RTL_DIR)/fifo.v \
           $(SIM_RTL_DIR)/matrix.v \
           $(SIM_RTL_DIR)/util.v \
           $(SIM_RTL_DIR)/xilinx_decoder.v \
           $(SIM_RTL_DIR)/xilinx_encode.v \
           $(SIM_RTL_DIR)/fuzzy_extractor.sv \
           xilinx_carry4_stub.v

all: sim

$(SIM_RTL_STAMP): $(SIM_RTL_INPUTS)
	rm -rf $(SIM_RTL_DIR)
	mkdir -p $(SIM_RTL_DIR)
	cp $(RTL_DIR)/*.v $(RTL_DIR)/*.vh $(RTL_DIR)/*.sv $(SIM_RTL_DIR)/
	sed -i 's/#TCQ //g' $(SIM_RTL_DIR)/*.v
	sed -i '/^\s*localparam TCQ = 1;\s*$$/d' $(SIM_RTL_DIR)/*.v
	sed -i 's/TCQ = 1;/TCQ = 0;/' $(SIM_RTL_DIR)/*.v
	touch $(SIM_RTL_STAMP)

$(RTL_SRCS): $(SIM_RTL_STAMP) ;

$(SIM_EXE): $(TB_SV) $(RTL_SRCS) $(TB_CPP) $(SIM_RTL_STAMP)
	$(VERILATOR) $(VERILATOR_FLAGS) --top-module $(TOP_MODULE) $(RTL_SRCS) $(TB_SV) $(TB_CPP)
	$(MAKE) -C obj_dir -f V$(TOP_MODULE).mk V$(TOP_MODULE)

$(TB_CPP):
	@echo '#include "V$(TOP_MODULE).h"' > $@
	@echo '#include "verilated.h"' >> $@
	@echo '' >> $@
	@echo 'int main(int argc, char** argv) {' >> $@
	@echo '    Verilated::debug(0);' >> $@
	@echo '    const std::unique_ptr<VerilatedContext> contextp{new VerilatedContext};' >> $@
	@echo '    contextp->threads(1);' >> $@
	@echo '    contextp->commandArgs(argc, argv);' >> $@
	@echo '    const std::unique_ptr<V$(TOP_MODULE)> topp{new V$(TOP_MODULE){contextp.get(), ""}};' >> $@
	@echo '    while (VL_LIKELY(!contextp->gotFinish())) {' >> $@
	@echo '        topp->eval();' >> $@
	@echo '        if (!topp->eventsPending()) break;' >> $@
	@echo '        contextp->time(topp->nextTimeSlot());' >> $@
	@echo '    }' >> $@
	@echo '    topp->final();' >> $@
	@echo '    contextp->statsPrintSummary();' >> $@
	@echo '    return 0;' >> $@
	@echo '}' >> $@

sim: $(SIM_EXE)
	@echo "Running simulation..."
	@./obj_dir/$(SIM_EXE)

clean:
	rm -rf obj_dir $(SIM_RTL_DIR) *.vcd $(TB_CPP)

.PHONY: all sim clean
