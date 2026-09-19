# PUF64 KCV trust-anchor audit (Phase I2.5)

Status: `ACTIVE_SUBSTITUTION_BLOCKER` (audit, Phase I2.5).  Resolved by the
T0-T8 trust-anchor fix; see "Resolution" below.  Evidence: `sim/edge_wrapper/tb_edge_kcv_substitution.sv`
(`make -C sim/edge_wrapper substitution`).

## 1. `kcv_ref` provenance per path

| Path | KCV generated | Stored | Writable by | Comparator input | Survives reset/power-cycle | Helper can replace ref | CRC the only guard |
|---|---|---|---|---|---|---|---|
| Diagnostic enrollment (`Edge_Arty_Diagnostic_Top.sv`, `Edge_Zynq_Diagnostic_100MHz_Top.sv`) | device computes `kcv_out` from FE key (`edge_puf_mlkem_core` `ST_KCV_GEN`) | emitted in record bytes 46..73 | host storage | n/a (no compare) | no | n/a | CRC only for transport |
| CPU-free Edge reconstruct | device computes `kcv_out` | none | anyone sending the helper record | `edge_uart_transport:414 core_kcv_ref <= rec_kcv` → `edge_puf_mlkem_core:105` → `edge_root_binding` | cleared at reset/zeroize (`:257,:306,:625`) | **yes** | **yes** |
| PicoRV32 / SoC (`Kyber_System_Top.sv`) | device `kcv_out` via `soc_peripherals` KCV engine | `kcv_ref_reg[0:6]` MMIO `0x100000A0..B8` | CPU/firmware write (`:238`); reads return `kcv_out` (`:262`, oracle) | engine `kcv_ref` | cleared on reset/zeroize (`:211`) | **yes (firmware + MMIO)** | CRC only for transport |
| Firmware (`firmware/main.c`) | n/a | record bytes | firmware | `kcv_write_ref(&record_buf[OFF_KCV])` (`:415`) | no | **yes** | **yes** |
| UART/helper transport (`edge_uart_transport.sv`) | n/a | `rec_kcv` from `helper_record.sv:50` (`raw[OFF_KCV +: 224]`) | received bytes | `core_kcv_ref` | cleared | **yes** | **yes** |
| Operational top (`Kyber_System_Top.sv`) | as SoC | as SoC | as SoC | as SoC | no | **yes** | **yes** |
| ASIC frontend (`Edge_Puf_Mlkem_Asic_Top.sv`) | n/a | external port `kcv_ref_i` (`:32,92`) | off-chip source | `edge_root_binding` | n/a | depends on board anchor | hook only |
| `Kyber_System_Asic_Top.sv` | n/a | none | n/a | `.kcv_ref()` unconnected (`:82`) | n/a | n/a | placeholder only |
| Sim wrappers | TB-driven | TB | TB | TB | TB | TB | TB |

Enrollment writes the public KCV into the record; reconstruction always takes
the reference from the same unauthenticated helper, so reference and helper
travel together.

## 2. Threat tests (attacker may rewrite the whole record and recompute CRC)

| # | Case | Result |
|---|---|---|
| 1 | helper correct + matching KCV | PASS (`tb_edge_phase1_e2e` noise 0..8) |
| 2 | helper modified + stale CRC | parser FAIL (`helper_record` CRC slot) |
| 3 | helper modified + recomputed CRC | parser PASS (header valid), FE reconstruct attempted |
| 4 | codeword delta, original KCV | KCV mismatch, blocked (`tb_edge_phase1_e2e` case 3) |
| 5 | codeword delta + KCV replaced with the matching digest | **PASS, KEM started** (`tb_edge_kcv_substitution` case B) |
| 6 | gate outcome for case 5 | **PASS → active substitution not blocked** |

The new audit test also shows: case A (delta, original KCV) rejected; case C
(correct root, wrong KCV) rejected.  Only the matching substitution passes.

