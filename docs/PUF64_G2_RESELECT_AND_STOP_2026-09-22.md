# PUF64 gen2 margin-reselect: outcome and fail-closed stop (2026-09-22)

Branch: `codex/fpga-v2-split`, HEAD `103e5e1` (worktree dirty, no commit/push
per task constraints). Vivado 2020.1 at
`/media/donglong/tools/Xilinx/Vivado/2020.1`. Board `ZYNQ-A01` (`xc7z020_1`).

## Verdict: NOT READY — stop code `OPERATIONAL_OFFSET_NOT_BOUNDED`

No final image is frozen, programmed, or claimed. The board is left on the
known-good gen1 diagnostic (SHA-attested, see §6).

## What was done

1. **Audit.** Board reprogrammed to gen1 diagnostic `279a1ae0` (INFO
   `454101010f`). SHAs verified from files. Diffs reviewed: tie-absorb
   scheduler policy, BCH corr-count latch, diagnostic transport codes —
   all diagnostic-gated; release path still generic `0x03`, 2 bytes.
2. **SYNTH-6 gate.** Final `428af11a` failed the old allowlist (9 vs 2).
   All 8 entries classified: ML-KEM hash `ififo/ofifo/ofifo1` + NTT
   `RAM0-4`, message "no output register merged", none under the PUF macro
   hier, no latch/truncation/multi-driver, timing still WNS `+0.219 ns`.
   Gate updated to an EXACT 8-instance set (fails on any foreign, missing,
   or macro-hier instance) + `--selftest` negative tests
   (`SYNTH6_SELFTEST_PASS`, gate `FINAL_IMAGE_REPORT_GATE_PASS`).
3. **Sim mapping gap (found + fixed).** Scheduler/operational sims included
   `rtl/top/puf64_mapping_data.vh` — the STALE legacy d501 table — while the
   board runs frozen V2. Proven: tb literal `f845...` == legacy synthetic
   golden. Fixed: `PUF64_MAPPING_DIR` include prepend (default frozen V2)
   + `PUF64_GOLDEN_HEX` define (default gen1-V2 `572f...`, G2 `5d7c...`).
   Sims now PASS against frozen gen1 AND G2 (scheduler, operational core,
   boundary).
4. **Gen2 reselect (margin ≥ 9).** Same train evidence
   (`train_input_301_320`, aggregate `e94858c0`), only `min_margin_p01`
   4.0 → 9.0. Result: 264 pairs, min margin 9.0, worst minority 0.0,
   degree 48×8/16×9, selection `ea877a59`. Pre-flip context
   (`e9152b9b`) reconstructed byte-exact for the selector binding check
   (kept in `/tmp`, frozen artifacts untouched).
5. **Gen2 post-hoc holdout re-eval.** 500/500 frames, 0 errors, max 0
   (single evaluation, no iteration; threshold motivated by train physics +
   board behavior — documented POST-HOC, not a frozen unbiased closure).
   Canonicalized: tag **`0x005D`**, digest `5d00c4d4...`.
6. **Gen2 artifacts + enroll.** `rtl/puf/v2_mapping_g2/`,
   `host/puf64_mapping_g2_generated.py`, `firmware/puf64_mapping_g2_data.h`
   (gen1 files untouched). Enroll script gained generation overrides
   (defaults byte-identical for gen1, verified). Gen2 helper
   (`e3fb0735...`) + anchor (KCV `7f05d2d1...`, generation `0x02`,
   ctx `0x02005d01010102`); host KCV cross-check PASS; RTL FE reconstruct
   sim with real holdout frame PASS `corr=0`.
7. **Build/bring-up.** Gen2 diagnostic `3026f27b`: fingerprint MATCH,
   WNS `+0.453 ns`, route complete. Found + fixed a real bug on the way:
   two `set_property generic` calls overwrote each other (dropped
   `DIAGNOSTIC_FAILURE_CODES`, seen as release `0x03`); now a single call
   + static check (`check_picorv32_final_static.py` enforces it).
   Host e2e gained `--mapping-tag`.
8. **Board evidence that falsifies the margin model.** Gen2 diagnostic
   live: 10/10 `0x32` BCH-fail with STABLE `corr=1` miscorrection
   (deterministic far word, not marginal noise), while gen1 on the same
   board/practice passes (5/5 + full E2E PASS), gen2 sim/holdout are clean,
   and build contents verified (include order, generics, tag `0x005d`,
   anchor). Inversion (high-margin pairs fail, margin-4 pairs pass)
   rules out the train-margin noise model: the live offsets are
   systematic per-RO and placement-dependent (gen1 itself swung 0/10 on
   build `36b89b3` vs 29-30/30 on `279a1ae0` with identical policy).
   Reselecting to higher margins cannot fix offsets that do not
   correlate with train margin. Freezing gen2 final would be unsound.
9. **Privacy fix.** Helper `*.record` files (gen1+gen2) were NOT
   git-ignored (only `*.helper_record` was). Added
   `reports/puf64_macrov2_campaign/*.record` to `.gitignore`; verified.

## Board final state (safe, attested)

- Programmed: gen1 diagnostic `279a1ae0` (SHA-verified program log).
- INFO `454101010f`; full E2E PASS (positives deterministic:
  `pk e0abecde...`, tags per nonce; negatives `0x08/0x33/0x06/0x32`).
- No final programmed. No cold boots run. No commit/push.

## Key SHAs / identifiers

- Gen1 diag (board): `279a1ae0e3deab88...` | Gen1 final (unprogrammed):
  `428af11aed8aeb20...` | Gen2 diag: `3026f27be...` (fails E2E, kept
  for evidence; build dir self-consistent).
- Gen1 map tag `0x81b5` sel `2e37c3c1`; gen2 tag `0x005D` sel `ea877a59`,
  helper `e3fb0735...`, anchor KCV `7f05d2d1...`.
- Known-bad `b2e1ef33` (dropped diagnostic generic) superseded by
  `3026f27b`; bit copy only in `/tmp` (volatile).

## Limitations / residual risks

- Operational sweep environment (placement-dependent systematic per-RO
  offsets) is NOT bounded; quiet-char-image margins do not transfer.
- Gen2 holdout re-eval is post-hoc by construction (selection postdates
  holdout); threshold was train/board-motivated, evaluated once.
- Single device, no PVT/aging, no cold-boot campaign, no second board.
- Legacy (non-PicoRV32) wrappers predate diagnostic ports (floating
  inputs, trimmed at DIAGNOSTIC=0); untouched by design, not built.
- `Vivado` is not bit-reproducible across runs; A/B reproducibility for
  any future final must still be demonstrated.

## Corrective path (not started)

1. Isolate the operational sweep (gate surrounding logic during PUF
   measurement) to shrink implementation-dependent offsets.
2. Requalify the mapping with characterization taken through the
   operational image path (not the quiet char image), then freeze.
3. Consider keep-out/placement discipline around the macro + temperature
   logging during campaigns.
4. Only then: final rebuild → A/B → gates → warm → 3 user cold boots →
   manifest → review → commit on explicit request.
