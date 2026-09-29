# Self-review kỹ thuật — release R7 FPGA (solo, không độc lập)

Ngày bắt đầu: 2026-09-29. Người review + implement: cùng 1 người
(Đồng Trường Long) — vì nhóm đã rút. Mọi mục dưới đây vì thế chỉ đạt mức
**self-review**, KHÔNG thay thế review độc lập; viết rõ để không ai ngộ
nhận. Phạm vi: image release R7-B (`ab075bfd...`) + helper R7 trên
`ZYNQ-A01` ở 100 MHz. Mỗi mục: claim → evidence (file/log/SHA) → verdict.

## 1. FIPS 203 — KeyGen mapping (d,z) → (ek,dk)

- Claim: RTL sinh đúng FIPS 203 §7.1 cho ML-KEM-512.
- Evidence: `sim/mlkem` KeyGen **100/100** (25 NIST ACVP tgId=1 + 75
  differential incl. edge, pq-crystals ref `3edd5af`, seed 203), `ek`
  800 B + `dk` 1632 B bit-exact, cycle 4204 cố định.
- Files: `sim/mlkem/mlkem512_keygen_acvp.txt` (100 TC), `mlkem_keygen_main.cpp`.
- Verdict: [x] PASS [ ] FAIL — Ghi chú: Re-run 2026-09-29: 100/100, TCID 1-25 đúng header NIST ACVP tgId=1, cycle 4204 đều. (verify: agent, 2026-09-29)

## 2. FIPS 203 — Encaps (m, ek) → (c, K)

- Claim: đúng FIPS 203 §7.2.
- Evidence: Encaps **100/100** (25 ACVP + 75 differential), ciphertext
  768 B + K 32 B bit-exact, cycle 5985 cố định.
- Verdict: [x] PASS [ ] FAIL — Ghi chú: Re-run 2026-09-29: 100/100, cycle 5985 đều. (verify: agent, 2026-09-29)

## 3. FIPS 203 — Decaps + implicit rejection

- Claim: đúng FIPS 203 §7.3: `c` hợp lệ → K, `c` sai → `J(z||c)`, `equal=0`,
  timing đều 2 nhánh.
- Evidence: Decaps **50/50** valid + **350/350** rejection (7 vị trí
  mutation × 50 block), K/J bit-exact vs pq-crystals + `hashlib.shake_256`,
  cycle 12288 cố định mọi ca.
- Verdict: [x] PASS [ ] FAIL — Ghi chú: Re-run 2026-09-29: 50/50 + 350/350, cycle 12288 đều 2 nhánh. (verify: agent, 2026-09-29)

## 4. FIPS 202 byte-oriented phục vụ ML-KEM

- Claim: SHA3-256/512, SHAKE128/256 đúng, gồm 20 vector NIST CAVP.
- Evidence: `make fips202` **50/50**; KDF SHAKE256 KAT bit-exact
  (`make kdf` PASS 2026-09-29).
- Verdict: [x] PASS [ ] FAIL — Ghi chú: Re-run 2026-09-29: regression 50/50 (54 check PASS, 0 FAIL); KDF KAT PASS trước đó. (verify: agent, 2026-09-29)

## 5. BCH fuzzy extractor + KDF + KCV anchor (tag 0x81B7)

- Claim: reconstruct đúng với helper R7 trên đường final; KCV gate chặn
  helper sai; helper sai/tag sai/CRC sai đều fail-closed.
- Evidence: holdout R7 **500/500 frame 0 lỗi selected**; E2E 3/3 cold boot
  + stress **1000/1000**; negative `0x08/0x03/0x06/0x03` đúng mã.
- Files: `reports/puf64_finalchar_campaign/` (freeze `7af51c09`, sel
  `b1b2b076`, auth `c6842f18`), helper `55bf5588...`, anchor `14edaaed...`.
- Verdict: [x] PASS [ ] FAIL — Ghi chú: Verify 2026-09-29: holdout R7 aggregate 500 frame, total/max lỗi 0/0 từ session.json. (verify: agent, 2026-09-29)

## 6. Scheduler/invariant (single-attempt, no starvation)

- Claim: không retry, không treo/starvation/underflow; tie budget 2 ở
  release; abort fail-closed có mã.
- Evidence: sim scheduler + operational core PASS; board: 0 abort trong
  holdout R7 + stress 1000 (tie budget 8 ở char, 2 ở release);
  Kyber raw gate 1024/1024 (RC1 era, single-attempt).
- Verdict: [x] PASS [ ] FAIL — Ghi chú: Sims PASS; board 0 abort (holdout R7 + stress 1000); raw gate 1024/1024 single-attempt (RC1 era). (verify: agent, 2026-09-29)

## 7. Transport/UART release (INFO/enroll/0x70)

- Claim: INFO `454101010f`, enroll reject `FF 01`, lệnh lạ/`0x70` reject,
  không xuất secret/raw/KCV.
- Evidence: E2E logs `reports/puf64_final_r7_e2e/boot{1,2,3}_e2e.log`
  (3/3 PASS, pk `9311c3c3...` deterministic).
- Verdict: [x] PASS [ ] FAIL — Ghi chú: Verify 2026-09-29: 3 log boot E2E PASS, cùng pk 9311c3c3, enroll/0x70 reject. (verify: agent, 2026-09-29)

## 8. Lifecycle/anchor/zeroize boundary

- Claim: anchor tin cậy R7 đúng manifest; enroll/legacy/diagnostic khóa
  cứng; accelerator zeroize handshake (candidate v4) — boundary KHÔNG gồm
  PicoRV32/bus/SoC-RAM/scan (ghi rõ tin cậy).
- Evidence: static gate PASS 2 mode; lifecycle netlist proof PASS (build);
  anchor `7b13...`→R7 `14edaaed...` provenance trong freeze json.
- Verdict: [x] PASS [ ] FAIL — Ghi chú: Static gate 2 mode PASS; lifecycle netlist proof PASS (build R7); boundary CPU/bus/RAM/scan ghi rõ ngoài phạm vi tin cậy. (verify: agent, 2026-09-29)

## 9. FPGA implementation R7-B

- Claim: route đủ, timing 100 MHz, DRC 0 error, fingerprint macro MATCH,
  A==B reproducibility.
- Evidence: BIT B `ab075bfd...`, WNS `+0,306 ns`/WHS `+0,051 ns`,
  fingerprint 3713 lines MATCH, `repro_A/B`, freeze `4b48deba...`.
- Verdict: [x] PASS [ ] FAIL — Ghi chú: BIT ab075bfd, WNS +0,306/WHS +0,051, fingerprint A==B 3713 lines, freeze 4b48deba. (verify: agent, 2026-09-29)

## 10. Giới hạn đã biết (không phải verdict, phải đọc cùng kết luận)

- 1 board duy nhất, không PVT/aging/entropy liên board.
- Self-review, không độc lập; không formal proof/side-channel/fault-injection.
- Không phải chứng nhận CAVP/FIPS 140-3.

## Kết luận và ký

Ngày ..../..../........ — Người review: ........................
Kết luận: [ ] ĐẠT final FPGA nội bộ (1 board, self-review) [ ] CHƯA ĐẠT
Ghi chú tồn đọng: .....................................................
