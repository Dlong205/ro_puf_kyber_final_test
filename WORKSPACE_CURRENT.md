# Workspace phát triển hiện hành

Từ ngày **2026-09-16**, mọi thay đổi mới của dự án được thực hiện trong thư
mục này. Thư mục `kyber_puf_fpga_delivery` được giữ làm bản đối chiếu và không
tiếp tục sửa nếu chưa có quyết định rõ ràng.

## Mốc bắt đầu

- Nhánh: `codex/fpga-v2-split` (HEAD `103e5e1`; worktree 14 modified + 131
  untracked, chưa commit — không commit khi chưa review).
- Artifact FPGA được chấp nhận: ML-KEM-512 `0.2.0-rc1`.
- Hạng mục 1: count-margin telemetry RO-PUF trên Zynq — PASS.
- Hạng mục 2: candidate pool toàn bộ 496 cặp — RTL/Vivado/board PASS.
- Hạng mục 3 (2026-09-24/25): R6 holdout qual image A — **10/10 PASS**
  (pilot 502, train 503–522 frozen, holdout 601–610, 500/500 frame,
  0 lỗi selected, BCH 0). Xem `docs/PUF64_R6_COLD_RESUME_2026-09-23.md`.
- Hạng mục 4 (2026-09-25): final plain rebuild C/D sạch (WNS +0,263 ns,
  fingerprint MATCH C==D) nhưng **board FAIL `0x32` BCH systematic** —
  BLOCKED, chờ quyết định vehicle. Image diagnostic G bench-only, không freeze.
- Hạng mục 5 (2026-09-28/29): **R7 RELEASED** — char campaign (pilot 703 +
  train 704–723 + holdout 801–810, 500 frame 0 lỗi), mapping `0x81B7`,
  release pair A/B MATCH (WNS +0,306 ns), formal E2E 3/3 cold boot PASS
  (pk `9311c3c3...`), freeze `R7_RELEASE_FREEZE.json`. BIT release là B
  (`ab075bfd...`). Xem `docs/PUF64_R7_FINALCHAR_2026-09-29.md`.
- Báo cáo mới nhất: `docs/PUF64_R7_FINALCHAR_2026-09-29.md` (release closure).
- Trạng thái: mapping R7 đã freeze + holdout-qualify; release R7 E2E PASS;
  board hiện giữ image R7-B (volatile); còn mở review độc lập,
  multi-board/PVT, license.

## Quy tắc dữ liệu

- Không commit `private_*.json`, helper, raw response, shared secret hoặc dữ
  liệu có thể định danh fingerprint của board.
- Build/cache được tạo lại tại `build/`, `.Xil/` và `sim/*/obj_dir*`; các thư
  mục này không được sao chép từ workspace cũ.
- Bitstream RC1 chuẩn vẫn là `Kyber_System_Top.bit`; ảnh characterization phải
  được build riêng và không được dùng thay artifact release.

## Hướng phát triển kế tiếp

Review độc lập crypto/zeroize, multi-board/PVT/aging cho mapping R7,
threat model CPU/bus/scan, PDK/macro ASIC và các gate license trước
public/production release. Dọn + commit worktree theo đợt có review.
