.PHONY: check clean

check:
	verilator --binary --timing -j 1 --Mdir obj_dir \
		--top-module tb_edge_uart_transport -Wall -Wno-fatal \
		-Wno-DECLFILENAME -Wno-TIMESCALEMOD -Wno-WIDTHTRUNC \
		-Wno-WIDTHEXPAND -Wno-PROCASSINIT \
		../../rtl/puf/uart_rx.v ../../rtl/puf/uart_tx.v \
		../../rtl/top/edge_uart_transport.sv tb_edge_uart_transport.sv
	./obj_dir/Vtb_edge_uart_transport

clean:
	rm -rf obj_dir
