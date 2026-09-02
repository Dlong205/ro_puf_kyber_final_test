VERILATOR = verilator
TOP = Kyber_System_Top
SIM_EXE = V$(TOP)

FLAGS = --cc --exe --timing --top-module $(TOP) --Mdir obj_dir \
        -CFLAGS "-std=c++17 -O2" -LDFLAGS "-lstdc++" \
        -I../../rtl/kyber/ref -I../../rtl/common -I../../rtl/hash_core \
        -I../fuzzy_extractor/rtl_tcq0 \
        -I../../rtl/puf \
        -Wno-WIDTH -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL \
        -Wno-CASEINCOMPLETE -Wno-MULTITOP -Wno-MULTIDRIVEN \
        -Wno-UNSIGNED -Wno-EOFNEWLINE -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND \
        -Wno-MODDUP -Wno-TIMESCALEMOD -Wno-BLKANDNBLK -Wno-IMPLICIT \
        -Wno-IMPLICITSTATIC -Wno-CASEOVERLAP -Wno-CASEX -Wno-fatal \
        -DKP_RO_BEHAVIORAL

COMMON_SRCS = ../../rtl/common/generic_blk_mem_wrapper.sv \
              ../../rtl/common/generic_c_shift_ram_wrapper.sv \
              ../../rtl/common/generic_dist_mem_wrapper.sv \
              ../../rtl/common/generic_bram.sv \
              ../../rtl/common/generic_mult.sv \
              ../../rtl/common/generic_fifo.sv

HASH_SRCS = ../../rtl/hash_core/fips202_sponge.sv \
            ../../rtl/hash_core/ALGORITHM.v \
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
             ../../rtl/kyber/ref/reduc.v \
             ../../rtl/kyber/kyber_axi_wrapper.v

FE_DIR = ../fuzzy_extractor/rtl_tcq0
FE_STAMP = $(FE_DIR)/.stamp
FE_SRCS = $(FE_DIR)/bch_blank_ecc.v \
          $(FE_DIR)/bch_chien.v \
          $(FE_DIR)/bch_encode.v \
          $(FE_DIR)/bch_error_tmec.v \
          $(FE_DIR)/bch_math.v \
          $(FE_DIR)/bch_sigma_bma_serial.v \
          $(FE_DIR)/bch_syndrome.v \
          $(FE_DIR)/bch_syndrome_method1.v \
          $(FE_DIR)/bch_syndrome_method2.v \
          $(FE_DIR)/buff.v \
          $(FE_DIR)/compare_cla.v \
          $(FE_DIR)/compare_cla_xilinx.v \
          $(FE_DIR)/fifo.v \
          $(FE_DIR)/matrix.v \
          $(FE_DIR)/util.v \
          $(FE_DIR)/xilinx_decoder.v \
          $(FE_DIR)/xilinx_encode.v \
          $(FE_DIR)/fuzzy_extractor.sv \
          ../fuzzy_extractor/xilinx_carry4_stub.v

PUF_SRCS = ../../rtl/puf/kp_ro_cell.sv \
           ../../rtl/puf/kp_ro_cell_model.sv \
           ../../rtl/puf/kp_puf_cells.sv \
           ../../rtl/puf/kp_puf_control.sv \
           ../../rtl/puf/kp_puf_top.sv \
           ../../rtl/puf/uart_rx.v \
           ../../rtl/puf/uart_tx.v

SOC_SRCS = ../../rtl/soc/picorv32.v \
           ../../rtl/soc/soc_bram.v \
           ../../rtl/soc/soc_peripherals.sv \
           ../../rtl/soc/riscv_soc.sv \
           ../../rtl/top/kdf_keccak.sv \
           ../../rtl/top/Kyber_System_Top.sv

ALL_SRCS = $(COMMON_SRCS) $(HASH_SRCS) $(KYBER_SRCS) $(FE_SRCS) $(PUF_SRCS) $(SOC_SRCS)

$(FE_STAMP):
	$(MAKE) -C ../fuzzy_extractor rtl_tcq0/.stamp

$(FE_SRCS): $(FE_STAMP) ;

obj_dir/$(SIM_EXE): $(ALL_SRCS) system_uart_main.cpp $(FE_STAMP)
	$(VERILATOR) $(FLAGS) $(ALL_SRCS) system_uart_main.cpp
	$(MAKE) -C obj_dir -f V$(TOP).mk V$(TOP)

sim: obj_dir/$(SIM_EXE) ../../firmware/firmware.hex
	@echo "=== Running firmware/UART RO-PUF -> FE -> KDF -> Kyber-512 ==="
	@cd ../../firmware && ../sim/system/obj_dir/$(SIM_EXE)

clean:
	rm -rf obj_dir

.PHONY: sim clean
