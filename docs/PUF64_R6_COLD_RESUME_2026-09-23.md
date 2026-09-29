# R6 cold campaign resume — 2026-09-23

Status: `NOT READY`. R6.2 A/B remains PASS; no final image was programmed.

The preceding session reported cold pilot boot 501 PASS (50/50 frames), but
its private frame JSON and session manifest are not present in this workspace
or `/tmp` after the host restart. Treat the numerical summary as a report,
not as locally reproducible raw evidence, until its storage path is supplied.
No train or holdout boot evidence has been found locally.

The board UART returned no INFO on preflight. A JTAG configuration loaded
before power-off must not be assumed to survive a cold boot.

Current qualification A bitstream SHA-256:
`a9ffce0e3cb23c894c99e45c27aebc1770a24c505da35ea0eac27315194dc280`

Frozen macro DCP SHA-256:
`bd0cd6200ca4e122932596eb8502d29f1b7d4b1aedf974a79990b4d1f5a9fdd4`

Frozen macro fingerprint SHA-256:
`7d12e3a99849f6d6351e414ebe17829fa2175cdbe42c55bc19df27bbd45afbf5`

R6.2 gate was rerun on 2026-09-23: macro fingerprints MATCH (3713 lines),
operational influence fingerprints A=B (24961 lines), route complete,
WNS A=B +0.265 ns, zero unexpected critical warnings.

`host/puf64_qual_cold_boot.py` now reserves each boot index before JTAG
programming and writes private frame JSON under the git-ignored
`reports/puf64_operational_native_campaign/` directory. It checks the exact
qual A bitstream SHA, A/B physical gate, INFO `4541010171`, disabled
enrollment, frame sequence, CRC, 2016 canonical pairs, clock/overflow status,
public-key stability and BCH correction count. An interrupted attempt remains
reserved and must be replaced with a new boot index.

Next action depends on the boot 501 evidence:

1. If the original private 50-frame directory is found, validate its hashes
   and retain boot 501 as the pilot. Begin train with boot 502.
2. If it is not found, repeat the cold pilot under the next unused index,
   then allocate 20 fresh train indices. Do not represent the missing raw
   frames as qualification evidence.

The operator must disconnect all supply and back-power for at least 10
seconds, wait for LEDs to extinguish, then power up and report the index.
Only after that confirmation may the collector program qual A and acquire
the boot. Holdout remains blocked until 20 valid train boots are frozen and
`HOLDOUT_AUTHORIZED` is recorded.

## Cold pilot 502 — completed

The operator confirmed that boot 501's raw files were unavailable, then
confirmed a fresh power cycle for boot 502. The one-boot collector programmed
qualification image A (exact SHA above) and recorded
`reports/puf64_operational_native_campaign/pilot_ZYNQ-A01_502/`.
The private session manifest SHA-256 is
`0d38eb3410e424b6d7487a57f0f93579ee83bebfebf0a9190d955cc4c151f239`.

Independent readback of the manifest and 50 frame files: all 50 SHA-256
digests match, frame sequence is exactly 1–50, every frame has 2016 canonical
pairs, no timeout/overflow, BCH correction 0, the public key SHA is stable,
and all 50 result tags are distinct. The bad-CRC helper was rejected with
code `0x08`. Selected gen1 pairs: 264/264 have consistent winner, zero
selected ties, minimum observed margin 2. Across the full 2016-pair pool,
26 pairs changed winner at least once; 754 tie events occurred across the
50 frames (9–23/frame). The conservative telemetry overrun bit was set in
49/50 frames, but frame sequence, per-frame CRC, and complete 2016-entry
readback were verified. `R6_PILOT_502_EVIDENCE_PASS`.

Boot 501 remains excluded because its raw evidence is missing. Next allocate
20 cold train boots starting at index 503. Each requires a separate physical
power cycle and must be captured under a never-reused index. No train or
holdout boot has yet been counted in this new evidence set.

## Cold train 503 — 1/20 valid boots

The operator confirmed a separate cold power cycle before boot 503. The
collector programmed the exact qualification A image and recorded
`reports/puf64_operational_native_campaign/train_ZYNQ-A01_503/`.
Session manifest SHA-256:
`c7ce4747611ede87f620a0c9b9ba0a5725f1c43dbd620d2cb18c9476e276c6fa`.
Independent readback verified 5/5 frame file hashes, sequence 1–5, 2016
canonical pairs per frame, no timeout/overflow, BCH correction 0, and the
same public key as pilot 502. All 264 selected pairs agreed with the pilot
consensus, none tied, and minimum selected margin was 2.
`R6_TRAIN_503_EVIDENCE_PASS`. Train progress: 1/20 valid cold boots;
next unused index is 504. Holdout is still blocked.

