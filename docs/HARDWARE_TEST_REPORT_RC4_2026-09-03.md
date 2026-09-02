# Báo cáo test phần cứng RC4 — 2026-09-03

## Kết luận

Ứng viên nội bộ `0.1.0-rc4` đã được build lại sau khi tách backend FPGA/ASIC,
nạp lên một board XC7Z020-2CLG400I và PASS INFO, enroll, reconstruct cùng stress
100, 1.000 và 10.000 giao dịch end-to-end. Không có timeout, protocol error hay
key mismatch; Kyber vẫn chạy đúng một attempt và firmware không retry.

Kết quả giới hạn ở một board, điều kiện phòng và một phiên cấp nguồn. Nhiệt độ,
điện áp, nhiều board và chiến dịch power-cycle chưa được đo.

## Artifact

- File: `Kyber_System_Top.bit`
- Kích thước: 4.045.676 byte
- SHA-256: `bd8153f8ab58f0a704b2f696c54ed1f57d1a31b951d273f547b33926d239f348`
- Firmware SHA-256: `d8774e78d37c8fbc34d799426ce7a0150715569217bb921df3c0c1519348ec8e`
- Part: `xc7z020clg400-2`
- Clock constraint: 20 ns, tương ứng 50 MHz
- Protocol/capability: 1.2 / `0x06`
- Shared-secret export: tắt

## Implementation

| Chỉ số | Kết quả |
|---|---:|
| WNS/TNS | `+3,663 ns` / `0 ns` |
| WHS/THS | `+0,056 ns` / `0 ns` |
| LUT | 51.682/53.200 (`97,15%`) |
| Register | 30.554/106.400 (`28,72%`) |
| BRAM tile | 23,5/140 (`16,79%`) |
| DSP | 4/220 (`1,82%`) |
| Failed/unrouted/partial net | 0/0/0 |
| DRC error | 0 |
| DRC warning | 165, đã phân loại |

Warning DRC gồm 4 `DPOP-2`, 32 vòng RO `LUTLP-2`, 128 `PDCN-1569` liên
quan LUT RO và một `ZPS7-1` do thiết kế pure-PL. Report methodology còn 72
`TIMING-17` critical warning vì hai clock RO vật lý có tần số bất định và không
được khai báo là timing clock, 2 `LUTAR-1`, 4 `TIMING-18` và 32 `TIMING-23`.
Các warning này phải được giữ trong giới hạn kết luận; không được mô tả run là
ASIC/CDC sign-off sạch.

## Kiểm tra portability và netlist

- Full RTL/full-system regression: PASS.
- ASIC-generic elaboration: PASS với `KP_TARGET_ASIC` và macro RO black-box.
- Fuzzy extractor portable: PASS 12/12.
- Multiplier trung lập: PASS 10.004 vector; Vivado infer 4 DSP48E1.
- Netlist RO Xilinx: 128 LUT, 128 feedback net, 128/128 net có
  `ALLOW_COMBINATORIAL_LOOPS`.
- Vivado project: 0 file `.xci`, không dùng IP sinh tự động.

## Thiết lập board

- JTAG: Digilent `260515110006`
- Vivado device: `xc7z020_1`
- UART: CH340 `/dev/ttyUSB1`, 115200 8N1
- Nạp: volatile PL qua JTAG, không ghi QSPI
- Helper: enroll mới và lưu ngoài repository tại thời điểm test

## Kết quả board

| Bài test | Attempt | Pass | Fail | Latency TB | Throughput |
|---|---:|---:|---:|---:|---:|
| INFO | 1 | 1 | 0 | — | — |
| Enroll | 1 | 1 | 0 | — | — |
| Reconstruct smoke | 1 | 1 | 0 | — | — |
| Stress ngắn | 100 | 100 | 0 | 28,647 ms | 34,908/s |
| Stress trung bình | 1.000 | 1.000 | 0 | 29,291 ms | 34,140/s |
| Stress dài | 10.000 | 10.000 | 0 | 29,119 ms | 34,342/s |

Run 10.000 kéo dài 291,188 s. Kết quả xác nhận thay đổi reset/CDC của counter
RO và việc tách backend không làm hỏng pipeline PUF → fuzzy extractor → KDF →
Kyber trên board được thử.

## Phạm vi kết luận

RC4 đủ làm artifact FPGA nội bộ và làm baseline chức năng trước khi bắt đầu
ASIC backend theo PDK. Nó không chứng minh FIPS 203 ML-KEM-512, không phải chứng
nhận FIPS 140-3, không phải ASIC sign-off và không qualification RO-PUF cho
production. Public release vẫn bị chặn bởi license của RTL Kyber và top-level.
