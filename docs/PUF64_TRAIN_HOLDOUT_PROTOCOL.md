# PUF64 Train/Holdout Campaign Protocol (ZYNQ-A01)

Frozen before any train data is collected.  No RTL/XDC/INFO/bitstream change is
permitted in this campaign.  Raw data is private and git-ignored
(`reports/puf64_campaign/`).

## 1. Golden input (immutable)
Board `ZYNQ-A01`; protocol 3.0; image_mode `PUF_CHARACTERIZATION` (code 1);
topology `0xC0DE`; build_id 1; NUM_RO 64; PAIR_COUNT 2016; WIDTH 16;
input 50 MHz / system 100 MHz; REF_CYCLES 1023; window 10230 ns; prescaler on;
lock `placement + LOCK_PINS + route-fingerprint fail-closed`, `FIXED_ROUTE=false`.
Bitstream `5eaebb00…`, routed DCP `91adf5a5…`, route fingerprint `ecc33b53…`
(see `constraints/puf_allpairs64_golden_manifest.json`).

The 3 pilot boots are **excluded** from train/holdout.  Any `build_id=1`
artifact built before commit `eaab60c` is revoked.

## 2. Campaign sizes
- Train: 20 independent cold boots, `boot_index=101..120`, 50 frames each.
- Holdout: 10 independent cold boots, `boot_index=201..210`, 50 frames each,
  ideally a different session/day.
- 50 frames in one boot are NOT 50 power-cycles.

## 3. Power-cycle procedure (per boot)
Real power removal of all rails (no back-power), wait ~10–20 s, power on, operator
confirms.  Reset/reprogram is NOT a power-cycle.  Then: verify local bitstream
SHA, program golden bitstream, flush UART, read INFO, enforce the full golden
tuple, and only then acquire.  The tool requires `--operator-power-cycle`.

## 4. Session manifest + freshness
The tool writes a private session manifest (campaign, board, boot index, UUID,
timestamps, operator confirmation, power-off wait, warm-up, serial device, golden
path/hash, local bitstream SHA, device INFO tuple, host commit, frames
requested/received, raw-payload SHA, parsed-dataset SHA, status, errors,
warnings).  Freshness rejects duplicate `(board, campaign, boot_index)`, duplicate
UUID, cached reads, and requires a fresh RUN with flushed buffers.  Equal raw hash
to a previous session is a strong warning (never an automatic fraud call).  INFO
change mid-acquisition and disconnect/reconnect reject the session.

## 5. Per-boot validity
INFO tuple matches golden; MMCM locked; exactly 50 frames; each frame has 2016
canonical `i<j` pairs, no missing/duplicate, first `(0,1)`, last `(62,63)`,
count0/count1 non-zero, no near-wrap, no parser error, correct
NUM_RO/pair_count/topology/width/ref_cycles.  Invalid boots are recorded with a
reason and never silently reused.

## 6. Unbiased train aggregation
For each pair: per-boot majority over the 50 frames; then a majority across the
20 boots (one vote per boot).  Train reference = across-boot majority.  A tied or
indeterminate across-boot result makes the pair ineligible.  Metrics per pair
include per-boot majority bits, changed-boot count, worst/mean within-boot
minority, tie events, margin p01 per boot and min/median, count drift, RO degree,
invalid events.

## 7. Frozen eligibility (before data)
A pair is eligible only if: valid in all 20 train boots; no
timeout/wrap/unstable; no tie event; majority unchanged across all boots; worst
within-boot minority ≤ 10%; min margin p01 over 20 boots ≥ 4; both RO endpoints
valid in all boots.  If fewer than 264 eligible: stop and report a blocker — never
lower thresholds and never look at holdout.

## 8. Selection (deterministic)
No response sign used; no 132/132 balance goal; no holdout; no pilot.  Ranking:
(1) higher min margin p01, (2) lower worst minority, (3) higher median margin p01,
(4) lower drift, (5) canonical pair index ascending.  Graph: 264 unique edges on
64 ROs; total degree 528; target 48 ROs degree 8 and 16 ROs degree 9; no RO above
9; no hub/star; every RO covered.  If 8–9 is infeasible, stop and report — never
relax constraints.

## 9. Mapping artifact
Private/reviewable candidate: algorithm version, config/thresholds, golden
identity, train boot list, ordered 264 pairs, per-RO degree, per-pair scores,
private train reference, dataset hashes, deterministic selection hash,
single-device limitation, `mapping_tag=0`,
`status=TRAIN_SELECTED_NOT_HOLDOUT_QUALIFIED`.  Never commit raw frames, full
response fingerprint, or secret/reference response.

## 10. Holdout evaluation
After the train mapping is frozen: run 10 holdout boots × 50 frames; take exactly
the 264 selected bits; compare to the train reference; errors-per-vector; FE
predicted success under BCH `t=8`.  Report frame errors, per-boot majority errors,
P50/P95/P99/max, frames and boots over 8 errors, observed FRR, failing selected
pairs, their margin/tie/minority, and per-RO count drift.  Report 500 observed
frames but 10 independent session boots.

## 11. Acceptance gate
PASS iff: 10/10 boots valid; no selected pair invalid/timeout/wrap; no frame > 8
errors; no boot-majority > 8 errors; observed FE failure 0; P95 ≤ 4; no system
error indicating a dead RO or route change; golden tuple/fingerprint unchanged.
On FAIL: never change pairs from holdout; mark the candidate failed.

## 12. Mapping tag
Only after holdout PASS: canonicalize the mapping binding protocol, image mode,
topology, build id, NUM_RO, counter width, REF_CYCLES, clock identity, bitstream
SHA, fingerprint SHA, ordered 264 pair, algorithm/config version; derive a
nonzero `mapping_tag`; status
`RELIABILITY_QUALIFIED_ZYNQ_A01_GOLDEN_BITSTREAM`; record that inter-device
uniqueness and min-entropy 256 are NOT proven, 264 is a FE vector length, and
`log2(64!)≈296` is only a structural ceiling.

## 13. Tools
- `host/puf64_campaign.py` — session acquisition, freshness, validation.
- `host/puf64_train_select.py` — per-boot aggregation, eligibility, selection.
- `host/puf64_holdout_eval.py` — holdout evaluation, gate, mapping tag.
- Make targets: `puf64-train-boot`, `puf64-holdout-boot`, `puf64-train-select`,
  `puf64-holdout-eval`.