## Cold train 504 — 2/20 valid boots

After a separately confirmed cold power cycle, the exact qualification A
image produced 5/5 valid train frames at
`reports/puf64_operational_native_campaign/train_ZYNQ-A01_504/`.
Session manifest SHA-256:
`7f7e71a4292de0daf5fdc795d121ca5bccea26ab6f64972ecfa7da1fa5d4a981`.
Independent readback verified all 5 frame hashes, sequence 1–5, 2016
canonical pairs per frame, pilot-bound bitstream/macro/influence/helper
identity, stable public key, FE/KCV PASS, BCH correction 0 and no
timeout/overflow. Selected gen1 pairs: 264/264 agree with pilot 502,
zero selected ties, minimum observed margin 2. Full-pool ties: 93 across
five frames. `R6_TRAIN_504_EVIDENCE_PASS`. Progress: 2/20; next unused
index 505. Holdout remains blocked.

## Cold train 505 — 3/20 valid boots; campaign stopped by operator

The operator confirmed a separate cold power cycle and explicitly requested
that this be the last cold-boot test for now. The exact qualification A image
produced 5/5 valid frames at
`reports/puf64_operational_native_campaign/train_ZYNQ-A01_505/`.
Session manifest SHA-256:
`2036570067f7763802f1c35958d91647268f2afae364b7ee3b157ddb46bf7a2c`.
Independent readback verified 5/5 frame hashes, sequence 1–5, pilot-bound
bitstream/macro/influence/helper identity, 2016 canonical pairs per frame,
stable public key, FE/KCV PASS, BCH correction 0 and no timeout/overflow.
All 264 selected pairs agreed with pilot 502; none tied; minimum observed
margin 2. Full-pool ties: 85 across five frames.
`R6_TRAIN_505_EVIDENCE_PASS`.

Campaign state is **3/20 valid cold train boots, 0/10 cold holdout boots**.
The board evidence supports a limited three-boot operational smoke result,
not a completed operational requalification. Do not freeze a train mapping,
authorize holdout, label a final release qualified, or infer that earlier
characterization-image cold boots replace missing operational-image boots.
No further cold boot was requested by the operator. If the campaign is later
resumed, 506 is the next unused index, subject to a new separately confirmed
physical power cycle.

## Cold train 506 — campaign resumed, 4/20 valid boots

The operator explicitly resumed R6 qualification and confirmed a separate
cold power cycle for boot 506. The collector programmed the exact
qualification A image and recorded five valid frames at
`reports/puf64_operational_native_campaign/train_ZYNQ-A01_506/`.
Session manifest SHA-256:
`c969166c1050e5d11e392f07a3c4c25e06c2d03395d318b5516502ef49d2f2e7`.
Independent readback verified 5/5 frame hashes, sequence 1–5, 2016
canonical pairs per frame, pilot-bound bitstream/macro/influence/helper
identity, same public key, FE/KCV PASS, BCH correction 0 and no
timeout/overflow. All 264 selected pairs agreed with pilot 502, none tied,
and minimum observed selected margin was 2. Full-pool ties: 78 across
five frames. `R6_TRAIN_506_EVIDENCE_PASS`.

Train progress is now 4/20 valid cold boots; next unused index is 507.
Holdout remains blocked until the full train set is frozen and authorized.

## Cold train 507 — 5/20 valid boots

After the operator confirmed another independent cold power cycle, the
collector programmed qualification A and recorded five valid frames at
`reports/puf64_operational_native_campaign/train_ZYNQ-A01_507/`.
Session manifest SHA-256:
`2618605709b09900cd53121c8c3d4de3937f6cb511966d846e31a328d82b0a08`.
Independent readback verified all frame hashes and sequence 1–5, the same
pilot-bound bitstream/macro/influence/helper identity and public key,
2016 canonical pairs per frame, FE/KCV PASS, BCH correction 0, and no
timeout/overflow. All 264 selected pairs matched pilot 502, with zero
selected ties and minimum selected margin 2. Full-pool ties: 83 across
five frames. `R6_TRAIN_507_EVIDENCE_PASS`. Train progress: 5/20;
next unused index 508. Holdout remains blocked.

## Cold train 508 — 6/20 valid boots

