.PHONY: check negative clean

check:
	verilator --binary --timing -j 1 --Mdir obj_dir \
		--top-module tb_edge_uart_transport -Wall -Wno-fatal \
		-Wno-DECLFILENAME -Wno-TIMESCALEMOD -Wno-WIDTHTRUNC \
		-Wno-WIDTHEXPAND -Wno-PROCASSINIT \
		-I../../rtl/top -I.. \
		../../rtl/puf/uart_rx.v ../../rtl/puf/uart_tx.v \
		../../rtl/top/helper_record.sv \
		../../rtl/top/edge_uart_transport.sv tb_edge_uart_transport.sv
	./obj_dir/Vtb_edge_uart_transport

negative:
	verilator --binary --timing -j 1 --Mdir obj_dir_neg \
		--top-module tb_edge_uart_negative -Wall -Wno-fatal \
		-Wno-DECLFILENAME -Wno-TIMESCALEMOD -Wno-WIDTHTRUNC \
		-Wno-WIDTHEXPAND -Wno-PROCASSINIT -Wno-UNUSEDSIGNAL \
		-I../../rtl/top -I.. \
		../../rtl/puf/uart_rx.v ../../rtl/puf/uart_tx.v \
		../../rtl/top/helper_record.sv \
		../../rtl/top/edge_uart_transport.sv tb_edge_uart_negative.sv
	./obj_dir_neg/Vtb_edge_uart_negative

clean:
	rm -rf obj_dir obj_dir_neg
