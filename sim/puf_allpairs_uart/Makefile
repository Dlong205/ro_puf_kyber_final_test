VERILATOR ?= verilator
TOP := puf_allpairs_uart
OBJ := obj_dir_16

.PHONY: sim sim64 clean

sim:
	$(VERILATOR) --cc --exe --build -j 1 --threads 1 \
		--top-module $(TOP) --Mdir $(OBJ) -GCLKS_PER_BIT=16 \
		-Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
		-CFLAGS "-std=c++17 -O2 -DTEST_CLKS_PER_BIT=16" \
		../../rtl/top/puf_allpairs_uart.sv \
		../../rtl/puf/uart_rx.v ../../rtl/puf/uart_tx.v \
		uart_allpairs_test.cpp
	./$(OBJ)/V$(TOP)

# PUF64 variant: equivalent endpoint at NUM_RO=64/PAIR_COUNT=2016 (protocol 3.0).
sim64:
	$(VERILATOR) --cc --exe --build -j 1 --threads 1 \
		--top-module $(TOP) --Mdir obj_dir_64 -GCLKS_PER_BIT=16 \
		-GNUM_RO=64 -GPAIR_COUNT=2016 -GRESPONSE_BITS=2016 \
		-Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD \
		-CFLAGS "-std=c++17 -O2 -DTEST_CLKS_PER_BIT=16" \
		../../rtl/top/puf_allpairs_uart.sv \
		../../rtl/puf/uart_rx.v ../../rtl/puf/uart_tx.v \
		uart_allpairs64_test.cpp
	./obj_dir_64/V$(TOP)

clean:
	rm -rf obj_dir_*