The operator confirmed an independent cold power cycle; qualification A
was programmed and five valid train frames were recorded at
`reports/puf64_operational_native_campaign/train_ZYNQ-A01_508/`.
Session manifest SHA-256:
`5d2b8d445544a0cfe40c84f2b884ea6cf42e366823ce876f40a7f5c85657f7b8`.
Independent readback verified frame hashes and sequence 1–5, pilot-bound
bitstream/macro/influence/helper identity and public key, 2016 canonical
pairs per frame, FE/KCV PASS, BCH correction 0, and no timeout/overflow.
All 264 selected pairs matched pilot 502, zero selected ties, minimum
selected margin 2; full-pool ties: 75 across five frames.
`R6_TRAIN_508_EVIDENCE_PASS`. Train progress: 6/20; next unused index 509.
Holdout remains blocked.

## Cold train 509 — 7/20 valid boots

The operator confirmed a separate cold power cycle. Qualification A was
programmed and five valid train frames were recorded at
`reports/puf64_operational_native_campaign/train_ZYNQ-A01_509/`.
Session manifest SHA-256:
`dcd253d283fca0e8b26e3448a8779c0dae6fa32a82b4a738bdf40e2360f9477d`.
Independent readback verified frame hashes and sequence 1–5, pilot-bound
bitstream/macro/influence/helper identity and public key, 2016 canonical
pairs per frame, FE/KCV PASS, BCH correction 0, and no timeout/overflow.
All 264 selected pairs matched pilot 502, zero selected ties, minimum
selected margin 2; full-pool ties: 71 across five frames.
`R6_TRAIN_509_EVIDENCE_PASS`. Train progress: 7/20; next unused index 510.
Holdout remains blocked.

## Cold train 510 — 8/20 valid boots

The operator confirmed another independent cold power cycle.
Qualification A was programmed and five valid train frames were recorded at
`reports/puf64_operational_native_campaign/train_ZYNQ-A01_510/`.
Session manifest SHA-256:
`39d2285d8518c3ea33bcfbcddfa5223cd20374ac1644e051139b62321580fd59`.
Independent readback verified frame hashes and sequence 1–5, pilot-bound
bitstream/macro/influence/helper identity and public key, 2016 canonical
pairs per frame, FE/KCV PASS, BCH correction 0, and no timeout/overflow.
All 264 selected pairs matched pilot 502, zero selected ties, minimum
selected margin 2; full-pool ties: 82 across five frames.
`R6_TRAIN_510_EVIDENCE_PASS`. Train progress: 8/20; next unused index 511.
Holdout remains blocked.

## Cold train 511 — 9/20 valid boots

The operator confirmed an independent cold power cycle. Qualification A
was programmed and five valid train frames were recorded at
`reports/puf64_operational_native_campaign/train_ZYNQ-A01_511/`.
Session manifest SHA-256:
`3cb807e52c23949e6caa5cad77846efbee61ec63ed96c4559dc0cd3d6bc9aa04`.
Independent readback verified frame hashes and sequence 1–5, pilot-bound
bitstream/macro/influence/helper identity and public key, 2016 canonical
pairs per frame, FE/KCV PASS, BCH correction 0, and no timeout/overflow.
All 264 selected pairs matched pilot 502, zero selected ties, minimum
selected margin 2; full-pool ties: 81 across five frames.
`R6_TRAIN_511_EVIDENCE_PASS`. Train progress: 9/20; next unused index 512.
Holdout remains blocked.

## Cold train 512 — 10/20 valid boots

The operator confirmed an independent cold power cycle. Qualification A
was programmed and five valid train frames were recorded at
`reports/puf64_operational_native_campaign/train_ZYNQ-A01_512/`.
Session manifest SHA-256:
`690cbb1559b5b40e5d4d4fb31546299f852a60c83d00bbd7522fbda3f962b0f1`.
Independent readback verified frame hashes and sequence 1–5, pilot-bound
bitstream/macro/influence/helper identity and public key, 2016 canonical
pairs per frame, FE/KCV PASS, BCH correction 0, and no timeout/overflow.
All 264 selected pairs matched pilot 502, zero selected ties, minimum
selected margin 2; full-pool ties: 79 across five frames.
`R6_TRAIN_512_EVIDENCE_PASS`. Train progress: 10/20; next unused index 513.
Holdout remains blocked.

## Cold train 513 — 11/20 valid boots

The operator confirmed an independent cold power cycle. Qualification A
was programmed and five valid train frames were recorded at
`reports/puf64_operational_native_campaign/train_ZYNQ-A01_513/`.
Session manifest SHA-256:
`0348525eac1c0da3c0da638a7bff16069c12a1e3c7f263e9951caeb4cd074e11`.
Independent readback verified frame hashes and sequence 1–5, pilot-bound
bitstream/macro/influence/helper identity and public key, 2016 canonical
pairs per frame, FE/KCV PASS, BCH correction 0, and no timeout/overflow.
All 264 selected pairs matched pilot 502, zero selected ties, minimum
selected margin 3; full-pool ties: 76 across five frames.
`R6_TRAIN_513_EVIDENCE_PASS`. Train progress: 11/20; next unused index 514.
Holdout remains blocked.

