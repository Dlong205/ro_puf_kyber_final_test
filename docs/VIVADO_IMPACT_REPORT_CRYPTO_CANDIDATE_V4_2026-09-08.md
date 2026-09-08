# Báo cáo Vivado crypto candidate v4 — 2026-09-08

## Kết luận

Crypto candidate v4 tại commit
`5943cebd79738c12e21dbe79210ff821d1776d78` đã **PASS synthesis,
placement, routing, timing, DRC không lỗi, tạo bitstream và audit khóa vật lý
RO** trên `xc7z020clg400-2` ở 50 MHz. Build chạy cách ly, một worker, không có
XCI/IP sinh tự động và không thay đổi artifact RC1 ở root.

Một lần implementation trước bản sửa đã dừng đúng tại `UTLZ-1`: mẫu scrub có
hai địa chỉ ghi cú pháp làm Vivado giải thể RAM Kyber thành FF/LUTRAM, khiến
post-synth tăng lên 242.665 LUT. Commit trên mux scrub/normal trước một câu
lệnh ghi duy nhất cho mỗi cổng RAM. Vivado sau đó nhận các biến thể
`generic_bram` là true-dual-port RAM và ánh xạ lại FIFO/RAM crypto vào BRAM.

## Định danh build

- Nhánh: `codex/asic-frontend-mlkem512`
- Run: `build/soc_repro/candidate_v4_final/`
- Vivado: 2020.1, build 2902540
- Part/top: `xc7z020clg400-2` / `Kyber_System_Top`
- Clock constraint: 20 ns, 50 MHz
- Lệnh: `make -j1 soc-repro-build SOC_REPRO_RUN=candidate_v4_final ...`

## Tài nguyên

| Tài nguyên | Post-synth | Post-route | Có sẵn | Post-route |
|---|---:|---:|---:|---:|
| Slice LUT | 51.561 | 50.902 | 53.200 | 95,68% |
| LUT logic | — | 50.458 | 53.200 | 94,85% |
| LUT memory | — | 444 | 17.400 | 2,55% |
| Slice register | 30.958 | 30.958 | 106.400 | 29,10% |
| Slice | — | 13.283 | 13.300 | 99,87% |
| BRAM tile | 30,5 | 30,5 | 140 | 21,79% |
| DSP48E1 | 4 | 4 | 220 | 1,82% |

Thiết kế chỉ còn 17 slice chưa dùng. Candidate v4 đạt 50 MHz nhưng **không có
margin placement cho thay đổi RTL đáng kể**, và kết quả này không suy ra khả
năng chạy 100 MHz. Mọi thay đổi phải chạy lại full implementation.

## Timing và routing cuối

| Chỉ số | Kết quả |
|---|---:|
| WNS / TNS | +3,268 ns / 0 ns |
| Setup endpoint lỗi | 0 / 90.240 |
| WHS / THS | +0,037 ns / 0 ns |
| Hold endpoint lỗi | 0 / 90.240 |
| Routable net hoàn tất | 72.468 / 72.468 |
| Fixed-route net | 128 |
| Net routing error | 0 |

Vivado kết luận `All user specified timing constraints are met`.

## DRC và methodology

DRC có 0 Error, 0 Critical Warning và 165 Warning đã phân loại:

| Rule | Số lượng | Lý do |
|---|---:|---|
| `DPOP-2` | 4 | DSP NTT chưa dùng MREG; timing 50 MHz vẫn đạt |
| `LUTLP-2` | 32 | 32 vòng RO có chủ đích và đã constraint |
| `PDCN-1569` | 128 | pin LUT được giữ cho cấu trúc/route RO |
| `ZPS7-1` | 1 | pure-PL, không dùng PS7 |

Methodology có 111 finding: 72 `TIMING-17`, 3 `LUTAR-1`, 4 `TIMING-18` và
32 `TIMING-23`. Chúng chủ yếu thuộc clock/vòng RO bất định và I/O delay; không
được diễn giải là zero-warning hoặc CDC/RDC sign-off.

## Khóa vật lý RO

- Synthesis placement: 128 LUT, 256 thuộc tính LOC/BEL PASS.
- Post-route: 136 endpoint cell và 128 fixed route PASS.
- Candidate v3 và v4 tái lập cùng implementation vật lý RO.
- Fingerprint khớp byte-for-byte baseline RC1, SHA-256:
  `1fbad9f1d1ec3a04560d506979778991311a00e84d3b31c7e8e56596db464c23`.

Khóa route kiểm soát tính tái lập implementation, không thay thế qualification
reliability/entropy/PVT/nhiều board.

## Artifact và checksum

| Artifact/report | SHA-256 |
|---|---|
| Candidate v4 bitstream (4.045.676 byte) | `bc3a8ab8cac94c00ad3f02f5c3165ff9f8bbacf13db7ba0952003bb90946260a` |
| Routed DCP | `9cd81b827a0414e746eae699beebf68076e8e967d300f6b30b97712869f68ff4` |
| Post-synth utilization | `a2c5661ddcf7824141639dd1c61e5db6a1c4aa4b2a6c9f74fc36285424850969` |
| Post-route utilization | `e54bf12121483d322234578748f5ff94a74a3a52a3a6291aee4da2e839ec10c2` |
| Post-route timing | `93b52df86288ea7c9f66b831e278f87d430cd0a62ddbf0d95cd0b5e9161d6fcf` |
| Route status | `213cd72b18fdd623661ddb4f35cf5dd00925f0df3e327cc36d7956df09b94ec2` |
| DRC | `6bd1fa2d34ef21e7297d854c424200691b687ff43a57dfbc1fce9aebf2fc923d` |
| Methodology | `bdb74816846f9456448a04ef9ba9383a28fa393bc76a76ceb2ea58cc367b683c` |

Root `Kyber_System_Top.bit` vẫn là RC1, SHA-256 `183e0af3...1f20e8e`; routed
DCP RC1 vẫn là `f843e5fa...d401af`. Không file RC1 nào bị ghi đè.

## Quyết định

Vivado/physical-impact gate của candidate v4 là **PASS**; đúng-image board gate
cũng đã PASS theo báo cáo cùng ngày. Candidate chuyển sang review độc lập trước
khi cân nhắc freeze; chưa phải production release, PUF qualification hay ASIC
sign-off.
