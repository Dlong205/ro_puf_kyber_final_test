# Workspace ASIC — RO-PUF + ML-KEM-512

Thư mục này chứa đầu vào và các cổng kiểm tra dành riêng cho ASIC. Baseline
FPGA/tag/bitstream ở root không bị thay thế bởi kết quả trong đây.

## Trạng thái hiện tại

- Đã có top digital ASIC `Kyber_System_Asic_Top` với `clk_i/rst_ni`; reset được
  assert bất đồng bộ và release đồng bộ, không dùng power-up value kiểu FPGA.
- Đã có ba filelist tường minh cho full system, ML-KEM accelerator và FIPS 202,
  cùng danh sách header; gate cấm dependency Verilator tự nạp ngoài danh sách.
- Source ASIC loại `LUT6_L`, `CARRY4`, DSP48 primitive và các file legacy.
- Full top đã elaborate bằng Verilator; lỗi multiple-driver trong FIFO wrapper
  được phát hiện và sửa.
- Candidate v4 thêm reset thật cho BCH và crypto-accelerator zeroize xuyên
  PUF/FE/KDF/ML-KEM; full offline freeze gate, Vivado 50 MHz và đúng-image
  board stress 10.000/10.000 PASS.
- Chưa có PDK, standard-cell/memory/pad library, RO macro vật lý, SDC sign-off,
  OpenROAD/STA/KLayout hay commercial backend tool trên máy hiện tại.

Vì vậy đây là **ASIC front-end đang triển khai**, chưa phải handoff GDS/sign-off.
Zeroize hiện không bao gồm PicoRV32, SoC RAM/bus hay scan/DFT; macro memory thật
vẫn phải giữ scrub contract và được kiểm chứng lại. Candidate v4 chưa được
freeze vì review độc lập còn mở; artifact/report ở root vẫn thuộc RC1.

## Lệnh nhẹ, chạy tuần tự

```sh
make -j1 asic-filelist-check
make -j1 asic-frontend-check
```

Log sinh ra ở `build/asic_frontend/` và không được commit. Không chạy nhiều job
Verilator/Vivado/backend đồng thời trên máy phát triển hiện tại.

## Cấu trúc

- `filelists/`: source compile theo từng top.
- `constraints/`: constraint khởi đầu, chưa phải SDC sign-off.
- `docs/`: đặc tả, threat model, clock/reset/CDC, memory và findings.
- `manifests/`: checksum của đúng source và header thuộc dependency closure ASIC.

Lộ trình tổng thể nằm tại
[`../docs/KE_HOACH_HOAN_THIEN_ASIC.md`](../docs/KE_HOACH_HOAN_THIEN_ASIC.md).
