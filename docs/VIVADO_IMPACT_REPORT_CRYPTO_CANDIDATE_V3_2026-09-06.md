# Báo cáo tác động Vivado của crypto candidate v3 — 2026-09-06

## Kết luận

Crypto RTL candidate v3 tại commit
`1dcdad8ccb8c5acda5b11fcf754b2d686818d718` đã **PASS synthesis, placement,
routing, timing, DRC không lỗi và tạo bitstream** trên `xc7z020clg400-2` ở
50 MHz. Audit vật lý xác nhận miền RO vẫn khớp chính xác fingerprint RC1.

Đây là cổng đánh giá tác động FPGA của candidate v3, không phải artifact FPGA
mới. Sau báo cáo implementation này, đúng bitstream trên đã PASS board
regression 10.000/10.000 nhưng không được quảng bá vì AI pre-review phát hiện
blocker zeroization sâu. Bitstream RC1 ở root vẫn là artifact được chấp nhận và
không bị thay đổi. Kết quả này cũng không phải crypto freeze cuối,
qualification PUF hay ASIC sign-off.

## Định danh build

- Source commit: `1dcdad8ccb8c5acda5b11fcf754b2d686818d718`
- Nhánh: `codex/asic-frontend-mlkem512`
- Vivado: 2020.1, build 2902540
- Part/top: `xc7z020clg400-2` / `Kyber_System_Top`
- Clock constraint: 20 ns, 50 MHz
- Xilinx IP sinh tự động: 0 `.xci`, 0 IP instance
- Run cách ly: `build/soc_repro/candidate_v3/`
- Chế độ chạy: tuần tự, một worker

Lệnh tái tạo:

```sh
make -j1 soc-repro-build \
  SOC_REPRO_RUN=candidate_v3 \
  VIVADO=/absolute/path/to/Vivado/2020.1/bin/vivado
```

## Tài nguyên sau route

| Tài nguyên | Đã dùng | Có sẵn | Tỷ lệ |
|---|---:|---:|---:|
| Slice LUT | 49.886 | 53.200 | 93,77% |
| LUT logic | 49.549 | 53.200 | 93,14% |
| LUT memory | 337 | 17.400 | 1,94% |
| Slice register | 30.649 | 106.400 | 28,81% |
| Slice | 13.243 | 13.300 | 99,57% |
| BRAM tile | 25 | 140 | 17,86% |
| DSP48E1 | 4 | 220 | 1,82% |

Thiết kế vẫn fit nhưng số slice đã dùng rất sát giới hạn. Kết quả 50 MHz không
cho phép suy ra 100 MHz hoặc còn đủ chỗ cho thay đổi RTL lớn mà không
implementation lại.

## Timing và routing

| Chỉ số | Kết quả |
|---|---:|
| WNS | +4,732 ns |
| TNS | 0 ns |
| Setup endpoint lỗi | 0 / 84.277 |
| WHS | +0,034 ns |
| THS | 0 ns |
| Hold endpoint lỗi | 0 / 84.277 |
| Routable net hoàn tất | 70.741 / 70.741 |
| Fixed-route net | 128 |
| Net routing error | 0 |

Vivado kết luận `All user specified timing constraints are met` cho constraint
50 MHz.

## DRC và methodology

DRC có 0 Error, 0 Critical Warning và 165 Warning đã biết:

| Rule | Số lượng | Phân loại |
|---|---:|---|
| `DPOP-2` | 4 | DSP NTT chưa dùng output pipeline MREG |
| `LUTLP-2` | 32 | vòng tổ hợp có chủ đích của 32 RO |
| `PDCN-1569` | 128 | pin giữ cấu trúc LUT RO vật lý |
| `ZPS7-1` | 1 | thiết kế pure-PL không dùng PS7 |

Methodology report còn 110 finding: 72 Critical Warning `TIMING-17`, 2
`LUTAR-1`, 4 `TIMING-18` và 32 `TIMING-23`. Các finding này cùng nhóm với
baseline và chủ yếu liên quan clock/vòng RO cùng I/O delay chưa khai báo; vì
vậy không được mô tả toàn build là “zero-warning” hoặc CDC/RDC sign-off.

