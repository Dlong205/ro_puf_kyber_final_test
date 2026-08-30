# KDF SHAKE256 KAT Test — Verilator
VERILATOR = verilator
VERILATOR_FLAGS = --cc --exe --timing \
    -CFLAGS "-std=c++17 -O2" \
    -LDFLAGS "-lstdc++" \
    -I../../rtl/kyber/ref \
    -I../../rtl/common \
    -I../../rtl/hash_core \
    -I../../rtl/top \
    -Wno-WIDTH -Wno-UNUSEDPARAM -Wno-UNUSEDSIGNAL \
    -Wno-CASEINCOMPLETE -Wno-MULTITOP -Wno-MULTIDRIVEN \
    -Wno-UNSIGNED -Wno-EOFNEWLINE -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND \
    -Wno-MODDUP -Wno-TIMESCALEMOD -Wno-BLKANDNBLK -Wno-IMPLICIT -Wno-IMPLICITSTATIC \
    -Wno-CASEOVERLAP -Wno-CASEX -Wno-fatal

TOP_MODULE = tb_kdf_kat

HASH_CORE_SRCS = ../../rtl/hash_core/ALGORITHM.v \
                 ../../rtl/hash_core/THETA1.v \
                 ../../rtl/hash_core/THETA2_RHO_PI.v \
                 ../../rtl/hash_core/CHI1.v \
                 ../../rtl/hash_core/CHI2.v \
                 ../../rtl/hash_core/Chi_3_Iota.v \
                 ../../rtl/hash_core/IOTA.v \
                 ../../rtl/hash_core/RC.v \
                 ../../rtl/hash_core/ADDER.v

KDF_SRCS = ../../rtl/top/kdf_keccak.sv \
           ../../rtl/kyber/ref/keccak_f1600_server.v

TB_SRCS = tb_kdf_kat_main.cpp tb_kdf_kat.sv

all: build run

build: obj_dir/V$(TOP_MODULE)

obj_dir/V$(TOP_MODULE): $(HASH_CORE_SRCS) $(KDF_SRCS) $(TB_SRCS)
	$(VERILATOR) $(VERILATOR_FLAGS) --top-module $(TOP_MODULE) \
		$(HASH_CORE_SRCS) $(KDF_SRCS) $(TB_SRCS)
	$(MAKE) -C obj_dir -f V$(TOP_MODULE).mk V$(TOP_MODULE)

run: build
	./obj_dir/V$(TOP_MODULE)

clean:
	rm -rf obj_dir

.PHONY: all build run clean
