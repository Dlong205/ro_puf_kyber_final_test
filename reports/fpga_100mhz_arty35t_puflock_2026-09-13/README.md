# Full Edge 100 MHz với khóa vật lý RO-PUF — Arty A7-35T

Đây là bộ bằng chứng hậu place-and-route OOC của
`edge_puf_mlkem_core` trên `xc7a35ticsg324-1L`, clock 10 ns. Candidate được
chọn là `edgefull_10ns_kdfwidece_puflock_v08`.

## Kết quả chấp nhận

| Chỉ tiêu | Kết quả |
|---|---:|
| Setup slack (WNS) | +0,053 ns |
| Hold slack (WHS) | +0,046 ns |
| Net chưa route / route một phần | 0 / 0 |
| Routing error | 0 |
| LUT logic | 19.935 / 20.800 (95,84%) |
| Slice LUT tổng | 20.126 / 20.800 (96,76%) |
| Register | 19.398 / 41.600 (46,63%) |
| BRAM tile | 14 / 50 (28,00%) |
| DSP | 2 / 90 (2,22%) |

DRC có 166 warning đã phân loại: 32 `LUTLP-2` và 128 `PDCN-1569` thuộc cấu
trúc RO có chủ đích; 2 `DPOP-2`, 2 `PDRC-153` và 2 `PLHOLDVIO-2`. Không có
Error, Critical Warning hay `RTSTAT-2`.

## Audit khóa RO

- XDC cố định placement của 1.166 primitive trong toàn vùng `u_puf`.
- 136 endpoint cell có LOC/BEL/LOCK_PINS cố định.
- 128 feedback net có FIXED_ROUTE và route thực tế trùng nhau.
- Fingerprint sinh từ checkpoint v08 khớp byte-for-byte baseline:
  `aac68edf2d30aec04b77c5e90fc2619ab8b819ec0fe9d9fe51bd9d934bc32f69`.
- Validator kết thúc với `RO_PHYSICAL_LOCK_AUDIT=PASS` và
  `RO_ARTY35T_LOCK_VALIDATION=PASS`.

## Phạm vi tuyên bố

Kết quả này chứng minh core Edge fit, đóng timing OOC và tái lập được hình học
RO trong implementation. Nó chưa chứng minh board operation: chưa có board
top, transport, constraint chân/I/O và bitstream full Edge. Ảnh PUF-only từng
đo trên board không dùng implementation này, do đó vẫn cần tạo image full Edge
đã khóa rồi chạy power-cycle, PVT, count-margin và nhiều board trước khi freeze
RO-PUF.

Các file `.rpt`, `result.tsv` và `ro_physical_fingerprint.tsv` trong thư mục
này là bản sao trực tiếp từ run v08.
