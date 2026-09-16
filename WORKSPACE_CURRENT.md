# Workspace phát triển hiện hành

Từ ngày **2026-09-16**, mọi thay đổi mới của dự án được thực hiện trong thư
mục này. Thư mục `kyber_puf_fpga_delivery` được giữ làm bản đối chiếu và không
tiếp tục sửa nếu chưa có quyết định rõ ràng.

## Mốc bắt đầu

- Nhánh: `codex/fpga-v2-split`.
- Artifact FPGA được chấp nhận: ML-KEM-512 `0.2.0-rc1`.
- Hạng mục 1: count-margin telemetry RO-PUF trên Zynq — PASS.
- Hạng mục 2: candidate pool toàn bộ 496 cặp — RTL/Vivado/board PASS.
- Báo cáo mới nhất: `docs/PUF_ALLPAIRS_CHARACTERIZATION_2026-09-16.md`.
- Trạng thái: đủ candidate pool để chọn N=264; mapping chưa freeze.

## Quy tắc dữ liệu

- Không commit `private_*.json`, helper, raw response, shared secret hoặc dữ
  liệu có thể định danh fingerprint của board.
- Build/cache được tạo lại tại `build/`, `.Xil/` và `sim/*/obj_dir*`; các thư
  mục này không được sao chép từ workspace cũ.
- Bitstream RC1 chuẩn vẫn là `Kyber_System_Top.bit`; ảnh characterization phải
  được build riêng và không được dùng thay artifact release.

## Hướng phát triển kế tiếp

Thu thập nhiều board/PVT, chọn mapping 264 cặp bằng train/holdout và định danh
mapping bằng version/hash trước khi chạy same-root/BCH trên đường tích hợp.
