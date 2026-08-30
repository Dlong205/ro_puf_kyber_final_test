# Báo cáo test phần cứng RC3 — 2026-08-30

## Kết luận

Ứng viên nội bộ `0.1.0-rc3` đã được build lại từ RTL, nạp lên một board
XC7Z020-2CLG400I và PASS INFO, enroll, reconstruct cùng stress 100, 1.000 và
10.000 giao dịch end-to-end. Tất cả giao dịch Kyber chạy đúng một attempt;
firmware không có retry.

Kết quả giới hạn ở một board, điều kiện phòng và một phiên test. Nhiệt độ/điện
áp không được đo, chưa có chiến dịch power-cycle hay nhiều thiết bị.

## Artifact

- File: `Kyber_System_Top.bit`
- Kích thước: 4.045.676 byte
- SHA-256: `c78724fd9007d21791caf654b8fe8f08a44653bfa028e6a15af80d7425f04d89`
- Firmware SHA-256: `d8774e78d37c8fbc34d799426ce7a0150715569217bb921df3c0c1519348ec8e`
- Part: `xc7z020clg400-2`
- Clock: 50 MHz
- Protocol/capability: 1.2 / `0x06`
- Shared-secret export: tắt

## Implementation

| Chỉ số | Kết quả |
|---|---:|
| WNS/TNS | `+4,371 ns` / `0 ns` |
| WHS/THS | `+0,056 ns` / `0 ns` |
| LUT | 51.738/53.200 (`97,25%`) |
| Register | 30.546/106.400 (`28,71%`) |
| BRAM tile | 23,5/140 (`16,79%`) |
| DSP | 4/220 (`1,82%`) |
| Failed/unrouted/partial net | 0/0/0 |
| DRC error | 0 |
| DRC warning | 165, đã phân loại |

Warning gồm 4 `DPOP-2`, 32 vòng RO `LUTLP-2`, 128 `PDCN-1569` liên quan LUT
RO và một `ZPS7-1` dự kiến cho thiết kế pure-PL.

## Thiết lập board

- JTAG: Digilent `260515110006`
- Vivado device: `xc7z020_1`
- UART: CH340 `/dev/ttyUSB1`, 115200 8N1
- Nạp: volatile PL qua JTAG, không ghi flash
- Helper: enroll mới và lưu ngoài repository

## Xác minh trước khi nạp

- Regression RO-PUF: PASS
- BCH fuzzy extractor: PASS 12/12
- SHAKE256 KDF KAT: PASS
- Kyber functional loopback: PASS
- AXI single-attempt 32 vector: PASS
- Codec round-trip: PASS
- Raw single-attempt 1.024 vector: PASS, mismatch 0
- Full-system UART simulation: PASS, 952.496 cycle
- Standalone/pure RTL audit: PASS

## Kết quả board

| Bài test | Attempt | Pass | Fail | Latency TB | Throughput |
|---|---:|---:|---:|---:|---:|
| INFO | 1 | 1 | 0 | — | — |
| Enroll | 1 | 1 | 0 | — | — |
| Reconstruct smoke | 1 | 1 | 0 | — | — |
| Stress ngắn | 100 | 100 | 0 | 28,527 ms | 35,054/s |
| Stress trung bình | 1.000 | 1.000 | 0 | 28,458 ms | 35,139/s |
| Stress dài | 10.000 | 10.000 | 0 | 28,914 ms | 34,585/s |

Run 10.000 kéo dài 289,143 s, không có UART/protocol error, PUF/FE/KDF timeout,
Kyber timeout hay key mismatch. Lỗi RC2 từng xuất hiện quanh giao dịch 209 không
tái hiện sau sửa handshake/cửa sổ sinh ma trận RC3.

## Phạm vi kết luận

Test chứng minh RC3 hoạt động end-to-end trên board và đáp ứng cổng triển khai
FPGA nội bộ. Nó không chứng minh FIPS 203 ML-KEM-512, không phải chứng nhận FIPS
140-3 và không qualification RO-PUF cho production.

Các bước còn thiếu: nhiều board; cold/warm power-cycle; góc điện áp/nhiệt độ;
aging; entropy/reliability/uniqueness; ML-KEM KAT chính thức; constant-time,
side-channel và fault-injection review. Public release còn bị chặn bởi license.
