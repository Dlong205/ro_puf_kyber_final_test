# PUF64 I4 → I5 FPGA path (preservation first, trusted anchor second)

Date: 2026-09-20. Branch: `codex/fpga-v2-split`. Checkpoint: `103e5e1` (clean,
matches `origin/codex/fpga-v2-split`; Bước 0 push already satisfied — no ahead).

Golden pins (do not regenerate from a new build):

- Golden routed DCP SHA-256: `febefcc7129fdf42aae7c3be55875ed61f8cfb72562bbe8830d514628b2788e0`
  (`build/puf_allpairs64_characterization/puf_allpairs64_zynq7020.runs/impl_1/…_routed.dcp`)
- Golden characterization bitstream: `e920b4a9…967c754d` (board `ZYNQ-A01`)
- Physical inventory: 256 RO LUT / 64 prescaler / 1088 ripple stages /
  1408 LOC / 1408 BEL / 256 LOCK_PINS. No BUFG/BUFH/BUFR on RO/prescaler/ripple nets.

## I4.2 (Vivado 2020.1)

1. Static gate (no Vivado): `make puf64-i42-gate` → `I4_1…PASS` + `I4_2_BUILD_GATE_PASS`.
2. Golden fingerprint (Vivado 2020.1):
   `make puf64-operational-golden-fp` → `reports/puf64_operational_preservation/golden_expanded_fingerprint.tsv`
   (refuses any DCP whose SHA ≠ `febefcc7…`; format `I4_EXPANDED_FINGERPRINT_V1`
   with CELL/TAP/RIPPLE + driver/sink + clock class).
3. First build: `make puf64-operational-build` (synth + impl, 100 MHz timing,
   route-complete, 0 critical warnings, hierarchy/inventory/tap/clock audits,
   then candidate fingerprint + `I4_PHYSICAL_FINGERPRINT_MATCH`).
4. Manual compare if needed: `make puf64-operational-fp-compare`.
   Any REF_NAME/INIT/LOC/BEL/LOCK_PINS/route diff → `I4_PHYSICAL_FINGERPRINT_MISMATCH`:
   stop, no board program, KCV pass never overrides.

## I4.2a (approved 2026-09-20, implemented, worktree uncommitted)

- `kp_puf64_mapping_scheduler.sv` only: pre-registered
  `puf64_map_sorted_full/dest(sel_ptr)` lookup, 2-deep event FIFO, 1-cycle
  commit bubble, drain-safe FINISH (valid only after the last event commits).
  No change to bench/RO/ripple/wrapper/sweep order/table/destinations/timing.
  Plus `input logic` -> `input wire logic` (Vivado 8-6735 under
  `default_nettype none`) in the scheduler + physical wrapper.
- Scheduler sim: 19 checks PASS (burst spacing-1, coincident last-event/done,
  reset/zeroize-while-pending, last-pair fault, last-entry tie, trailing
  unselected tie, no-early-valid, consume-zeroize; negedge-only ready driving
  to avoid a TB sampling race).
- Core sim model: event spacing 1/cycle -> 1/8 cycles (real bench ≈ 1040);
  sustained full-rate is outside the no-backpressure interface contract.
- Critical-warning gate now scans `synth_1/runme.log` + `impl_1/runme.log`:
  exactly 64x `Synth 8-295` (RO 0..63, in-macro, RO-cell source) + 0
  unexpected; `Timing 38-282` must be absent.

## I4.2 rerun result (2026-09-20, Vivado 2020.1) -- FINGERPRINT MISMATCH, STOP

- Synth/impl complete; route complete (51451/51451); timing 100 MHz PASS
  (WNS +0.355 ns, 0 failing); critical warnings: 64 expected RO-loop, 0
  unexpected; inventory 256/64/1088 + tap endpoints + clock audit PASS.
- `I4_PHYSICAL_FINGERPRINT_MISMATCH` (1390/2561 lines differ per side):
  placement preserved (256/256 RO LUT lines incl. LOCK_PINS identical; all
  prescaler/stage LOC/BEL/REF/INIT identical) but routes differ (TAP 50/64,
  RIPPLE 1088/1088, e.g. `ro[0].counter/out` same driver/sinks, different
  nodes). Root cause: tap/ripple nets were never route-locked (by design,
  FIXED_ROUTE excluded) and the router chose different paths around the
  operational logic; unlocked INV LUT1s also sit at different BELs.
