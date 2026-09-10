VERILATOR ?= verilator
TOP := tb_edge_seed_controller
MDIR := obj_dir
EXE := $(MDIR)/V$(TOP)

HASH := ../../rtl/kyber/ref/keccak_f1600_server.v \
        ../../rtl/hash_core/ALGORITHM.v ../../rtl/hash_core/THETA1.v \
        ../../rtl/hash_core/THETA2_RHO_PI.v ../../rtl/hash_core/CHI1.v \
        ../../rtl/hash_core/CHI2.v ../../rtl/hash_core/Chi_3_Iota.v \
        ../../rtl/hash_core/IOTA.v ../../rtl/hash_core/RC.v \
        ../../rtl/hash_core/ADDER.v
RTL := ../../rtl/top/kdf_keccak_compact.sv ../../rtl/top/edge_seed_controller.sv

$(EXE): $(RTL) tb_edge_seed_controller.sv
	$(VERILATOR) --binary --timing -j 1 --Mdir $(MDIR) --top-module $(TOP) \
		-I../../rtl/hash_core -I../../rtl/kyber/ref \
		-Wall -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL \
		-Wno-UNUSEDPARAM -Wno-TIMESCALEMOD -Wno-WIDTHTRUNC \
		$(RTL) tb_edge_seed_controller.sv

run: $(EXE)
	@$(EXE)

check: compact-kat run scrub plane

clean:
	rm -rf $(MDIR) obj_dir_kat obj_dir_scrub obj_dir_plane

scrub:
	$(VERILATOR) --binary --timing -j 1 --Mdir obj_dir_scrub \
		--top-module tb_edge_kem_scrub_controller -Wall -Wno-fatal \
		-Wno-DECLFILENAME -Wno-TIMESCALEMOD -Wno-WIDTHTRUNC \
		../../rtl/top/edge_kem_scrub_controller.sv \
		tb_edge_kem_scrub_controller.sv
	@obj_dir_scrub/Vtb_edge_kem_scrub_controller

plane:
	$(VERILATOR) --binary --timing -j 1 --Mdir obj_dir_plane \
		--top-module tb_edge_control_plane -I../../rtl/hash_core \
		-I../../rtl/kyber/ref -Wall -Wno-fatal -Wno-DECLFILENAME \
		-Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-TIMESCALEMOD \
		-Wno-WIDTHTRUNC $(RTL) ../../rtl/top/edge_kem_scrub_controller.sv \
		../../rtl/top/edge_control_plane.sv tb_edge_control_plane.sv
	@obj_dir_plane/Vtb_edge_control_plane

compact-kat:
	$(VERILATOR) --binary --timing -j 1 --Mdir obj_dir_kat \
		--top-module tb_kdf_compact -Wall -Wno-fatal \
		-Wno-DECLFILENAME -Wno-TIMESCALEMOD -Wno-WIDTHTRUNC \
		../../rtl/top/kdf_keccak_compact.sv tb_kdf_compact.sv
	@obj_dir_kat/Vtb_kdf_compact

.PHONY: check compact-kat run scrub plane clean