## Cold train 514 — 12/20 valid boots

The operator confirmed an independent cold power cycle. Qualification A
was programmed and five valid train frames were recorded at
`reports/puf64_operational_native_campaign/train_ZYNQ-A01_514/`.
Session manifest SHA-256:
`4f37c27a7ad79e03348a10ef9be4c4db164fec97db7725612fac6c0c99f8a314`.
Independent readback verified frame hashes and sequence 1–5, pilot-bound
bitstream/macro/influence/helper identity and public key, 2016 canonical
pairs per frame, FE/KCV PASS, BCH correction 0, and no timeout/overflow.
All 264 selected pairs matched pilot 502, zero selected ties, minimum
selected margin 2; full-pool ties: 81 across five frames.
`R6_TRAIN_514_EVIDENCE_PASS`. Train progress: 12/20; next unused index 515.
Holdout remains blocked.

## Cold train 515 — 13/20 valid boots

The operator confirmed an independent cold power cycle. Qualification A
was programmed and five valid train frames were recorded at
`reports/puf64_operational_native_campaign/train_ZYNQ-A01_515/`.
Session manifest SHA-256:
`3d7ab2dc6e7ba8c9a0418b03fed8b32b66bb2b0da0cb04d8389b27f07aabfbbe`.
Independent readback verified frame hashes and sequence 1–5, pilot-bound
bitstream/macro/influence/helper identity and public key, 2016 canonical
pairs per frame, FE/KCV PASS, BCH correction 0, and no timeout/overflow.
All 264 selected pairs matched pilot 502, zero selected ties, minimum
selected margin 2; full-pool ties: 77 across five frames.
`R6_TRAIN_515_EVIDENCE_PASS`. Train progress: 13/20; next unused index 516.
Holdout remains blocked.

## Cold train 516 — 14/20 valid boots

The operator confirmed an independent cold power cycle. Qualification A
was programmed and five valid train frames were recorded at
`reports/puf64_operational_native_campaign/train_ZYNQ-A01_516/`.
Session manifest SHA-256:
`d2f54314d802a9ba910449d777b1a8d74163572a584ece6bfc26ee8b550bbb4a`.
Independent readback verified frame hashes and sequence 1–5, pilot-bound
bitstream/macro/influence/helper identity and public key, 2016 canonical
pairs per frame, FE/KCV PASS, BCH correction 0, and no timeout/overflow.
All 264 selected pairs matched pilot 502, zero selected ties, minimum
selected margin 2; full-pool ties: 75 across five frames.
`R6_TRAIN_516_EVIDENCE_PASS`. Train progress: 14/20; next unused index 517.
Holdout remains blocked.

## Cold train 517 — 15/20 valid boots

The operator confirmed an independent cold power cycle. Qualification A
was programmed and five valid train frames were recorded at
`reports/puf64_operational_native_campaign/train_ZYNQ-A01_517/`.
Session manifest SHA-256:
`481b4879bd9e6797000187ec140de0b4f02863bf0f56772c88e09a7e1b4a640b`.
Independent readback verified frame hashes and sequence 1–5, pilot-bound
bitstream/macro/influence/helper identity and public key, 2016 canonical
pairs per frame, FE/KCV PASS, BCH correction 0, and no timeout/overflow.
All 264 selected pairs matched pilot 502, zero selected ties, minimum
selected margin 2; full-pool ties: 86 across five frames.
`R6_TRAIN_517_EVIDENCE_PASS`. Train progress: 15/20; next unused index 518.
Holdout remains blocked.

## Cold train 518 — 16/20 valid boots

The operator confirmed an independent cold power cycle. Qualification A
was programmed and five valid train frames were recorded at
`reports/puf64_operational_native_campaign/train_ZYNQ-A01_518/`.
Session manifest SHA-256:
`99a9032d7e43571053d21123c58e7e2b33f14e9b26b89b3155007fc674d86ba9`.
Independent readback verified frame hashes and sequence 1–5, pilot-bound
bitstream/macro/influence/helper identity and public key, 2016 canonical
pairs per frame, FE/KCV PASS, BCH correction 0, and no timeout/overflow.
All 264 selected pairs matched pilot 502, zero selected ties, minimum
selected margin 2; full-pool ties: 87 across five frames.
`R6_TRAIN_518_EVIDENCE_PASS`. Train progress: 16/20; next unused index 519.
Holdout remains blocked.

## Cold train 519 — 17/20 valid boots

