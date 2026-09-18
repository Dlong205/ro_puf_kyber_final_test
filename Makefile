VIVADO ?= vivado
PUF_CHAR_XPR := build/puf_characterization/puf_characterization_zynq7020.xpr
ARTY_PUF_XPR := build/arty_puf_characterization/puf_characterization_arty_a7_35t.xpr
SOC_REPRO_RUN ?= locked_a
SOC_REPRO_A ?= locked_a
SOC_REPRO_B ?= locked_b
SOC_REPRO_BIT := build/soc_repro/$(SOC_REPRO_RUN)/kyber_ro_puf_$(SOC_REPRO_RUN).runs/impl_1/Kyber_System_Top.bit

# This repository is intentionally serialized: two concurrent Vivado or
# Verilator builds can exhaust RAM on the reference development host.
.NOTPARALLEL:

.PHONY: check firmware ro-puf fuzzy fuzzy-portable puf-stability-proxy puf-characterization-project puf-characterization-bitstream puf-characterization-program puf-raw-characterize puf-margin-characterize puf-allpairs-sim puf-allpairs-project puf-allpairs-bitstream puf-allpairs-program puf-allpairs-characterize puf-mapping-train arty-puf-characterization-project arty-puf-characterization-bitstream arty-puf-characterization-program arty-puf-raw-characterize puf-characterization-sim fuzzy-characterization puf-metrics-test fips202 kdf mlkem edge-uart edge-uart-mlkem edge-root-binding edge-asic-top kyber kyber-invalid axi axi-secure kyber-strict kyber-long kyber-codec system regression ntt-multiplier xilinx-ro-lint asic-reset-smoke asic-filelist-check asic-manifest-check asic-frontend-check asic-backend-readiness asic-elaboration asic-portability crypto-freeze-check verification-inputs-check crypto-freeze-gate ro-lock-export ro-lock-source-check soc-repro-project soc-repro-build ro-route-repro-check vivado-project synth impl program program-bit soc-repro-program release-check package-internal clean

PUF_PORT ?= /dev/serial/by-id/usb-1a86_USB_Serial-if00-port0
ARTY_PUF_PORT ?= $(firstword $(wildcard /dev/serial/by-id/usb-Digilent_Digilent_USB_Device_*-if01-port0))
PUF_SAMPLES ?= 1000
PUF_MARGIN_REPORT ?= reports/puf_characterization/private_margin_latest.json
PUF_ALLPAIRS_REPORT ?= reports/puf_allpairs_characterization/private_allpairs_latest.json
PUF_BOARD_ID ?= UNSPECIFIED
PUF_CONDITION_ID ?= UNSPECIFIED
PUF_MAPPING_TRAINING ?=
PUF_MAPPING_HOLDOUT ?=
PUF_MAPPING_VERSION ?= provisional-v0
PUF_MAPPING_MANIFEST ?= reports/puf_mapping/provisional_mapping.json
PUF_CHAR_BIT := build/puf_characterization/puf_characterization_zynq7020.runs/impl_1/Puf_Characterization_Top.bit
PUF_ALLPAIRS_XPR := build/puf_allpairs_characterization/puf_allpairs_zynq7020.xpr
PUF_ALLPAIRS_BIT := build/puf_allpairs_characterization/puf_allpairs_zynq7020.runs/impl_1/Puf_AllPairs_Characterization_Top.bit
ARTY_PUF_BIT := build/arty_puf_characterization/puf_characterization_arty_a7_35t.runs/impl_1/Puf_Characterization_Top.bit

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

puf-margin-characterize:
	python3 -u host/puf_margin_characterize.py --port "$(PUF_PORT)" --count $(PUF_SAMPLES) --bitstream "$(PUF_CHAR_BIT)" --report "$(PUF_MARGIN_REPORT)"

# Protocol 2.0 diagnostic image: all C(32,2)=496 unordered RO pairs.
puf-allpairs-sim:
	$(MAKE) -j1 -C sim/puf_allpairs sim
	$(MAKE) -j1 -C sim/puf_allpairs_uart sim

puf-allpairs-project:
	$(VIVADO) -mode batch -nolog -nojournal -source scripts/create_puf_allpairs_project.tcl

puf-allpairs-bitstream:
	@test -f $(PUF_ALLPAIRS_XPR) || $(MAKE) -j1 puf-allpairs-project VIVADO=$(VIVADO)
	$(VIVADO) -mode batch -nolog -nojournal -source scripts/build_puf_allpairs.tcl

puf-allpairs-program:
	$(VIVADO) -mode batch -nolog -nojournal -source scripts/program_puf_allpairs.tcl

puf-allpairs-characterize:
	python3 -u host/puf_allpairs_characterize.py --port "$(PUF_PORT)" --count $(PUF_SAMPLES) --bitstream "$(PUF_ALLPAIRS_BIT)" --report "$(PUF_ALLPAIRS_REPORT)" --board-id "$(PUF_BOARD_ID)" --condition-id "$(PUF_CONDITION_ID)"

