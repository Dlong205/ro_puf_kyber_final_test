# PUF64 Train/Holdout Campaign Protocol (ZYNQ-A01)

Frozen before any train data is collected.  No RTL/XDC/INFO/bitstream change is
permitted in this campaign.  Raw data is private and git-ignored
(`reports/puf64_campaign/`).

## 1. Golden input (immutable)
Board `ZYNQ-A01`; **protocol 3.1** (major 3, minor 1, record_bytes 20, status+CRC);
image_mode `PUF_CHARACTERIZATION` (code 1); topology `0xC0DE`; **build_id 2**;
NUM_RO 64; PAIR_COUNT 2016; WIDTH 16; ripple 17 stages/RO (overflow guard);
input 50 MHz / system 100 MHz; REF_CYCLES 1023; window 10230 ns; prescaler on;
lock `placement + LOCK_PINS + route-fingerprint fail-closed`, `FIXED_ROUTE=false`.
Active SHAs are in `constraints/puf_allpairs64_golden_manifest.json`.

**Revoked**: build_id 1 (bitstream `5eaebb00…`) — no direct status/CRC; its pilot
reports are historical architecture evidence only and must not qualify build 2.
The 3 pilot boots are excluded from train/holdout.
Reporting wording: status/timeout/wrap are **enforced by the record status byte
and CRC in RTL**; the host checks the status byte + CRC (not an inference).

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

---

## 14. Status-flag gate — BLOCKER on candidate build 1 (revoked)

Read-only trace of candidate build 1 (`build_id=1`, bitstream `5eaebb00…`):

- `rtl/debug/puf64_ro_bench.sv` S_CAPTURE (lines 150–157) asserts `telemetry_valid`
  on both stable and timeout (`(stable) || cnt_timeout==CAPTURE_TIMEOUT-1`);
  `telemetry_stable/timeout` are auxiliary outputs.
- `rtl/top/Puf_AllPairs64_Characterization_Top.sv` connects only
  `.telemetry_valid` to the production UART; `telemetry_stable/timeout` are
  unused (`unused_tel`).
- `rtl/top/puf_allpairs_uart.sv` captures on `telemetry_valid` only (line 96);
  the 16-byte record carries no status flags.

Therefore a record CAN be emitted with a plausible-looking count while
unstable/timeout, and the host cannot detect it.  Hence candidate build 1 is
**revoked** for train/holdout; the pilot reports remain as historical evidence
only.  `count<60000` is a heuristic, not proof of stability.

## 15. Protocol 3.1 (build_id=2) — direct status + CRC16

- Bump protocol `3.0 -> 3.1`, `build_id 1 -> 2`; build 1 revoked for all future
  campaigns.
- Every pair emits exactly one terminal record, including on timeout.
- Record = 20 bytes: `index u16 | pair_a | pair_flags | count0 u32 | count1 u32 |
  margin u32 | status u8 | reserved(0) | crc_low | crc_high` (all LE).
- Status bits: 0 stable, 1 timeout, 2 overflow_a, 3 overflow_b, 4 count_zero_a,
  5 count_zero_b, 6 mmcm_locked_snapshot, 7 reserved(=0).
- A record is valid only if stable=1, timeout=0, overflow_a/b=0,
  count_zero_a/b=0, mmcm_locked=1, reserved=0, CRC valid.
- CRC-16/CCITT-FALSE: poly 0x1021, init 0xFFFF, no reflect, xorout 0x0000,
  covers bytes 0..17, stored low byte then high byte at 18/19.
  Golden: body `00000001e8030000d0070000e80300004100` -> CRC `0xD1CB`
  (full `…41 00 d1 cb`); status 0x02 body -> CRC `0x934E`.
- UART still delivers exactly 2016 records; missing record is a secondary
  detection, not the primary mechanism.
- Overflow guard: ripple counter is WIDTH+1 stages; transmitted count is the low
  WIDTH bits, the high stage is `overflow`; reset and captured with the count.
- Topology count changes to 64 prescalers + 64*(WIDTH+1) ripple stages
  (1088 for WIDTH=16); assertions/fingerprint/`topology_id` updated accordingly.
- Candidate lifecycle: rerun F1/F2, F3 auto-place + smoke (all status valid,
  CRC ok), F4 re-export/reapply lock + 2 clean fingerprint, F5 new manifest
  (protocol 3.1, build 2, new SHAs), then a fresh 3-boot pilot before train 101.
- Reporting: never write "host confirmed timeout/stable/wrap"; write
  "RTL/record status enforce; host checks the status byte + CRC".
