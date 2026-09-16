VERILATOR ?= verilator
TOP := puf_allpairs_uart
OBJ := obj_dir_16

.PHONY: sim clean

sim:
	$(VERILATOR) --cc --exe --build -j 1 --threads 1 \
		--top-module $(TOP) --Mdir $(OBJ) -GCLKS_PER_BIT=16 \
		-Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
		-CFLAGS "-std=c++17 -O2 -DTEST_CLKS_PER_BIT=16" \
		../../rtl/top/puf_allpairs_uart.sv \
		../../rtl/puf/uart_rx.v ../../rtl/puf/uart_tx.v \
		uart_allpairs_test.cpp
	./$(OBJ)/V$(TOP)

clean:
	rm -rf obj_dir_*
