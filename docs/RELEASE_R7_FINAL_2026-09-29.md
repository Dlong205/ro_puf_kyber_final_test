# Release notes — FPGA R7 final (internal, single-board)

Tag: `fpga-r7-final` trên nhánh `codex/fpga-v2-split`.
Ngày: 2026-09-29. Trạng thái: final FPGA nội bộ (1 board `ZYNQ-A01`,
self-review). KHÔNG phải chứng nhận CAVP/FIPS 140-3, KHÔNG public/production.

## Bộ artifact (byte-exact, SHA-256)

| Thành phần | SHA-256 (đầu) | Vị trí |
|---|---|---|
| BIT release (B) | `ab075bfd...` | `reports/puf64_operational_final_r7/repro_B/final_r7_B.bit` |
| BIT dự phòng (A) | `bfbff188...` | `reports/puf64_operational_final_r7/repro_A/Edge_...Top.bit` |
| Fingerprint macro | MATCH 3713 dòng | `repro_{A,B}/final_r7_fingerprint.tsv` |
| Freeze manifest | `4b48deba...` | `reports/puf64_operational_final_r7/R7_RELEASE_FREEZE.json` |
| Helper R7 (private, theo board) | `55bf5588...` | `reports/puf64_finalchar_campaign/r7_helper.record` (git-ignored) |
| Anchor R7 (private) | KCV `14edaaed...` | `reports/puf64_finalchar_campaign/r7_anchor.json` (git-ignored) |
| Mapping R7 (tag `0x81B7`) | sel `b1b2b076...` | `rtl/puf/v2_mapping_r7/`, `constraints/puf64_r7_mapping_manifest.json` |

Root `Kyber_System_Top.bit` (RC1) giữ nguyên làm baseline đối chiếu;
release R7 sống ở tag này + build dir riêng, không trộn lẫn.

## Tái lập từ source (đã verify)

```sh
git checkout fpga-r7-final
make -j1 -C sim/mlkem all        # 100/100/50+350 FIPS 203 functional
PUF64_MAPPING_R7=1 make ...      # create+build release (xem docs/PUF64_R7_FINALCHAR_2026-09-29.md)
python3 scripts/check_operational_final_static.py
PUF64_MAPPING_R7=1 python3 scripts/check_operational_final_static.py
```

## Nạp + kiểm tra board (ZYNQ-A01)

```sh
# 1. Nạp đúng SHA (sai 1 ký tự là từ chối)
vivado -mode batch -nolog -nojournal \
  -source scripts/program_puf64_operational_final_r7.tcl \
  -tclargs ab075bfbd28b5d8e0a18f0a9bfba0bdfeb6ee1dec1dbea0bd381b41a7cba4dea
# 2. E2E (helper/anchor của đúng board này, tag 0x81B7)
python3 host/puf64_operational_final_e2e.py \
  --helper reports/puf64_finalchar_campaign/r7_helper.record \
  --anchor reports/puf64_finalchar_campaign/r7_anchor.json \
  --mapping-tag 0x81B7
# Kỳ vọng: INFO 454101010f, enroll/0x70 reject, 3 positive pk 9311c3c3...,
# 4 negative fail-closed, OPERATIONAL_FINAL_E2E_PASS
# 3. Stress: python3 host/puf64_r7_stress.py --count 1000  (đã PASS 1000/1000)
```

Helper/anchor là private theo từng board + lần enroll: KHÔNG copy helper
board này sang board khác; board mới phải enroll + qualify lại.

## Đã kiểm chứng

- Sim: FIPS 202 50/50, ML-KEM 100/100/50+350, scheduler/operational/enroll.
- Board: holdout R6 10/10 (qual) + R7 10/10 (500 frame 0 lỗi),
  formal E2E 3/3 cold boot, stress 1000/1000.
- Vivado 100 MHz: WNS +0,306/WHS +0,051, route đủ, DRC 0 error,
  fingerprint A==B, lifecycle proof.
- Self-review 9/9 PASS (`docs/SELF_REVIEW_R7_2026-09-29.md`, solo).

## Giới hạn đã biết (đọc trước khi dùng)

1 board duy nhất, không PVT/aging/entropy liên board; self-review không
độc lập; không formal/side-channel/fault-injection proof; boundary tin cậy
loại trừ CPU/bus/SoC-RAM/scan (xem SECURITY.md liên quan).
Mọi claim ngoài phạm vi trên đều không có giá trị.