- Verdict: placement-OK-route-differ -> I4.3 per plan. Bitstream
  `e5bafb21...8901b07` / DCP `c4e7ea08...4c6c` are UNQUALIFIED: no board
  program, no mapping claim, KCV must not override. I4.4 blocked.
- Next (needs approval): I4.3 option A -- scoped import of the golden routed
  macro; abort the candidate on any partial route/RTSTAT/conflict and never
  force FIXED_ROUTE.

1. Static gate (no Vivado): `make puf64-i42-gate` → `I4_1…PASS` + `I4_2_BUILD_GATE_PASS`.
2. Golden fingerprint (Vivado 2020.1):
   `make puf64-operational-golden-fp` → `reports/puf64_operational_preservation/golden_expanded_fingerprint.tsv`
   (refuses any DCP whose SHA ≠ `febefcc7…`; format `I4_EXPANDED_FINGERPRINT_V1`
   with CELL/TAP/RIPPLE + driver/sink + clock class).
3. First build: `make puf64-operational-build` (synth + impl, 100 MHz timing,
   route-complete, 0 critical warnings, hierarchy/inventory/tap/clock audits,
   then candidate fingerprint + `I4_PHYSICAL_FINGERPRINT_MATCH`).
4. Manual compare if needed: `make puf64-operational-fp-compare`.
   Any REF_NAME/INIT/LOC/BEL/LOCK_PINS/route diff → `I4_PHYSICAL_FINGERPRINT_MISMATCH`:
   stop, no board program, KCV pass never overrides.

## I4.3A outcome (2026-09-20, Vivado 2020.1) -- STOP, two blockers

- Export from golden DCP `febefcc7…` OK: inventory 256/64/1088 + 64 TAP +
  1088 ripple routes verified; macro checkpoint
  `build/puf64_operational_preservation/i4_routed_macro_u_puf.dcp`
  (SHA `2a8da756…`, manifest `i4_routed_macro_manifest.tsv`). Census: all
  1088 ripple-chain INV LUT1s sit OUTSIDE golden `u_puf` (flat top-level
  names); macro boundary = 4262 ports. Tool note `Vivado 12-7117` (advisory).
- Import trial on the existing operational synth: REFUSED verbatim --
  `ERROR: [Project 1-257] Command is only supported on a black-box
  instance. Cell '…/u_puf64_physical/u_puf' is not a black-box.`
  `read_checkpoint -cell` (2020.1) only serves black-box/OOC instances;
  forcing it (stubbing the target to black box) is forbidden.
- Structural blocker (independent): golden INVs outside `u_puf` vs
  operational INVs inside the target -- boundary incompatible, so scoped
  import could not have preserved the ripple clock paths anyway.
- Extra probe (read-only): even intra-ring nets differ for ro[0]
  (t1/t2 local nodes; t0 identical). Placement is intact but no route is
  provably identical -> requalification analysis required before any I4.3B.
- Scripts: `export_puf64_routed_macro.tcl` (done),
  `trial_puf64_routed_macro_import.tcl` (verdict: STOP, no save, no route).
  No board program. Worktree uncommitted.

## I4.3 closure (ratified 2026-09-20) -- no I4.3B rerun

- I4.3B was already substantively executed by I4.2 (placement + LOCK_PINS +
  free router -> route mismatch). Re-running the same configuration creates
  no new evidence; no further free-route build is needed.
- Golden mapping/tag/helper remain qualified ONLY for fingerprint
  `a35fac78…`; they must not be transferred to any new candidate.
- I4.4 and I5 stay blocked. No operational bitstream on hand may be
  programmed. HEAD stays `103e5e1`; worktree stays uncommitted.
- I4.3A export/trial scripts are kept as evidence.
- Next engineering step (not started): physical macro V2 with explicit
  in-hierarchy LUT1 inverters + OOC black-box flow (R1), then a new
  characterization image (R3), fresh-board requalification
  (R4: pilot + >=20 train + >=10 holdout cold boots, new 264-pair mapping),
  and only then operational embedding (R5). No train/holdout until
  characterization and operational prove the same routed-macro fingerprint.