The operator confirmed an independent cold power cycle. Qualification A
was programmed and five valid train frames were recorded at
`reports/puf64_operational_native_campaign/train_ZYNQ-A01_519/`.
Session manifest SHA-256:
`54e59a61220f2d031e6c8e515cb77c5b951d195f5e70393c98aa8c5a0c9e6627`.
Independent readback verified frame hashes and sequence 1–5, pilot-bound
bitstream/macro/influence/helper identity and public key, 2016 canonical
pairs per frame, FE/KCV PASS, BCH correction 0, and no timeout/overflow.
All 264 selected pairs matched pilot 502, zero selected ties, minimum
selected margin 2; full-pool ties: 78 across five frames.
`R6_TRAIN_519_EVIDENCE_PASS`. Train progress: 17/20; next unused index 520.
Holdout remains blocked.

## Cold train 520 — 18/20 valid boots

The operator confirmed an independent cold power cycle. Qualification A
was programmed and five valid train frames were recorded at
`reports/puf64_operational_native_campaign/train_ZYNQ-A01_520/`.
Session manifest SHA-256:
`7cce344b550f0814941550e461ddde441a61cace32a096c6f9f45a25aa20ffe7`.
Independent readback verified frame hashes and sequence 1–5, pilot-bound
bitstream/macro/influence/helper identity and public key, 2016 canonical
pairs per frame, FE/KCV PASS, BCH correction 0, and no timeout/overflow.
All 264 selected pairs matched pilot 502, zero selected ties, minimum
selected margin 2; full-pool ties: 72 across five frames.
`R6_TRAIN_520_EVIDENCE_PASS`. Train progress: 18/20; next unused index 521.
Holdout remains blocked.

## Cold train 521 — 19/20 valid boots

The operator confirmed an independent cold power cycle. Qualification A
was programmed and five valid train frames were recorded at
`reports/puf64_operational_native_campaign/train_ZYNQ-A01_521/`.
Session manifest SHA-256:
`27208ce3e41f5082c4b24b6f790c4a930926f0ebe1b3109ea0c506adbdfa7f5b`.
Independent readback verified frame hashes and sequence 1–5, pilot-bound
bitstream/macro/influence/helper identity and public key, 2016 canonical
pairs per frame, FE/KCV PASS, BCH correction 0, and no timeout/overflow.
All 264 selected pairs matched pilot 502, zero selected ties, minimum
selected margin 2; full-pool ties: 80 across five frames.
`R6_TRAIN_521_EVIDENCE_PASS`. Train progress: 19/20; next unused index 522.
Holdout remains blocked.

## Cold train 522 — 20/20 valid boots; train input frozen

The operator confirmed a separate cold power cycle. Qualification A was
programmed and five valid frames were recorded at
`reports/puf64_operational_native_campaign/train_ZYNQ-A01_522/`.
Session SHA-256:
`fc06ca2e74d5c452afd21c11960c4c195a1affdf1c452597b8bfcc070c6909c9`.
Frame sequence 1–5, all five frame hashes, 2016 pairs/frame, FE/KCV,
stable public key, BCH correction 0, and no pair timeout/overflow passed.
All 264 selected pairs agreed with pilot 502; none tied. Full-pool ties:
78 across five frames. `R6_TRAIN_522_EVIDENCE_PASS`.

The complete train set is boots **503–522**, 20 independently confirmed
cold boots and 100 valid frames. The read-only aggregate audit found
264/264 selected pairs consistent with pilot 502, zero selected ties,
zero BCH correction, one stable public key, 100 distinct result tags,
1586 full-pool tie events, and 80 conservative overrun flags with no lost
frame. Minimum observed selected margin is **2**; three selected pairs
had at least one observed margin below 4. These are measurements, not a
claim that a margin-4 selection threshold was satisfied.

`host/puf64_qual_freeze_train.py` froze the exact pilot/session/frame
hashes to the private, git-ignored
`reports/puf64_operational_native_campaign/train_input_503_522.frozen.json`.
Freeze SHA-256:
`ccd13801478c58043d00c2c294c4609753dbbe006101c3abe93cfba654b9a692`.
A second run revalidated all source hashes and reproduced the same freeze.
State: **`TRAIN_INPUT_FROZEN_HOLDOUT_BLOCKED`**.

The older characterization-image protocol specifies 50 frames per train
boot and a margin criterion for *selecting a new mapping*; this R6
operational campaign used five frames per train boot to test an already
frozen mapping. Therefore, 20/20 PASS does not silently satisfy or waive
the old selection protocol. Before any independent holdout collection,
define and record the R6-specific acceptance rule and frame count. No
holdout or final-board programming is authorized by this freeze alone.

