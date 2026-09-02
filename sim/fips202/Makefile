VERILATOR ?= verilator
TOP_MODULE := fips202_sponge

VERILATOR_FLAGS := --cc --exe --timing \
	-CFLAGS "-std=c++17 -O2" \
	-Wall -Wno-fatal -Wno-DECLFILENAME -Wno-EOFNEWLINE \
	-Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-WIDTH \
	-I../../rtl/hash_core

HASH_CORE_SRCS := ../../rtl/hash_core/ALGORITHM.v \
	../../rtl/hash_core/THETA1.v \
	../../rtl/hash_core/THETA2_RHO_PI.v \
	../../rtl/hash_core/CHI1.v \
	../../rtl/hash_core/CHI2.v \
	../../rtl/hash_core/Chi_3_Iota.v \
	../../rtl/hash_core/IOTA.v \
	../../rtl/hash_core/RC.v \
	../../rtl/hash_core/ADDER.v

SRCS := ../../rtl/hash_core/fips202_sponge.sv $(HASH_CORE_SRCS)
HARNESS := fips202_main.cpp
VECTORS := fips202_vectors.txt
NIST_VECTORS := nist_cavp_vectors.txt

.PHONY: all vectors nist-cavp-vectors build run clean

all: run

vectors: $(VECTORS)

$(VECTORS): generate_vectors.py
	python3 generate_vectors.py --output $(VECTORS)

# Explicit regeneration target; pass paths to the two official NIST archives.
nist-cavp-vectors:
	@test -n "$(SHA3_ZIP)" -a -n "$(SHAKE_ZIP)" || \
		(echo "usage: make nist-cavp-vectors SHA3_ZIP=... SHAKE_ZIP=..." >&2; exit 2)
	python3 import_nist_cavp.py --sha3-zip "$(SHA3_ZIP)" \
		--shake-zip "$(SHAKE_ZIP)" --output $(NIST_VECTORS)

build: obj_dir/V$(TOP_MODULE)

obj_dir/V$(TOP_MODULE): $(SRCS) $(HARNESS) $(VECTORS) $(NIST_VECTORS)
	$(VERILATOR) $(VERILATOR_FLAGS) --top-module $(TOP_MODULE) \
		$(SRCS) $(HARNESS)
	$(MAKE) -C obj_dir -f V$(TOP_MODULE).mk -j1 V$(TOP_MODULE)

run: build
	./obj_dir/V$(TOP_MODULE) $(VECTORS) $(NIST_VECTORS)

clean:
	rm -rf obj_dir
