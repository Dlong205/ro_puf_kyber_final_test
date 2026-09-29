VERILATOR ?= verilator

.PHONY: sim clean

sim:
	$(MAKE) -C ../../firmware supervisor
	$(VERILATOR) --binary --timing -j 1 --threads 1 \
		--top-module tb_puf64_picorv32_supervisor --Mdir obj_dir \
		-Wno-fatal -Wno-WIDTH -Wno-TIMESCALEMOD -Wno-UNUSEDSIGNAL \
		-Wno-PINCONNECTEMPTY -Wno-UNUSEDPARAM \
		../../rtl/soc/picorv32.v ../../rtl/soc/soc_bram.v \
		../../rtl/soc/puf64_picorv32_supervisor.sv \
		tb_puf64_picorv32_supervisor.sv
	./obj_dir/Vtb_puf64_picorv32_supervisor

clean:
	rm -rf obj_dir
