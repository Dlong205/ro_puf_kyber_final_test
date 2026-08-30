VIVADO ?= vivado
XPR := build/vivado/kyber_ro_puf_zynq7020.xpr

.PHONY: check firmware ro-puf fuzzy kdf kyber axi kyber-strict kyber-long kyber-codec system regression vivado-project synth impl program release-check package-internal clean

check:
	@./scripts/check_standalone.sh

firmware:
	$(MAKE) -C firmware

ro-puf:
	$(MAKE) -C sim/ro_puf sim

fuzzy:
	$(MAKE) -C sim/fuzzy_extractor sim

kdf:
	$(MAKE) -C sim/kdf_kat run

kyber:
	$(MAKE) -C sim/kyber kat

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

regression: ro-puf fuzzy kdf kyber axi kyber-strict kyber-codec system check

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
	$(MAKE) -C sim/kdf_kat clean
	$(MAKE) -C sim/kyber clean
	$(MAKE) -C sim/system clean