```text
I4.3A_BLOCKED_VIVADO_BLACKBOX_AND_BOUNDARY
I4.3B_EXHAUSTED_BY_I4.2_FREE_ROUTE_MISMATCH
REQUALIFICATION_REQUIRED
BOARD_PROGRAM_PROHIBITED
```

## I4.3 (only if I4.2 routes differ while placement is right)

- Template: `scripts/reuse_puf64_physical_macro.tcl`. Order A (scoped routed-macro
  import, keep internal place+route, external control/clock free, all macro ports
  connected) → B (1408 LOC/BEL + 256 LOCK_PINS, free router, re-extract + compare).
- Abort on partial route / RTSTAT / conflict; never force `FIXED_ROUTE`.
- Route mismatch → `I4_PHYSICAL_FINGERPRINT_MISMATCH`; re-qualify via train/holdout.

## I4.4 (after one fingerprint-passing candidate)

- Clean build A: save bitstream + routed DCP + expanded fingerprint + topology /
  timing / route-status / DRC-methodology / clock-resource reports + source manifest + commit.
- Clean build B: delete only the I4 build dir, rebuild from same commit + Vivado 2020.1.
- Require `fingerprint_A == fingerprint_B`, `topology_A == topology_B`,
  `clock_use_A == clock_use_B`; both timing-100 MHz PASS, route-complete,
  0 critical warnings, correct hierarchy, no global buffers on PUF clocks.
- Record both bitstream SHAs (byte equality not required). No freeze manifest here.

## I4.5a (only after I4.4 PASS; placeholder anchor — bridge check only)

- Program the approved bitstream SHA; INFO/build identity must self-report as
  preservation/non-release. UART framing + parser-reject OK; invalid/wrong anchor
  blocks before KDF/ML-KEM; no raw response/count/FE root/KCV oracle/shared secret;
  no UART hangs. KCV PASS is NOT required (public token ≠ device root).
- Optional: skip programming the placeholder and go straight to I5 after I4.4 PASS.

## I5 → I5.1 (trusted anchor, then rebuild)

1. Collect the anchor from the qualified physical image (board `ZYNQ-A01`, golden
   bitstream `e920b4a9…`, qualified mapping/tag, correct helper version, trusted
   host procedure; multiple cold boots, stable root/KCV). Never from the
   placeholder, a mismatched candidate, an unverified helper, or an unidentified run.
2. Device anchor artifact: 224-bit KCV + board ID + golden bitstream SHA +
   fingerprint SHA + mapping digest/tag + helper version/digest + timestamp/tool
   version. Do not publish device-identifying anchors.
3. Patch the shell (`DIAGNOSTIC_ANCHOR=0`, `ROM_REF=DEVICE_TRUSTED_KCV`,
   `ROM_VALID=1`, keep `ALLOW_ENROLL=0`, `LEGACY_HELPER_ENABLE=0`, `provision=0`,
   no UART/MMIO anchor path). Static check: `python3 scripts/check_puf64_post_provision.py`.
4. I5.1 rebuild: full inventory + expanded fingerprint + 100 MHz timing +
   route/clock/critical-warning audits; require
   `post_provision_fingerprint == qualified_golden_fingerprint`, else
   `I5_POST_PROVISION_PHYSICAL_FINGERPRINT_MISMATCH` and stop (no program).
   Repeat clean-build A/B if the anchor change perturbs implementation.

## Formal FPGA E2E (only with true anchor + fingerprint/timing/route PASS + recorded identity)

- ≥3 independent cold boots (full power-off, settle, power-on, program exact
  bitstream SHA, save INFO/build identity, repeated PUF→FE→KCV→KDF→ML-KEM loops).
- Positive: correct helper/mapping/tag/anchor → FE OK → KCV PASS → downstream only
  after KCV PASS; no timeout/overflow/count-zero/mapped error; reset/zeroize works;
  no secret/raw PUF on UART.
- Negative (all fail-closed, no downstream KDF/ML-KEM, no valid result tag, no KCV
  oracle, no raw/count/root/secret leak): 1-bit helper flip, bad helper KCV, bad
  mapping tag/version, wrong anchor (separate test image), active substitution,
  truncated/timeout UART record, replay/bad nonce if bound, mid-path reset.