Additional oracle on the SoC path: reads at `KCV_REF` return the computed
`kcv_out` (`soc_peripherals.sv:262`), so CPU-side software can obtain the KCV
for a substituted helper and write it back as the reference.  On the ASIC
frontend the computed digest is exported (`kcv_out_o`) and can be consulted by
whatever supplies `kcv_ref_i`.

## 3. Proposed trust-anchor architecture

Keep the "no secret key in NVM" property: the KCV is a public verifier.  What
is missing is integrity/immutability of the **reference**, separate from the
helper.

- Operational core receives `trusted_kcv_ref` from its own source; the
  helper-provided KCV must never drive the comparator.
- Enrollment (diagnostic / manufacturing) may export the public KCV for
  provisioning; operational mode refuses enrollment/update (already the case
  via `EDGE_ALLOW_ENROLL=0`).
- Candidate anchors for the FPGA demo, in order of preference:
  1. ROM/constant inside the operational bitstream (per-device provisioned
     image) — immutable for the lifetime of the image, no secret.
  2. Write-once register bank locked after provisioning (lock bit survives
     until full power cycle and is re-asserted before any reconstruct).
  3. A dedicated enrollment store with its own integrity/lock, separate from
     the helper record.
- Do not accept a host-supplied KCV per session as the anchor while the host or
  helper is inside the attacker model.
- Bind generation/device identity and mapping version/tag in the KCV context
  (already: record_version, protocol, profile, fe_param, mapping_tag,
  generation).
- Reset must not disable the gate or mark a missing anchor as valid:
  fail-closed when `trusted_kcv_ref` is absent/invalid.

## 4. Interface decision (exact changes for the next RTL phase)

- `rtl/top/edge_puf_mlkem_core.sv`: split `kcv_ref[223:0]` into
  `trusted_kcv_ref[223:0]` (to `edge_root_binding.kcv_ref`) and
  `helper_kcv_ref[223:0]` (secondary equality check only).  Add
  `trusted_kcv_valid`; `kcv_enable` must be `trusted_kcv_valid`, never
  constant 1.
- `rtl/top/edge_uart_transport.sv`: stop driving `core_kcv_ref <= rec_kcv`
  (`:414`); expose `core_helper_kcv` instead.  The trusted reference comes from
  the top-level anchor.  Enrollment output unchanged.
- Tops: `Edge_Zynq_Diagnostic_100MHz_Top.sv`, `Edge_Arty_Diagnostic_Top.sv`,
  `Kyber_System_Top.sv`, `Edge_Puf_Mlkem_Asic_Top.sv` (`kcv_ref_i` → anchor
  port), `Kyber_System_Asic_Top.sv` (connect or fail-closed instead of `()`).
- `rtl/soc/soc_peripherals.sv`: make `kcv_ref_reg` write lockable after
  provisioning (write-once + lock), and return `kcv_out` reads only in
  enroll/diagnostic mode so the operational path has no digest oracle.
- `firmware/main.c`: reconstruct must not write `KCV_REF` from the record; it
  only starts the engine and checks pass against the locked anchor.  Enroll may
  provision.  Operational refuses enrollment (already).
- Do not expose the reconstructed FE key through CPU/MMIO/debug; keep
  `fe_kcv`/`kcv_out` diagnostic-only.
- Mapping tag remains a configuration identifier, never an authentication
  substitute.

## 5. Status

`ACTIVE_SUBSTITUTION_BLOCKER`: case 5 passes, so same-root binding is not safe
against an active helper substitution while the KCV reference travels inside
the helper record.

## 6. Migration and test plan

1. Add `trusted_kcv_ref` from a ROM/locked source with a `valid` flag; default
   fail-closed when absent.
2. Comparator uses only `trusted_kcv_ref`; helper KCV becomes a secondary
   consistency check (its mismatch fails; its match alone is not enough).
3. Remove the SoC digest oracle from the operational path; lock the reference
   registers; firmware reconstruct no longer writes the reference.
