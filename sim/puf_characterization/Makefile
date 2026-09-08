VERILATOR ?= verilator
TOP := puf_characterization_uart
CLKS_PER_BIT ?= 16
OBJ := obj_dir_$(CLKS_PER_BIT)
RTL := ../../rtl/top/puf_characterization_uart.sv \
       ../../rtl/puf/uart_rx.v ../../rtl/puf/uart_tx.v

.PHONY: all sim clean
all: sim

$(OBJ)/V$(TOP): $(RTL) uart_protocol_test.cpp
	$(VERILATOR) --cc --exe --build -j 1 --threads 1 \
		--top-module $(TOP) --Mdir $(OBJ) -GCLKS_PER_BIT=$(CLKS_PER_BIT) \
		-Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
		-CFLAGS "-std=c++17 -O2 -DTEST_CLKS_PER_BIT=$(CLKS_PER_BIT)" $(RTL) uart_protocol_test.cpp

sim: $(OBJ)/V$(TOP)
	./$(OBJ)/V$(TOP)

clean:
	rm -rf obj_dir_*
