# PUF64 I5 final timing closure: ML-KEM hash reset retimed (2026-09-21)

Date: 2026-09-21. Commit: `103e5e1` (`feat(puf64): add I4.1 operational
preservation shell`). Worktree CHANGED: `rtl/kyber/ref/Kyber_Server.v`
(+8/-4) and `rtl/top/Edge_Puf64_Zynq_Operational_Final_100MHz_Top.sv`
(untracked; +KEEP_HIERARCHY/DONT_TOUCH on `u_kcv_anchor`). NOT committed.

Target: final single-clock operational build WNS >= +0.1 ns at 100 MHz.

## Problem

`build_puf64_operational_final.tcl` attempt 5 (route `AggressiveExplore`
only) left WNS -0.007 ns: 5 endpoints on the 1600-bit synchronous clear of
the ML-KEM server hash sponge (`squeeze_reg[*]/R`), driven through a long
combinational cone

  `ofifo0 rd_ptr -> full-compare -> next_state -> keccak_init_hard ->
   hard_init -> init_clears -> squeeze_reg[*]/R`

with `squeeze_reg_reg[0]_3[0]` FO=1600 (pin_count 1601). Router/directive
roulette was off the table per plan; targeted minimal RTL shell fix chosen.

## Fix (Kyber_Server.v, states around the final KDF)

- One-cycle buffer state `6'h32` between `6'h30` (NTT_finish complete) and
  the final-KDF absorb state `6'h09`:
  `6'h30: next_state = NTT_finish ? 6'h32 : state;` and
  `6'h32: next_state = 6'h9;` (state 0x32 was unused and unreachable by the
  default `state+5'h1` arc: 0x2f->0x30, 0x30->0x32, 0x32->0x09).
- `keccak_init` now asserted only from the pure registered-state decode
  `6'h32 : keccak_init = 1'h1` (replaces `6'h30 : (next_state != state)`).
- `keccak_init_hard` becomes `(state==6'h1)||(state==6'h1a)||(state==6'h22)||
  (state==6'h32)` — the 1600-bit clear source is now a state-register
  decode, one cycle before state 7/9 writes K-bar/z, keeping `keccak_init`
  and `keccak_init_hard` cycle-aligned in the buffer state.
- Buffer state writes nothing: no IFIFO write, no fresh absorb, `extend=0`,
  `ofifo_ena` stays low (still 0 from state 0x30), `ififo_mode_n` resolves
  to 2'h1 for the 0x32->0x09 transition. `j_replay_ctr` reset held. One
  extra cycle per decap (final KDF) — no functional change.

## Simulation gates (PASS, pre-build)

- `make -C sim/kyber kat` (accepted ct): `K_server==K_client`,
  `decap equal=1` — KAT match.
- `make -C sim/kyber kat-invalid` (rejected ct): `decap equal=0`,
  `J(z||c) PASS`.
- `make -C sim/mlkem all` (ACVP): KeyGen 25/25 ek/dk bit-exact,
  Encaps 25/25 ct/K bit-exact, Decaps 25/25 valid + 175/175 implicit
  rejection K/J exact; all cycle-count identical to the frozen references.

## Lifecycle-gate discovery (not caused by the Kyber fix)

`final_audit_lifecycle` gates on `u_kcv_anchor` existing exactly once. With
`DIAGNOSTIC=0` all anchor outputs are build-time constants, so synthesis
constant-folded the whole cell (synth and routed DCPs: 0 matches). This gate
was never reached before (every prior attempt failed the timing gate first).

Fix: `(* KEEP_HIERARCHY = "yes" *) (* DONT_TOUCH = "yes" *)` on the
`u_kcv_anchor` instance in the FINAL top (anchor RTL and ROM untouched).
KEEP_HIERARCHY alone was insufficient (folded during opt); DONT_TOUCH
preserved the cell. Netlist proof then passes:
`provision/ref/valid` LOW, diagnostics trimmed, `trusted_kcv_valid`
HIGH-equivalent, enroll trimmed.

## Builds

`scripts/build_puf64_operational_final.tcl` (Vivado 2020.1,
Default/Default/PhysOpt Default/AggressiveRouteOnly), commit `103e5e1`:

| build | outcome | notes |
| --- | --- | --- |
| A (gate-validation, 2026-09-21 ~01:0x) | TIMING PASS, lifecycle FAIL (anchor folded) | first full reach of lifecycle gate |
| B (after KEEP_HIERARCHY) | TIMING PASS, lifecycle FAIL (anchor still folded) | KEEP alone insufficient |
| C (after +DONT_TOUCH) | TIMING PASS, lifecycle PASS, fingerprint MATCH | first clean |
| C2 (rebuild A) | identical clean | WNS +0.432 |
| C3 (rebuild B) | identical clean | WNS +0.432 |

Clean builds (post-route, all gates):

- Route: `FINAL_ROUTE_STATUS=PASS` (no partial/unrouted/RTSTAT/conflict).
- Timing @ 100 MHz: `FINAL_TIMING_100MHZ=PASS`;
  `clk_sys_100mhz` WNS **+0.432 ns**, TNS 0.000, 0 failing / 89544
  endpoints; WHS +0.028; WPWS +3.870.
- Single clock: only `clk_in_50mhz`, `clk_sys_100mhz`, `clk_feedback_raw`,
  `clk_100_raw`; `macro_clk` absent post-impl and in timing report.
- Macro: `R2_MACRO_FINGERPRINT_MATCH(final)` (frozen macro `bd0cd620…`
  RO/presc/ripple LOC/BEL/routes/ports untouched).
- Lifecycle: `FINAL_LIFECYCLE_NETLIST_PROOF_PASS` (u_kcv_anchor present).
- Bitstream SHAs: C `2f85a5f5…`, C2(A) `0468a268…`, C3(B) `f179be55…`.
  DCP SHA `7fbc568c…` (final routed DCP).

## Netlist proof of the retiming

In the C3 routed DCP, the 1600-bit sponge clear net
`…/server/hash/sponge/squeeze_reg_reg[0]_3[0]` (1600 FDRE `/R` + 1 load) has
parent net `u_control/u_scrub/state_reg[2]_2[0]`, driven by the mlkem
control FSM `u_scrub` — a registered state decode, not the FIFO/full-compare
chain. 1600-bit `squeeze_reg[*]/R` fanout now sits one LUT after a state
register (the required registered-state-decode property).

## Gates remaining before board program (per plan)

All gates PASS: route-complete, timing >= +0.1 ns (WNS +0.432), fingerprint
match, lifecycle netlist proof, sim/KAT/ACVP. Two clean builds A/B complete
(from the same commit + Vivado 2020.1). No board programming has been done.
No commit/push/reset/clean performed (final summary report deliverable).

## Supersession note (2026-09-25) — C/C2/C3 DO NOT USE on board

The C/C2/C3 builds above carry the stale transport default
`HREC_MAPPING_TAG = 0xD501` in `uart_v2` and floating chain-status ports.
Board program of this generation FAILs every positive SESSION with record
status 6 (`0x06`, mapping reject) against the frozen `0x81B5` helper —
proven on `xc7z020_1` with `f9f14c24...`. Use rebuilds C/D (2026-09-25,
tag fix + wired status, WNS `+0,263 ns`, fingerprint C==D) or later.
Repro archives `repro_A/B` under `reports/puf64_operational_final/` are
kept as evidence of the bug, not as usable images. Even the fixed plain
final fails board with `0x32` BCH systematic (see `PROJECT_STATUS.md`
checkpoint 2026-09-25); vehicle decision still pending.