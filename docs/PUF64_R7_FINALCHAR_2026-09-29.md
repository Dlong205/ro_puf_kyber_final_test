# R7 characterize-through-final + re-selection (2026-09-28/29)

Branch: `codex/fpga-v2-split`. Char image BIT `3e7ef332...` (build 3:
NONRELEASE telemetry, INFO `0x71`, tie budget 8, timeout 2048; route/timing/
lifecycle/fingerprint PASS, WNS `+0,121 ns`). Train freeze `7af51c09...`
(pilot 703 + train 704–723, 150 frames). Selection `b1b2b076...` (264 pairs,
tag `0x81B7`, margin ≥ 9, degree 8–9). Enroll sim PASS (helper `55bf5588...`,
anchor KCV `14edaaed...`). Authorization `c6842f18...` (boots 801–810).

## Why R7 exists

Release plain-final builds (C/D) fail board deterministically with `0x32`
BCH while qual passes the same helper/board. Final-path telemetry showed
**128/264** selected winners disagreeing with the qual-frozen reference
(CRC-verified frames): systematic placement-dependent offset, matching the
G2 finding. Abort signature at sweep index 867 (8/60 warm sweeps) traced to
selected pair **(15,38)** tying 37/49 frames and tripping the 2-tie scheduler
budget — fixed for collection with `TIE_BUDGET=8` (release keeps 2).

## Holdout closure — 10/10 PASS on the char image

Aggregate 801–810: 10/10 valid cold boots, 500/500 valid frames, CRC-verified
headers+bodies; **selected errors total 0 / max-per-frame 0 / p95 0**
(gates: no frame > 8, no boot-majority > 8, p95 ≤ 4); zero selected ties;
BCH correction max 0 (gate ≤ 8); full-pool ties 7163; conservative overrun
flags 490 with no gap. `R7_HOLDOUT_801_810_PASS_CHAR_IMAGE_ONLY`.

This qualifies the R7 MAPPING (tag `0x81B7`), not any release image.
Release cutover (R7 mapping dir switch, tag default, firmware/host
artifacts, release rebuild pair, 3-cold-boot E2E, freeze) remains open.
Limitations: one board (`ZYNQ-A01`), no PVT/aging; 500 frames prove no
zero-failure rate, uniqueness, or min-entropy.

## Release closure — R7 release pair + formal E2E 3/3 PASS (2026-09-29)

- Release builds with R7 mapping (`PUF64_MAPPING_R7=1`, own dir, tag/KCV
  generics): A `bfbff188...`, B `ab075bfd...`; route/timing/lifecycle/
  fingerprint PASS both; WNS `+0,306 ns`, WHS `+0,051 ns`, 0 failing;
  fingerprint A==B MATCH (3713 lines). Archived `repro_A/B`.
- Formal E2E on exact B image + R7 helper, 3 independent cold boots:
  INFO release, enroll/`0x70` disabled, 3 positives each, pk stable
  `9311c3c3...` with identical result tags across all boots and negatives
  fail-closed (`0x08/0x03/0x06/0x03`). **3/3 PASS.**
- Freeze: `reports/puf64_operational_final_r7/R7_RELEASE_FREEZE.json`
  (`4b48deba...`), evidence `reports/puf64_final_r7_e2e/boot{1,2,3}_*.log`.
- Release BIT is B (`ab075bfd...`); A kept as repro evidence. This closes
  the plain-final FE `0x32` blocker for the R7 mapping on `ZYNQ-A01`.
  Independent review, multi-board/PVT/aging, license gates still open
  (public/production remain NO-GO).