4. Tests to add/keep:
   - case 5 must FAIL after the fix (delta + replaced KCV);
   - missing/invalid trusted anchor → gate fails closed;
   - correct helper + trusted anchor → PASS;
   - wrong trusted anchor → FAIL;
   - reset/power-cycle does not bypass or zero the anchor incorrectly;
   - MMIO/enroll digest read unavailable in operational mode;
   - KDF/ML-KEM never start on any gate failure.
5. Re-run `make edge-root-binding` plus the substitution audit (now expecting
   rejection) and record results.

## 7. Wording

The KCV is a public verifier, not a MAC; it only proves same-root relative to a
reference that must itself be integrity-protected.  A 16-bit mapping tag is a
configuration identifier only.  This audit does not change the mapping,
reference, thresholds or any PUF datapath.
## 8. Resolution (T0-T8 trust-anchor fix)

Trust model (T0): helper/UART/host input is untrusted; an attacker may rewrite
the whole helper record and recompute its CRC; the FPGA operational bitstream
and JTAG/programming flow are trusted in this prototype; the KCV is a public
verifier, not a secret, so "no secret key in NVM" still holds when only the
public anchor is stored; bitstream authenticity in a product is a separate
secure-boot requirement and is not claimed here.

Implemented:
- `rtl/top/edge_kcv_anchor.sv` + `rtl/top/edge_kcv_anchor_rom.vh` template
  (default fail-closed): ROM anchor for operational mode, one-shot diagnostic
  provisioning latch otherwise; reset/zeroize never clears a ROM anchor and
  no runtime bypass exists.
- `edge_puf_mlkem_core`: split `trusted_kcv_ref/valid` from `helper_kcv_ref/
  valid`; the comparator only uses the anchor, the helper KCV is a
  comparison-only consistency input; `enroll_allowed` gates provisioning;
  missing anchor fails closed before KDF/ML-KEM.
- `edge_uart_transport`: exposes `core_helper_kcv[_valid]` and never drives
  the trusted reference; `ALLOW_ENROLL` default is now 0.
- SoC: `Kyber_System_Top` instantiates the anchor (diagnostic auto-provision
  for the research image; ROM for operational), `soc_peripherals` keeps the
  shadow comparison-only, gates the computed-digest read behind
  `DIAGNOSTIC_PROVISION`, and exposes anchor-valid in `KCV_CTRL`; firmware
  reconstruct never writes the trusted reference and refuses when the anchor
  is unprovisioned.
- ASIC: `Edge_Puf_Mlkem_Asic_Top` takes `trusted_kcv_valid_i/ref_i` (+ helper
  consistency inputs); `Kyber_System_Asic_Top` is explicitly frontend-only
  with no engine and `kcv_pass=0`.

| Top | Trust source |
|---|---|
| Edge_Arty_Diagnostic_Top / Edge_Zynq_Diagnostic_100MHz_Top | diagnostic anchor, one-shot from first enrollment |
| Kyber_System_Top (DIAGNOSTIC_ANCHOR=1, research image) | diagnostic anchor + comparison shadow |
| Kyber_System_Top (DIAGNOSTIC_ANCHOR=0) | ROM anchor; elaboration fails if ROM_VALID=0 |
| Edge_Puf_Mlkem_Asic_Top | platform `trusted_kcv_valid_i/ref_i` (ROM/OTP) |
| Kyber_System_Asic_Top | none (frontend-only, kcv_pass tied 0) |

Evidence: `tb_edge_phase1_e2e` (anchor invalid/wrong/helper-mismatch reject),
`tb_edge_kcv_substitution` (`KCV_ACTIVE_SUBSTITUTION_REJECTED`),
`tb_soc_kcv_operational` (no CPU write path to the anchor, no digest oracle in
operational mode), `sim/system` wrong-root KCV rejection, firmware `-Werror`,
ASIC frontend elaboration.
