# Báo cáo xác minh RC3 — 2026-08-30

Báo cáo ghi kết quả chạy trực tiếp trên worktree phát triển từ commit `6d9218f`.
Mọi tác vụ nặng chạy tuần tự (`-j1`); Vivado dùng một worker và tối đa hai thread.

## Môi trường

- Linux `6.8.0-138-generic`, x86-64
- Verilator `5.050`, revision `v5.050-60-g3d2421f3b`
- Python `3.10.12`
- Vivado `2020.1`, part `xc7z020clg400-2`
- Board JTAG: `xc7z020_1`, Digilent `260515110006`
- UART: `/dev/ttyUSB1`, 115200 8N1

## Regression chức năng

| Bài kiểm tra | Kết quả | Bằng chứng |
|---|---|---|
| RO-PUF controller/CDC | PASS | busy/done, digital model và mid-operation reset |
| BCH fuzzy extractor | PASS | 12/12 gồm clean, max-noise và over-noise reject |
| SHAKE256 KDF KAT | PASS | 24-byte input, 64-byte output khớp `hashlib.shake_256` |
| Kyber-512 functional loopback | PASS | shared key bằng nhau, cycle 15.316 |
| Kyber AXI single-attempt | PASS | 32 giao dịch, raw mismatch 0, max attempts 1 |
| Kyber codec round-trip | PASS | encode Client/decode Server giữ đúng coefficient |
| Kyber raw gate dài | PASS | 1.024/1.024, mismatch 0, recovered 0, max attempts 1 |
| Full firmware/UART pipeline | PASS | 952.496 cycle, không xuất secret, zeroize đạt |
| Standalone audit | PASS | đủ file, không symlink, `.xci` hay dependency source ngoài |
| Internal release check | PASS | regression, gate 1.024 vector, artifact, timing, DRC và provenance |

Lệnh chính:

```sh
make -j1 regression
make -j1 kyber-long
```

## Lỗi được tìm và sửa

Stress với message seed thay đổi từng phát hiện Client state `0x18` và Server
state `0x2f` rời cửa sổ sinh ma trận theo counter cycle trước khi rejection
sampling điền đủ 128 word. NTT state `0x06`, `0x0b` hoặc `0x26` sau đó tăng
counter khi FIFO trống và có thể chờ vô hạn hoặc dùng thiếu coefficient.

RC3 sửa bằng cách:

1. Giữ matrix pattern trong đúng state sinh ma trận.
2. Chỉ kết thúc sau khi `fifo_GENA_ctr[7]` xác nhận đủ dữ liệu.
3. Chỉ tăng NTT coefficient counter khi FIFO không empty.
4. Chờ đủ word thứ 128 trước khi chuyển state.
5. Loại bỏ retry khỏi firmware và testbench để lỗi raw không bị che.

Vector tái hiện trực tiếp và toàn bộ 1.024 vector đều PASS sau sửa.

## Implementation FPGA

| Chỉ số | Kết quả |
|---|---:|
| Clock constraint | 20,000 ns (50 MHz) |
| WNS/TNS | `+4,371 ns` / `0 ns` |
| WHS/THS | `+0,056 ns` / `0 ns` |
| Slice LUT | 51.738/53.200 (`97,25%`) |
| Slice register | 30.546/106.400 (`28,71%`) |
| BRAM tile | 23,5/140 (`16,79%`) |
| DSP | 4/220 (`1,82%`) |
| Failed/unrouted net | 0 |
| DRC error | 0 |

165 warning DRC đã phân loại: 4 `DPOP-2` do DSP NTT chưa pipeline MREG; 32
`LUTLP-2` là vòng RO có chủ ý; 128 `PDCN-1569` là input LUT RO không dùng; một
`ZPS7-1` vì thiết kế pure-PL không instantiate PS7.

## Test phần cứng

Bitstream được nạp volatile, sau đó INFO, enroll và reconstruct đều PASS. Ba run
stress độc lập:

| Run | Pass/Fail | Latency | Throughput |
|---|---:|---:|---:|
| 100 | 100/0 | 28,527 ms | 35,054 giao dịch/s |
| 1.000 | 1.000/0 | 28,458 ms | 35,139 giao dịch/s |
| 10.000 | 10.000/0 | 28,914 ms | 34,585 giao dịch/s |

Run 10.000 kéo dài 289,143 s và không có timeout, protocol error hay key mismatch.

## Artifact

```text
c78724fd9007d21791caf654b8fe8f08a44653bfa028e6a15af80d7425f04d89  Kyber_System_Top.bit
d8774e78d37c8fbc34d799426ce7a0150715569217bb921df3c0c1519348ec8e  firmware/firmware.hex
```

## Phạm vi tiêu chuẩn

KAT hiện tại chứng minh đường KDF SHAKE256 cụ thể khớp FIPS 202 reference. Chưa
có bộ SHA3/SHAKE multi-block đầy đủ. Kyber test không đối chiếu key/ciphertext/
shared secret với vector ML-KEM chính thức, nên không chứng minh FIPS 203 hoặc
FIPS 140-3.

## Kết luận

RC3 đạt cổng kỹ thuật FPGA nội bộ và đủ bằng chứng để bắt đầu nhánh ASIC backend
song song với việc giữ FPGA làm golden reference. Waveform trình bày và video
demo được hoãn. Public release vẫn bị chặn bởi license; production release bị
chặn bởi ML-KEM KAT, qualification PUF nhiều điều kiện và security review.
