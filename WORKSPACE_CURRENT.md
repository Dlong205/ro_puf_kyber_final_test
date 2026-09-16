# Workspace phát triển hiện hành

Từ ngày **2026-09-16**, mọi thay đổi mới của dự án được thực hiện trong thư
mục này. Thư mục `kyber_puf_fpga_delivery` được giữ làm bản đối chiếu và không
tiếp tục sửa nếu chưa có quyết định rõ ràng.

## Mốc bắt đầu

- Nhánh: `codex/fpga-v2-split`.
- Artifact FPGA được chấp nhận: ML-KEM-512 `0.2.0-rc1`.
- Hạng mục mới đầu tiên: count-margin telemetry RO-PUF trên Zynq.
- Báo cáo: `docs/PUF_MARGIN_TELEMETRY_2026-09-16.md`.
- Trạng thái: instrumentation/board PASS; RO-PUF chưa freeze.

## Quy tắc dữ liệu

- Không commit `private_*.json`, helper, raw response, shared secret hoặc dữ
  liệu có thể định danh fingerprint của board.
- Build/cache được tạo lại tại `build/`, `.Xil/` và `sim/*/obj_dir*`; các thư
  mục này không được sao chép từ workspace cũ.
- Bitstream RC1 chuẩn vẫn là `Kyber_System_Top.bit`; ảnh characterization phải
  được build riêng và không được dùng thay artifact release.

## Hướng phát triển kế tiếp

Mở rộng candidate pool RO, loại challenge lặp và chọn cố định 264 vị trí theo
reliability trước khi chạy lại same-root, warm/cold boot, PVT và nhiều board.

