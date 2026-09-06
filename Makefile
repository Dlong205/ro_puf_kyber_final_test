VIVADO ?= vivado
PUF_CHAR_XPR := build/puf_characterization/puf_characterization_zynq7020.xpr
SOC_REPRO_RUN ?= locked_a
SOC_REPRO_A ?= locked_a
SOC_REPRO_B ?= locked_b
SOC_REPRO_BIT := build/soc_repro/$(SOC_REPRO_RUN)/kyber_ro_puf_$(SOC_REPRO_RUN).runs/impl_1/Kyber_System_Top.bit

# This repository is intentionally serialized: two concurrent Vivado or
# Verilator builds can exhaust RAM on the reference development host.
.NOTPARALLEL:

.PHONY: check firmware ro-puf fuzzy fuzzy-portable puf-stability-proxy puf-characterization-project puf-characterization-bitstream puf-characterization-program puf-raw-characterize puf-characterization-sim fuzzy-characterization puf-metrics-test fips202 kdf mlkem kyber kyber-invalid axi kyber-strict kyber-long kyber-codec system regression ntt-multiplier xilinx-ro-lint asic-elaboration asic-portability crypto-freeze-check crypto-freeze-gate ro-lock-export ro-lock-source-check soc-repro-project soc-repro-build ro-route-repro-check vivado-project synth impl program program-bit soc-repro-program release-check package-internal clean

PUF_PORT ?= /dev/serial/by-id/usb-1a86_USB_Serial-if00-port0
PUF_SAMPLES ?= 1000
PUF_CHAR_BIT := build/puf_characterization/puf_characterization_zynq7020.runs/impl_1/Puf_Characterization_Top.bit

check:
	@./scripts/check_standalone.sh

firmware:
	$(MAKE) -C firmware

ro-puf:
	$(MAKE) -C sim/ro_puf sim

fuzzy:
	$(MAKE) -C sim/fuzzy_extractor sim

fuzzy-portable:
	$(MAKE) -C sim/fuzzy_extractor portable

# Release-mode proxy only: helper variation is not raw-response Hamming distance.
puf-stability-proxy:
	python3 -u host/puf_stability_proxy.py --port $(PUF_PORT) --count $(PUF_SAMPLES)

# Characterization uses a separate, PUF-only bitstream. It never overwrites
# the checked-in release bitstream or the full-system Vivado project.
puf-characterization-project:
	$(VIVADO) -mode batch -nolog -nojournal -source scripts/create_puf_characterization_project.tcl

puf-characterization-bitstream:
	@test -f $(PUF_CHAR_XPR) || $(MAKE) -j1 puf-characterization-project VIVADO=$(VIVADO)
	$(VIVADO) -mode batch -nolog -nojournal -source scripts/build_puf_characterization.tcl

puf-characterization-program:
	$(VIVADO) -mode batch -nolog -nojournal -source scripts/program_puf_characterization.tcl

puf-raw-characterize:
	python3 -u host/puf_raw_characterize.py --port "$(PUF_PORT)" --count $(PUF_SAMPLES) --bitstream "$(PUF_CHAR_BIT)"

puf-characterization-sim:
	$(MAKE) -j1 -C sim/puf_characterization sim

fuzzy-characterization:
	$(MAKE) -j1 -C sim/fuzzy_extractor characterization

puf-metrics-test:
	python3 -m unittest discover -s host/tests -v

fips202:
	$(MAKE) -C sim/fips202 run

kdf:
	$(MAKE) -C sim/kdf_kat run

mlkem:
	$(MAKE) -C sim/mlkem -j1 all

kyber:
	$(MAKE) -C sim/kyber kat

kyber-invalid:
	$(MAKE) -C sim/kyber kat-invalid

axi:
	$(MAKE) -C sim/kyber axi

kyber-strict:
	$(MAKE) -C sim/kyber strict-raw

kyber-long:
	$(MAKE) -C sim/kyber strict-raw-long

kyber-codec:
	$(MAKE) -C sim/kyber codec

system: firmware
	$(MAKE) -C sim/system sim

ntt-multiplier:
	$(MAKE) -C sim/portability multiplier

xilinx-ro-lint:
	$(MAKE) -C sim/portability xilinx-ro-lint

asic-elaboration:
	@./scripts/check_asic_portability.sh

asic-portability: ro-puf fuzzy-portable ntt-multiplier xilinx-ro-lint asic-elaboration

crypto-freeze-check:
	@./scripts/check_crypto_freeze.sh

# Force the complete candidate gate to run serially even if the caller uses -j.
crypto-freeze-gate:
	$(MAKE) -j1 regression
	$(MAKE) -j1 kyber-long
	$(MAKE) -j1 asic-portability
	$(MAKE) -j1 crypto-freeze-check

regression: ro-puf fuzzy fips202 kdf mlkem kyber kyber-invalid axi kyber-strict kyber-codec system check

vivado-project:
	$(VIVADO) -mode batch -nolog -nojournal -source scripts/create_project.tcl

# Both FPGA targets intentionally use one Vivado worker to protect low-memory hosts.
synth: vivado-project
	$(VIVADO) -mode batch -nolog -nojournal -source scripts/build_fpga.tcl -tclargs synth

impl: vivado-project
	$(VIVADO) -mode batch -nolog -nojournal -source scripts/build_fpga.tcl -tclargs impl

# The exporter is hash-gated to the accepted RC1 DCP/bitstream and refuses an
# unapproved baseline. Repro builds live under build/soc_repro and never
# overwrite the standard project or the checked-in release bitstream.
ro-lock-export:
	$(VIVADO) -mode batch -nolog -nojournal -source scripts/export_ro_physical_lock.tcl

ro-lock-source-check:
	$(VIVADO) -mode batch -nolog -nojournal -source scripts/validate_ro_lock_checkpoint.tcl

soc-repro-project:
	$(VIVADO) -mode batch -nolog -nojournal -source scripts/create_soc_repro_project.tcl -tclargs $(SOC_REPRO_RUN)

soc-repro-build: soc-repro-project
	$(VIVADO) -mode batch -nolog -nojournal -source scripts/build_soc_repro.tcl -tclargs $(SOC_REPRO_RUN)

ro-route-repro-check:
	@./scripts/check_ro_route_repro.sh $(SOC_REPRO_A) $(SOC_REPRO_B)

program:
	$(VIVADO) -mode batch -nolog -nojournal -source scripts/program_board.tcl

program-bit:
	@test -n "$(BITSTREAM)" || { echo "ERROR: set BITSTREAM=/absolute/path/to/file.bit" >&2; exit 2; }
	$(VIVADO) -mode batch -nolog -nojournal -source scripts/program_board.tcl -tclargs "$(BITSTREAM)"

soc-repro-program:
	@test -s "$(SOC_REPRO_BIT)" || { echo "ERROR: reproducibility bitstream not found: $(SOC_REPRO_BIT)" >&2; exit 2; }
	$(MAKE) program-bit BITSTREAM="$(abspath $(SOC_REPRO_BIT))" VIVADO=$(VIVADO)

release-check:
	@./scripts/release_check.sh

package-internal:
	@./scripts/package_release.sh --internal

clean:
	$(MAKE) -C sim/puf_characterization clean
	$(MAKE) -C sim/ro_puf clean
	$(MAKE) -C sim/fuzzy_extractor clean
	$(MAKE) -C sim/fips202 clean
	$(MAKE) -C sim/kdf_kat clean
	$(MAKE) -C sim/mlkem clean
	$(MAKE) -C sim/kyber clean
	$(MAKE) -C sim/system clean
	$(MAKE) -C sim/portability clean