## Holdout gate prepared — authorization only, no new board capture

The R6-specific protocol was fixed before any holdout observation in
`docs/PUF64_R6_OPERATIONAL_HOLDOUT_PROTOCOL_2026-09-23.md`: ten independent
cold boots 601–610, 50 frames each, with selected-vector and E2E gates.
The private selected reference was derived solely from the frozen pilot
and train data. Authorization SHA-256:
`d427524199506f99e06ecdfffafdf2c34e3be1c1a8debe74550aba8377a8bb8f`.
Rerun verified the same SHA. Holdout collector preflight for boot 601 PASS;
wrong index, wrong frame count, and missing operator cold confirmation were
all rejected in negative tests. State: `HOLDOUT_AUTHORIZED_QUAL_IMAGE_ONLY`.
No holdout data or final-image board test has yet been collected.

## Holdout cold boot 601 — 1/10 valid boots

The operator confirmed a separate cold power cycle. The collector
programmed exact qualification A and captured 50/50 frames under
`reports/puf64_operational_native_campaign/holdout_ZYNQ-A01_601/`.
Session SHA-256:
`9375d3365817410f507360c9670faee9f05cdc23958d7bed13f5ee5091e3d70e`.
Independent readback verified all frame hashes, sequence 1–50, 2016
valid pairs per frame, exact authorization/bitstream identity, one stable
public key, 50 distinct result tags, zero FE/KCV failure, zero selected
tie, **zero selected bit errors in all 50 frames**, and BCH correction 0.
Full-pool ties: 770; conservative overrun flags: 49, with no frame gap or
incomplete frame. `R6_HOLDOUT_601_EVIDENCE_PASS`. This is 1/10 cold boots,
not a full holdout PASS; final image remains unprogrammed and NOT READY.

## Holdout cold boot 602 — 2/10 valid boots

The operator confirmed a separate cold power cycle. The collector
programmed exact qualification A (`a9ffce0e...94dc280`) and captured
50/50 frames under
`reports/puf64_operational_native_campaign/holdout_ZYNQ-A01_602/`.
Session SHA-256:
`c1e0cfc112db4c06e442a82e6d34bbc1132917fd90d2cdbe43a5541a6222d820`.
Independent readback verified all 50 frame file hashes match the
session, sequence 1–50, 2016 valid pairs per frame, exact
authorization (`d4275241...b8f`)/bitstream/macro/influence/helper
identity, INFO `4541010171`, one stable public key
(`e0abecde...dac29fa23`), 50 distinct result tags, zero FE/KCV
failure, zero timeout/overflow, zero invalid pairs, zero selected
tie, **zero selected bit errors in all 50 frames**, and BCH
correction 0. Full-pool ties: 769; conservative overrun flags: 49,
with no frame gap or incomplete frame. `R6_HOLDOUT_602_EVIDENCE_PASS`.
This is 2/10 cold boots, not a full holdout PASS; final image remains
unprogrammed and NOT READY. Next unused index is 603, subject to a new
separately confirmed physical power cycle.

## Holdout cold boot 603 — 3/10 valid boots

The operator confirmed a separate cold power cycle. The collector
programmed exact qualification A (`a9ffce0e...94dc280`) and captured
50/50 frames under
`reports/puf64_operational_native_campaign/holdout_ZYNQ-A01_603/`.
Session SHA-256:
`51b67e81cd7bac2d2424e06195c897d149b5cef855c1b470ea83c4b224e7b25a`.
Independent readback verified all 50 frame file hashes match the
session, sequence 1–50, 2016 valid pairs per frame, exact
authorization (`d4275241...b8f`)/bitstream/macro/influence/helper
identity, INFO `4541010171`, one stable public key
(`e0abecde...dac29fa23`), 50 distinct result tags, zero FE/KCV
failure, zero timeout/overflow, zero invalid pairs, zero selected
tie, **zero selected bit errors in all 50 frames**, and BCH
correction 0. Full-pool ties: 809; conservative overrun flags: 49,
with no frame gap or incomplete frame. `R6_HOLDOUT_603_EVIDENCE_PASS`.
This is 3/10 cold boots, not a full holdout PASS; final image remains
unprogrammed and NOT READY. Next unused index is 604, subject to a new
separately confirmed physical power cycle.

## Holdout cold boot 604 — 4/10 valid boots