- PASS iff: fingerprint + reproducibility + post-provision PASS, 3 cold boots PASS,
  positive + negative PASS, no raw/secret export. Then freeze manifest + archive
  bitstream/DCP/fingerprint/evidence.

## R1/R2/R3 record (2026-09-20, autonomous)

- R1: macro-V2 RTL (explicit 1152 LUT1 in-hierarchy) + counter/sweep
  equivalence sims PASS + OOC census (256/64/1088/64/1088, contained) PASS.
- R2: routed OOC macro frozen: DCP `bd0cd620…`, fingerprint `7d12e3a9…`,
  freeze gate PASS (0 session criticals, exact DRC/methodology, macro_clk PASS).
- R3: char build-3 image: bitstream `cfc72674…`, DCP `a7703fa0…`,
  `R2_MACRO_FINGERPRINT_MATCH(char)`, image report gate PASS.
- R5-shell: operational-V2 construction: bitstream `9c153241…`,
  `R2_MACRO_FINGERPRINT_MATCH(shell)`, report gate PASS (operational
  profile), status CONSTRUCTION_NONRELEASE_NEVER_PROGRAM. Known limitation:
  dual-clock macro_clk methodology criticals (R5-final single-clock task);
  clk_sys WNS +0.007 PASS (thin).

## R4 board smoke (2026-09-20, live ZYNQ-A01) -- PASS (warm, non-campaign)

- JTAG: Digilent/260515110006, arm_dap_0 + xc7z020_1 (IDCODE captured).
- Programmed char build-3 bitstream `cfc72674…`:
  `PUF64_MACROV2_PROGRAM_PASS` (SHA-gated script, single target/device).
- Live UART (build 3, proto 3.2, mode 0x01, MMCM locked), INFO2 macro
  `bd0cd620…` + fp `7d12e3a9…` both match the frozen manifest on silicon.
- One MARGIN frame: 2016 canonical records, first pair (0,1).
- Warm smoke only: no session files written, no cold-boot claims. Pilot-cold
  (boot 300) + train (301..320) + holdout (401..410) still require operator
  power-cycles (checklist). Holdout stays ineligible until train freeze.

## Phase 1 record (autonomous): train freeze + selection -- PASS

- Verified 20/20 train 301..320 VALID/50 frames/board/build-3/proto-3.2/SHAs,
  distinct=50, no holdout data. Deviation boot-301 first attempt kept as
  `.invalid` (CRC mismatch idx 1990, 0 frames), retry accepted.
- Tie population ~700 events/boot (unselected, legal); minority pairs ~15-22.
- Freeze: 20 boots aggregate `e94858c0…`; refreeze identical (determinism).
- Selection (train only, 124 unit tests PASS): 264/264 from 1888 eligible,
  degree 8..9 (48x8+16x9), selection `2e37c3c1…`, balance 146/118
  (sign not a criterion); reselect identical.
- `V2_TRAIN_INPUT_FREEZE_PASS`, `V2_TRAIN_SELECTION_PASS`,
  `HOLDOUT_AUTHORIZED` (context `e9152b9b` -> `e9d05962`, holdout_eligible
  flipped with reason; train sessions stay bound to pre-flip SHA).

## Phase 3 record (autonomous): holdout + mapping freeze -- PASS

- 10/10 holdout 401..410 VALID/50, post-flip context, macro/fp SHAs bound.
- Holdout input FROZEN (`e789353a…`); candidate snapshot
  (`holdout_candidate_private.json` + backup) with temporal proof (bundle
  predates boot 401).
- Eval: 500 frames, p50/p95/p99/max = 0, FRR 0.0, 0 ties/minority on
  selected, all 6 gates true. No pair/threshold touched by holdout.
- Canonicalized: tag 33205 (`0x81b5`), digest `b581f44f…`, canonical SHA
  `447fd06b…`; rerun identical (determinism).
- `V2_HOLDOUT_INPUT_FREEZE_PASS`, `V2_HOLDOUT_EVALUATION_PASS`,
  `V2_MAPPING_CANDIDATE_FREEZE_PASS`. Old golden mapping/tag/helper stay
  locked to fingerprint `a35fac78…`.