# Explicit training and holdout file lists are mandatory. This target writes a
# provisional manifest unless the default 3-training/2-holdout board gates pass.
puf-mapping-train:
	@test -n "$(PUF_MAPPING_TRAINING)" || { echo "Set PUF_MAPPING_TRAINING to private campaign JSON files" >&2; exit 2; }
	python3 -u host/puf_mapping_train.py --training $(PUF_MAPPING_TRAINING) --holdout $(PUF_MAPPING_HOLDOUT) --version "$(PUF_MAPPING_VERSION)" --manifest "$(PUF_MAPPING_MANIFEST)"

arty-puf-characterization-project:
	$(VIVADO) -mode batch -nolog -nojournal -source scripts/create_arty_puf_characterization_project.tcl

arty-puf-characterization-bitstream:
	@test -f $(ARTY_PUF_XPR) || $(MAKE) -j1 arty-puf-characterization-project VIVADO=$(VIVADO)
	$(VIVADO) -mode batch -nolog -nojournal -source scripts/build_arty_puf_characterization.tcl

arty-puf-characterization-program:
	$(VIVADO) -mode batch -nolog -nojournal -source scripts/program_arty_puf_characterization.tcl

arty-puf-raw-characterize:
	python3 -u host/puf_raw_characterize.py --port "$(ARTY_PUF_PORT)" --count $(PUF_SAMPLES) --bitstream "$(ARTY_PUF_BIT)" --target-part xc7a35ticsg324-1L

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

edge-uart:
	$(MAKE) -j1 -C sim/edge_uart clean check

edge-uart-mlkem:
	$(MAKE) -j1 -C sim/edge_uart_mlkem clean check

# Phase-1 same-root binding: shared helper-record spec, RTL parser, KCV
# verifier KAT and the fail-closed gate on the reconstruct path.
edge-root-binding:
	python3 scripts/helper_record_spec.py --check
	python3 scripts/helper_record_spec.py --selftest
	$(MAKE) -j1 -C sim/edge_wrapper clean record kcv gate phase1 loopback e2e
	$(MAKE) -j1 -C sim/edge_uart check negative

edge-asic-top:
	$(MAKE) -j1 -C sim/edge_wrapper asic-top

kyber:
	$(MAKE) -C sim/kyber kat

kyber-invalid:
	$(MAKE) -C sim/kyber kat-invalid

axi:
	$(MAKE) -C sim/kyber axi

axi-secure:
	$(MAKE) -C sim/kyber axi-secure

kyber-strict:
	$(MAKE) -C sim/kyber strict-raw

kyber-long:
	$(MAKE) -C sim/kyber strict-raw-long

kyber-codec:
	$(MAKE) -C sim/kyber codec

system:
	$(MAKE) -C firmware firmware_diag.hex
	$(MAKE) -C sim/system sim

ntt-multiplier:
	$(MAKE) -C sim/portability multiplier

xilinx-ro-lint:
	$(MAKE) -C sim/portability xilinx-ro-lint

asic-reset-smoke:
	$(MAKE) -C sim/asic_frontend reset-smoke

asic-filelist-check:
	@./scripts/check_asic_filelists.sh

asic-manifest-check:
	@./scripts/check_asic_manifest.sh

asic-frontend-check: asic-manifest-check
	@./scripts/check_asic_frontend.sh

asic-backend-readiness:
	@./scripts/check_asic_backend_readiness.sh

asic-elaboration:
	@./scripts/check_asic_portability.sh

asic-portability: ro-puf fuzzy-portable ntt-multiplier xilinx-ro-lint asic-reset-smoke asic-elaboration asic-frontend-check

crypto-freeze-check:
	@./scripts/check_crypto_freeze.sh

verification-inputs-check:
	@./scripts/check_verification_inputs.sh

# Force the complete candidate gate to run serially even if the caller uses -j.
crypto-freeze-gate:
	$(MAKE) -j1 verification-inputs-check
	$(MAKE) -j1 regression
	$(MAKE) -j1 kyber-long
	$(MAKE) -j1 asic-portability
	$(MAKE) -j1 crypto-freeze-check

regression: ro-puf fuzzy fips202 kdf mlkem kyber kyber-invalid axi axi-secure kyber-strict kyber-codec edge-root-binding system check

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
	$(MAKE) -C sim/asic_frontend clean
	$(MAKE) -C sim/puf_characterization clean
	$(MAKE) -C sim/ro_puf clean
	$(MAKE) -C sim/fuzzy_extractor clean
	$(MAKE) -C sim/fips202 clean
	$(MAKE) -C sim/kdf_kat clean
	$(MAKE) -C sim/mlkem clean
	$(MAKE) -C sim/kyber clean
	$(MAKE) -C sim/system clean
	$(MAKE) -C sim/portability clean