## Audit physical lock RO

- Placement synthesis: 128/128 LUT RO đúng LOC/BEL và pin-map.
- Post-route: `RO_PHYSICAL_LOCK_AUDIT=PASS`.
- Endpoint cell: 136; fixed net: 128.
- SHA-256 fingerprint:
  `1fbad9f1d1ec3a04560d506979778991311a00e84d3b31c7e8e56596db464c23`.
- Fingerprint candidate khớp byte-for-byte với RC1, `locked_a` và `locked_b`.

Audit này khóa placement/routing giữa các build; nó không thay thế phép đo
reliability, uniqueness, entropy, PVT hoặc nhiều board.

## Artifact và checksum

Candidate bitstream được tạo cục bộ, chưa track/quảng bá:

- Kích thước: 4.045.676 byte.
- SHA-256:
  `b9f40dce606bcd429b5a97a123df1169e33c7ceca64ec901392651c60b4fa61e`.

Các report cách ly:

| Report | SHA-256 |
|---|---|
| Post-synth utilization | `55b10f0dd01d3c7e0875c5ab36d9adbe687a7e991ed3067140cc241595ce6927` |
| Post-route utilization | `0359828e2aee4e749fb543b96136423b55349f67729ad1f38213392afb14e5da` |
| Post-route timing | `ec5d4f2c412a5abe1bd483ec2ec219da9a1fb9bf91500c02e72d2f9c4732755c` |
| Route status | `f29a4db77a4c8044ecaada04a56dfdf759a400e3046debbea28e26e4a8e7ecd3` |
| DRC | `17dcbf40b12150dd8ea6f28b4e5d5e09a77da25fb9deffc7b05e0391ab3cb615` |
| Methodology | `4c7fac7af671e0f7982233fede6ceacea6863b7a657e0545ae10aab738829e9d` |

Root `Kyber_System_Top.bit` vẫn có SHA-256
`183e0af367376ebd7ca6bc2f3747314fd0602306a630af2a2e51858ef1f20e8e`,
đúng artifact `fpga-mlkem512-0.2.0-rc1`.

## So sánh với artifact RC1

| Chỉ số | RC1 | Candidate v3 | Delta |
|---|---:|---:|---:|
| Slice LUT | 49.909 | 49.886 | -23 |
| Slice register | 30.649 | 30.649 | 0 |
| BRAM tile | 25 | 25 | 0 |
| DSP | 4 | 4 | 0 |
| WNS | +2,226 ns | +4,732 ns | +2,506 ns |
| WHS | +0,034 ns | +0,034 ns | 0 ns |
| Routable net | 70.739 | 70.741 | +2 |
| RO fingerprint | RC1 golden | Khớp RC1 | Không đổi |

Bitstream khác RC1 là bình thường vì source tích hợp đã thay đổi; do đó không
được dùng kết quả board RC1 để gắn nhãn PASS board cho candidate v3.

Đúng bitstream candidate có hash nêu trên sau đó đã PASS INFO,
enroll/reconstruct và stress 100/100, 1.000/1.000, 10.000/10.000. Xem
[`HARDWARE_TEST_REPORT_CRYPTO_CANDIDATE_V3_2026-09-06.md`](HARDWARE_TEST_REPORT_CRYPTO_CANDIDATE_V3_2026-09-06.md).

## Cổng còn lại

1. Sửa P0 secure-zeroize được AI pre-review phát hiện: scrub NTT/FIFO RAM,
   sponge state, khóa FE và seed KDF; bổ sung handshake và test trực tiếp.
2. Sau thay đổi RTL, tạo candidate mới và chạy lại full gate, Vivado/board nếu
   ảnh FPGA đổi. Candidate v3 không được promote dù board regression đã PASS.
3. Hoàn tất review độc lập serialization, implicit rejection, reset và
   zeroization trước crypto freeze cuối.
4. Tiếp tục đóng các đầu vào ASIC: PDK/library, memory mapping, macro RO,
   SDC/CDC/RDC, DFT và security findings.