The operator confirmed a separate cold power cycle. The collector
programmed exact qualification A (`a9ffce0e...94dc280`) and captured
50/50 frames under
`reports/puf64_operational_native_campaign/holdout_ZYNQ-A01_604/`.
Session SHA-256:
`06602c257a3edfe2b94190740cd1adc1351fca01010249377be67f240eebe2c2`.
Independent readback verified all 50 frame file hashes match the
session, sequence 1–50, 2016 valid pairs per frame, exact
authorization (`d4275241...b8f`)/bitstream/macro/influence/helper
identity, INFO `4541010171`, one stable public key
(`e0abecde...dac29fa23`), 50 distinct result tags, zero FE/KCV
failure, zero timeout/overflow, zero invalid pairs, zero selected
tie, **zero selected bit errors in all 50 frames**, and BCH
correction 0. Full-pool ties: 801; conservative overrun flags: 49,
with no frame gap or incomplete frame. `R6_HOLDOUT_604_EVIDENCE_PASS`.
This is 4/10 cold boots, not a full holdout PASS; final image remains
unprogrammed and NOT READY. Next unused index is 605, subject to a new
separately confirmed physical power cycle.

## Holdout cold boot 605 — 5/10 valid boots

The operator confirmed a separate cold power cycle. The collector
programmed exact qualification A (`a9ffce0e...94dc280`) and captured
50/50 frames under
`reports/puf64_operational_native_campaign/holdout_ZYNQ-A01_605/`.
Session SHA-256:
`1ec2ab9668302b82b000acf98d1bbf759a3b6650a65a835f3e060aec44015236`.
Independent readback verified all 50 frame file hashes match the
session, sequence 1–50, 2016 valid pairs per frame, exact
authorization (`d4275241...b8f`)/bitstream/macro/influence/helper
identity, INFO `4541010171`, one stable public key
(`e0abecde...dac29fa23`), 50 distinct result tags, zero FE/KCV
failure, zero timeout/overflow, zero invalid pairs, zero selected
tie, **zero selected bit errors in all 50 frames**, and BCH
correction 0. Full-pool ties: 843; conservative overrun flags: 49,
with no frame gap or incomplete frame. `R6_HOLDOUT_605_EVIDENCE_PASS`.
This is 5/10 cold boots, not a full holdout PASS; final image remains
unprogrammed and NOT READY. Next unused index is 606, subject to a new
separately confirmed physical power cycle.

## Holdout cold boot 606 — 6/10 valid boots

The operator confirmed a separate cold power cycle. The collector
programmed exact qualification A (`a9ffce0e...94dc280`) and captured
50/50 frames under
`reports/puf64_operational_native_campaign/holdout_ZYNQ-A01_606/`.
Session SHA-256:
`37dee6b1fe8175180b3cad1e4cd80ed682ffda84c6eb1b7a9aadce72bf8e87a0`.
Independent readback verified all 50 frame file hashes match the
session, sequence 1–50, 2016 valid pairs per frame, exact
authorization (`d4275241...b8f`)/bitstream/macro/influence/helper
identity, INFO `4541010171`, one stable public key
(`e0abecde...dac29fa23`), 50 distinct result tags, zero FE/KCV
failure, zero timeout/overflow, zero invalid pairs, zero selected
tie, **zero selected bit errors in all 50 frames**, and BCH
correction 0. Full-pool ties: 780; conservative overrun flags: 49,
with no frame gap or incomplete frame. `R6_HOLDOUT_606_EVIDENCE_PASS`.
This is 6/10 cold boots, not a full holdout PASS; final image remains
unprogrammed and NOT READY. Next unused index is 607, subject to a new
separately confirmed physical power cycle.

## Holdout cold boot 607 — 7/10 valid boots

The operator confirmed a separate cold power cycle. The collector
programmed exact qualification A (`a9ffce0e...94dc280`) and captured
50/50 frames under
`reports/puf64_operational_native_campaign/holdout_ZYNQ-A01_607/`.
Session SHA-256:
`4c00f327a49fdd7ca653c38c75fdb19936ab6b29cd6b338b5d850d482081e509`.
Independent readback verified all 50 frame file hashes match the
session, sequence 1–50, 2016 valid pairs per frame, exact
authorization (`d4275241...b8f`)/bitstream/macro/influence/helper
identity, INFO `4541010171`, one stable public key
(`e0abecde...dac29fa23`), 50 distinct result tags, zero FE/KCV
failure, zero timeout/overflow, zero invalid pairs, zero selected
tie, **zero selected bit errors in all 50 frames**, and BCH
correction 0. Full-pool ties: 757; conservative overrun flags: 49,
with no frame gap or incomplete frame. `R6_HOLDOUT_607_EVIDENCE_PASS`.
This is 7/10 cold boots, not a full holdout PASS; final image remains
unprogrammed and NOT READY. Next unused index is 608, subject to a new
separately confirmed physical power cycle.

