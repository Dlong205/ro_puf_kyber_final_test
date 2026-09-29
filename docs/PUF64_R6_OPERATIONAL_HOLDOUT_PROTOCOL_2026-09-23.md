# R6 operational-image holdout protocol — frozen before collection

Status: `HOLDOUT_AUTHORIZED_QUAL_IMAGE_ONLY`; final/release image remains
`NOT READY`. This is **not** a new RO-pair selection exercise. The gen1
264-pair mapping and helper/anchor are unchanged. Pilot 502 and train
503–522 were collected under qualification image A; boot 501 is excluded
because its raw evidence is unavailable.

## Locked input and image

- Board: `ZYNQ-A01`; qualification INFO: `4541010171`.
- Exact qualification A bitstream SHA-256:
  `a9ffce0e3cb23c894c99e45c27aebc1770a24c505da35ea0eac27315194dc280`.
- Train-input freeze SHA-256:
  `ccd13801478c58043d00c2c294c4609753dbbe006101c3abe93cfba654b9a692`.
- Private authorization/reference SHA-256:
  `d427524199506f99e06ecdfffafdf2c34e3be1c1a8debe74550aba8377a8bb8f`.
- The selected reference is the unanimous pilot/training sign of each
  frozen gen1 pair. It is private device-response material, stored only in
  the git-ignored authorization JSON. Pilot and train agree 264/264; zero
  selected ties or bit flips. Train observed minimum margin 2; three
  selected pairs dipped below 4. This does not meet the old *new-mapping
  selection* margin criterion and makes the holdout particularly important.

## Independent holdout plan

- Exactly 10 distinct cold boots, indices **601–610**, each with **50
  fresh frames** (500 frames total). One boot is one independent complete
  power removal; 50 frames within it are not 50 cold boots.
- For each boot, disconnect all board supply/back-power, wait until LEDs
  extinguish and at least 10 seconds, then power on. Only after operator
  confirmation may the tool program qualification A (JTAG image does not
  survive power-off).
- The collector reserves the boot index before programming. On any
  interrupted/CRC-invalid/incomplete attempt, quarantine that index and
  use a new, explicitly authorized replacement index; never reuse it.
- Check exact bitstream/macro/influence/helper identity, A/B physical gate,
  INFO, disabled enrollment, per-frame sequence and CRC, canonical 2016
  records, pair validity, nonzero counts, timeout/overflow, FE/KCV, public
  key, BCH correction and selected-vector error count. The telemetry
  `overrun` flag may be conservative, but no sequence gap or incomplete
  frame is permitted.

## Predeclared acceptance gate

PASS requires 10/10 valid cold boots and 500/500 valid frames under the
same image/identity; zero FE/KCV failure, zero public-key mismatch, zero
selected tie, zero invalid/timeout/overflow/count-zero pair, no selected
frame with more than 8 bit errors relative to the locked train reference,
no boot-majority with more than 8 errors, P95 selected errors <=4, and
BCH correction <=8 in every frame. Any violation is a holdout FAIL, not a
reason to reselect pairs or edit the reference using holdout data.

The private authorization is generated and checked by
`host/puf64_qual_authorize_holdout.py`. The collector requires a successful
recheck before each holdout boot and records its SHA in the attempt/session.
Neither this authorization nor a subsequent holdout PASS qualifies the
final image by itself: final-image identity/fingerprint, reproduction,
programming and independent E2E/cold-boot gates remain separate.

Limitations: one board, no PVT/aging campaign; 500 observed frames cannot
prove a true zero failure rate, inter-device uniqueness, or 256-bit
min-entropy.
