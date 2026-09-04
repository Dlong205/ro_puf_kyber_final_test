VIVADO ?= vivado
XPR := build/vivado/kyber_ro_puf_zynq7020.xpr

.PHONY: check firmware ro-puf fuzzy fuzzy-portable fips202 kdf mlkem kyber kyber-invalid axi kyber-strict kyber-long kyber-codec system regression ntt-multiplier xilinx-ro-lint asic-elaboration asic-portability crypto-freeze-check crypto-freeze-gate vivado-project synth impl program release-check package-internal clean

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
synth:
	@test -f $(XPR) || $(MAKE) vivado-project VIVADO=$(VIVADO)
	$(VIVADO) -mode batch -nolog -nojournal -source scripts/build_fpga.tcl -tclargs synth

impl:
	@test -f $(XPR) || $(MAKE) vivado-project VIVADO=$(VIVADO)
	$(VIVADO) -mode batch -nolog -nojournal -source scripts/build_fpga.tcl -tclargs impl

program:
	$(VIVADO) -mode batch -nolog -nojournal -source scripts/program_board.tcl

release-check:
	@./scripts/release_check.sh

package-internal:
	@./scripts/package_release.sh --internal

clean:
	$(MAKE) -C sim/ro_puf clean
	$(MAKE) -C sim/fuzzy_extractor clean
	$(MAKE) -C sim/fips202 clean
	$(MAKE) -C sim/kdf_kat clean
	$(MAKE) -C sim/mlkem clean
	$(MAKE) -C sim/kyber clean
	$(MAKE) -C sim/system clean
	$(MAKE) -C sim/portability clean