## Holdout cold boot 608 — 8/10 valid boots

The operator confirmed a separate cold power cycle. The collector
programmed exact qualification A (`a9ffce0e...94dc280`) and captured
50/50 frames under
`reports/puf64_operational_native_campaign/holdout_ZYNQ-A01_608/`.
Session SHA-256:
`e23e7a6718008afc64c92b7b30a58e8a5637d614cb46dcb7116388cae19ef3f8`.
Independent readback verified all 50 frame file hashes match the
session, sequence 1–50, 2016 valid pairs per frame, exact
authorization (`d4275241...b8f`)/bitstream/macro/influence/helper
identity, INFO `4541010171`, one stable public key
(`e0abecde...dac29fa23`), 50 distinct result tags, zero FE/KCV
failure, zero timeout/overflow, zero invalid pairs, zero selected
tie, **zero selected bit errors in all 50 frames**, and BCH
correction 0. Full-pool ties: 765; conservative overrun flags: 49,
with no frame gap or incomplete frame. `R6_HOLDOUT_608_EVIDENCE_PASS`.
This is 8/10 cold boots, not a full holdout PASS; final image remains
unprogrammed and NOT READY. Next unused index is 609, subject to a new
separately confirmed physical power cycle.

## Holdout cold boot 609 — 9/10 valid boots

The operator confirmed a separate cold power cycle. The collector
programmed exact qualification A (`a9ffce0e...94dc280`) and captured
50/50 frames under
`reports/puf64_operational_native_campaign/holdout_ZYNQ-A01_609/`.
Session SHA-256:
`4b1ed670735657d069389f0961f5274acd46bc148719d98b5a77d0a7c3da0353`.
Independent readback verified all 50 frame file hashes match the
session, sequence 1–50, 2016 valid pairs per frame, exact
authorization (`d4275241...b8f`)/bitstream/macro/influence/helper
identity, INFO `4541010171`, one stable public key
(`e0abecde...dac29fa23`), 50 distinct result tags, zero FE/KCV
failure, zero timeout/overflow, zero invalid pairs, zero selected
tie, **zero selected bit errors in all 50 frames**, and BCH
correction 0. Full-pool ties: 770; conservative overrun flags: 49,
with no frame gap or incomplete frame. `R6_HOLDOUT_609_EVIDENCE_PASS`.
This is 9/10 cold boots, not a full holdout PASS; final image remains
unprogrammed and NOT READY. Next unused index is 610, subject to a new
separately confirmed physical power cycle.

## Holdout cold boot 610 — 10/10 valid boots

The operator confirmed a separate cold power cycle. The collector
programmed exact qualification A (`a9ffce0e...94dc280`) and captured
50/50 frames under
`reports/puf64_operational_native_campaign/holdout_ZYNQ-A01_610/`.
Session SHA-256:
`bfccacb38ab58a33c5cc89f12f15e6045e8cdd3e0c7e488b4be38ae6b76597cc`.
Independent readback verified all 50 frame file hashes match the
session, sequence 1–50, 2016 valid pairs per frame, exact
authorization (`d4275241...b8f`)/bitstream/macro/influence/helper
identity, INFO `4541010171`, one stable public key
(`e0abecde...dac29fa23`), 50 distinct result tags, zero FE/KCV
failure, zero timeout/overflow, zero invalid pairs, zero selected
tie, **zero selected bit errors in all 50 frames**, and BCH
correction 0. Full-pool ties: 803; conservative overrun flags: 49,
with no frame gap or incomplete frame. `R6_HOLDOUT_610_EVIDENCE_PASS`.

## Holdout closure — 10/10 PASS on qualification image

Aggregate 601–610: 10/10 valid cold boots, 500/500 valid frames under
the same qual A image/identity; zero FE/KCV failure, one stable public
key (zero mismatch), zero selected tie, zero invalid/timeout/overflow/
count-zero pairs, selected errors total 0 / max-per-frame 0 / p95 0
(gates: no frame >8, no boot-majority >8, p95 <=4), BCH correction max
0 in every frame (gate <=8). Full-pool ties 7867; conservative overrun
flags 490 with no sequence gap or incomplete frame.
`R6_HOLDOUT_601_610_PASS_QUAL_IMAGE_ONLY`.

This closes the R6 operational-image holdout on qualification image A
only. It does not qualify any final/release image by itself: final-image
identity/fingerprint, reproduction, programming and independent
E2E/cold-boot gates remain separate. Limitations: one board
(`ZYNQ-A01`), no PVT/aging campaign; 500 frames cannot prove a true
zero failure rate, inter-device uniqueness, or 256-bit min-entropy.
