VERILATOR ?= verilator
TOP := mlkem_keygen_probe
OBJ := obj_dir
ENCAP_TOP := mlkem_encap_probe
ENCAP_OBJ := obj_dir_encap
DECAP_TOP := mlkem_decap_probe
DECAP_OBJ := obj_dir_decap

DEBUG_FLAGS ?=
FLAGS := --cc --exe --timing $(DEBUG_FLAGS) -CFLAGS "-std=c++17 -O2" \
	-I../../rtl/kyber/ref -I../../rtl/common -I../../rtl/hash_core \
	-Wno-WIDTH -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL -Wno-CASEINCOMPLETE \
	-Wno-MULTITOP -Wno-MULTIDRIVEN -Wno-UNSIGNED -Wno-EOFNEWLINE \
	-Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-MODDUP -Wno-TIMESCALEMOD \
	-Wno-BLKANDNBLK -Wno-IMPLICIT -Wno-IMPLICITSTATIC -Wno-CASEOVERLAP \
	-Wno-CASEX -Wno-fatal

COMMON := ../../rtl/common/generic_blk_mem_wrapper.sv \
	../../rtl/common/generic_c_shift_ram_wrapper.sv \
	../../rtl/common/generic_dist_mem_wrapper.sv \
	../../rtl/common/generic_bram.sv ../../rtl/common/generic_mult.sv \
	../../rtl/common/generic_fifo.sv

HASH := ../../rtl/hash_core/ALGORITHM.v ../../rtl/hash_core/THETA1.v \
	../../rtl/hash_core/THETA2_RHO_PI.v ../../rtl/hash_core/CHI1.v \
	../../rtl/hash_core/CHI2.v ../../rtl/hash_core/Chi_3_Iota.v \
	../../rtl/hash_core/IOTA.v ../../rtl/hash_core/RC.v \
	../../rtl/hash_core/ADDER.v

KYBER := ../../rtl/kyber/ref/Kyber_Server.v \
	../../rtl/kyber/ref/Kyber_Client.v \
	../../rtl/kyber/ref/NTT_core_Server.v \
	../../rtl/kyber/ref/NTT_core_Client.v \
	../../rtl/kyber/ref/butterfly_Server.v \
	../../rtl/kyber/ref/butterfly_Client.v \
	../../rtl/kyber/ref/hash_core_Server.v \
	../../rtl/kyber/ref/hash_core_Client.v \
	../../rtl/kyber/ref/sha3_shake_core.v \
	../../rtl/kyber/ref/keccak_f1600_server.v \
	../../rtl/kyber/ref/keccak_f1600_client.v \
	../../rtl/kyber/ref/encode_Server.v \
	../../rtl/kyber/ref/encode_Client.v \
	../../rtl/kyber/ref/decode_Server.v \
	../../rtl/kyber/ref/decode_Client.v \
	../../rtl/kyber/ref/decode_keccak.v \
	../../rtl/kyber/ref/fifo_wrappers.v ../../rtl/kyber/ref/LUT.v \
	../../rtl/kyber/ref/mux4to2.v ../../rtl/kyber/ref/pattern.v \
	../../rtl/kyber/ref/reduc.v

$(OBJ)/V$(TOP): $(COMMON) $(HASH) $(KYBER) $(TOP).sv mlkem_keygen_main.cpp
	$(VERILATOR) $(FLAGS) --Mdir $(OBJ) --top-module $(TOP) \
		$(COMMON) $(HASH) $(KYBER) mlkem_keygen_main.cpp $(TOP).sv
	$(MAKE) -C $(OBJ) -f V$(TOP).mk V$(TOP)

keygen: $(OBJ)/V$(TOP) mlkem512_keygen_acvp.txt
	@$(OBJ)/V$(TOP)

$(ENCAP_OBJ)/V$(ENCAP_TOP): $(COMMON) $(HASH) $(KYBER) $(ENCAP_TOP).sv mlkem_encap_main.cpp
	$(VERILATOR) $(FLAGS) --Mdir $(ENCAP_OBJ) --top-module $(ENCAP_TOP) \
		$(COMMON) $(HASH) $(KYBER) mlkem_encap_main.cpp $(ENCAP_TOP).sv
	$(MAKE) -C $(ENCAP_OBJ) -f V$(ENCAP_TOP).mk V$(ENCAP_TOP)

encap: $(ENCAP_OBJ)/V$(ENCAP_TOP) mlkem512_encap_acvp.txt
	@$(ENCAP_OBJ)/V$(ENCAP_TOP)

$(DECAP_OBJ)/V$(DECAP_TOP): $(COMMON) $(HASH) $(KYBER) $(DECAP_TOP).sv mlkem_decap_main.cpp
	$(VERILATOR) $(FLAGS) --Mdir $(DECAP_OBJ) --top-module $(DECAP_TOP) \
		$(COMMON) $(HASH) $(KYBER) mlkem_decap_main.cpp $(DECAP_TOP).sv
	$(MAKE) -C $(DECAP_OBJ) -f V$(DECAP_TOP).mk V$(DECAP_TOP)

decap: $(DECAP_OBJ)/V$(DECAP_TOP) mlkem512_decap_ref.txt
	@$(DECAP_OBJ)/V$(DECAP_TOP)

all: keygen encap decap

clean:
	rm -rf $(OBJ) $(ENCAP_OBJ) $(DECAP_OBJ)

.PHONY: all keygen encap decap clean
