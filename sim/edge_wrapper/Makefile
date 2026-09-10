.PHONY: all clean

all:
	verilator --binary --timing -j 1 --Mdir obj_dir \
		--top-module tb_edge_puf_mlkem_handoff -Wall -Wno-fatal \
		-Wno-DECLFILENAME -Wno-TIMESCALEMOD -Wno-UNUSEDSIGNAL \
		-Wno-PINCONNECTEMPTY -Wno-PROCASSINIT -Wno-SYNCASYNCNET \
		../../rtl/top/edge_puf_mlkem_core.sv tb_edge_puf_mlkem_handoff.sv
	./obj_dir/Vtb_edge_puf_mlkem_handoff

clean:
	rm -rf obj_dir
