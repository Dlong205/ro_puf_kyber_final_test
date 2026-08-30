# Makefile for Kyber-512 KAT Verification (Verilator)
# Usage: make kat
#        make clean

VERILATOR = verilator
VERILATOR_FLAGS = --cc --exe --trace --timing \
    -CFLAGS "-std=c++17 -O2" \
    -LDFLAGS "-lstdc++" \
    -I../../rtl/kyber/ref \
    -I../../rtl/common \
    -I../../rtl/hash_core \
    -Wno-WIDTH -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL \
    -Wno-CASEINCOMPLETE -Wno-MULTITOP -Wno-MULTIDRIVEN \
    -Wno-UNSIGNED -Wno-EOFNEWLINE -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND \
    -Wno-MODDUP -Wno-TIMESCALEMOD -Wno-BLKANDNBLK -Wno-IMPLICIT -Wno-IMPLICITSTATIC -Wno-CASEOVERLAP -Wno-CASEX -Wno-fatal

TOP_MODULE = kat_wrapper
SIM_EXE = V$(TOP_MODULE)
AXI_TOP = axi_wrapper_tb
AXI_EXE = V$(AXI_TOP)

COMMON_SRCS = ../../rtl/common/generic_blk_mem_wrapper.sv \
              ../../rtl/common/generic_c_shift_ram_wrapper.sv \
              ../../rtl/common/generic_dist_mem_wrapper.sv \
              ../../rtl/common/generic_bram.sv \
              ../../rtl/common/generic_mult.sv \
              ../../rtl/common/generic_fifo.sv

HASH_CORE_SRCS = ../../rtl/hash_core/ALGORITHM.v \
                 ../../rtl/hash_core/THETA1.v \
                 ../../rtl/hash_core/THETA2_RHO_PI.v \
                 ../../rtl/hash_core/CHI1.v \
                 ../../rtl/hash_core/CHI2.v \
                 ../../rtl/hash_core/Chi_3_Iota.v \
                 ../../rtl/hash_core/IOTA.v \
                 ../../rtl/hash_core/RC.v \
                 ../../rtl/hash_core/ADDER.v

KYBER_SRCS = ../../rtl/kyber/ref/Kyber_Server.v \
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
             ../../rtl/kyber/ref/fifo_wrappers.v \
             ../../rtl/kyber/ref/LUT.v \
             ../../rtl/kyber/ref/mux4to2.v \
             ../../rtl/kyber/ref/pattern.v \
             ../../rtl/kyber/ref/reduc.v

TB_SRCS = tb_kyber_kat_main.cpp kat_wrapper.sv

obj_dir/$(SIM_EXE): $(COMMON_SRCS) $(HASH_CORE_SRCS) $(KYBER_SRCS) $(TB_SRCS)
	$(VERILATOR) $(VERILATOR_FLAGS) --top-module $(TOP_MODULE) $(COMMON_SRCS) $(HASH_CORE_SRCS) $(KYBER_SRCS) $(TB_SRCS)
	$(MAKE) -C obj_dir -f V$(TOP_MODULE).mk V$(TOP_MODULE)

kat: obj_dir/$(SIM_EXE)
	@echo "=== Running Kyber-512 Full KAT Verification ==="
	@obj_dir/$(SIM_EXE)

obj_dir_axi/$(AXI_EXE): $(COMMON_SRCS) $(HASH_CORE_SRCS) $(KYBER_SRCS) ../../rtl/kyber/kyber_axi_wrapper.v tb_axi_main.cpp axi_wrapper_tb.sv
	$(VERILATOR) $(VERILATOR_FLAGS) --Mdir obj_dir_axi --top-module $(AXI_TOP) $(COMMON_SRCS) $(HASH_CORE_SRCS) $(KYBER_SRCS) ../../rtl/kyber/kyber_axi_wrapper.v tb_axi_main.cpp axi_wrapper_tb.sv
	$(MAKE) -C obj_dir_axi -f V$(AXI_TOP).mk V$(AXI_TOP)

axi: obj_dir_axi/$(AXI_EXE)
	@echo "=== Running Kyber-512 AXI register/handshake verification ==="
	@obj_dir_axi/$(AXI_EXE)

clean:
	rm -rf obj_dir obj_dir_axi
	rm -f waveform.vcd

.PHONY: kat axi clean
