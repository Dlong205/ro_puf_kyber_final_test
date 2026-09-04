# Báo cáo implementation FPGA ML-KEM candidate — 2026-09-04

## Kết luận

RTL candidate đã **PASS synthesis, place, route, timing, DRC và bitstream** cho
`XC7Z020-2CLG400I` ở 50 MHz. Candidate chưa được nạp/test lại trên board, vì
board không xuất hiện trong `lsusb` và không có thiết bị `/dev/ttyUSB*` tại thời
điểm kiểm tra. Vì vậy đây là implementation candidate, chưa phải artifact FPGA
đã xác nhận end-to-end.

Nhãn mật mã vẫn là **ML-KEM-512 internal algorithm functional PASS**, không
phải chứng nhận CAVP, FIPS 140-3 hay chứng nhận sản phẩm.

## Định danh build

- Source commit: `8d2e8cda6d31e04e1557d64ca53d187cd85afc92`
- Nhánh: `codex/fips202-mlkem`
- Baseline so sánh bất biến: tag `fpga-rc4-baseline`
- Vivado: 2020.1, build 2902540
- Part: `xc7z020clg400-2`
- Top: `Kyber_System_Top`
- Clock constraint: 20 ns, 50 MHz
- Xilinx IP sinh tự động: 0 `.xci`, 0 IP instance
- Bitstream local:
  `build/vivado/kyber_ro_puf_zynq7020.runs/impl_1/Kyber_System_Top.bit`
- Kích thước bitstream: 4.045.676 byte
- SHA-256 bitstream:
  `183e0af367376ebd7ca6bc2f3747314fd0602306a630af2a2e51858ef1f20e8e`

Bitstream trên chỉ nằm trong thư mục build local. `Kyber_System_Top.bit` ở root
vẫn là artifact RC4 đã test board và chưa bị thay thế.

## Lỗi fit đã phát hiện và sửa

Implementation đầu tiên của candidate dùng trực tiếp controller FIPS 202 tổng
quát cho KDF và cần 56.145 Slice LUT (`105,54%`), nên placer dừng với
`UTLZ-1`. Hierarchy report chỉ ra KDF tổng quát dùng 14.871 LUT do giữ thêm một
bản sao state Keccak 1600-bit.

KDF SoC sau đó được chuyên dụng hóa đúng profile duy nhất mà thiết kế cần:
`SHAKE256(24 byte, 64 byte)`. Core FIPS 202 tổng quát vẫn được giữ và test độc
lập. KDF cố định PASS bit-exact với Python, full-system PASS lại và diện tích
KDF sau route giảm còn 9.102 LUT. Đây là thay đổi kiến trúc tài nguyên, không
thay đổi hàm mật mã.

## Tài nguyên sau route

| Tài nguyên | Đã dùng | Có sẵn | Tỷ lệ |
|---|---:|---:|---:|
| Slice LUT | 49.909 | 53.200 | 93,81% |
| LUT logic | 49.571 | 53.200 | 93,18% |
| LUT memory | 338 | 17.400 | 1,94% |
| Slice register | 30.649 | 106.400 | 28,81% |
| BRAM tile | 25 | 140 | 17,86% |
| DSP | 4 | 220 | 1,82% |

Ciphertext store 256 x 32 bit của implicit rejection được infer thành một
RAMB18E1. Bốn phép nhân NTT được infer thành DSP48E1 từ module multiplier RTL
trung lập; source không instantiate primitive DSP48 trực tiếp.

## Timing và route

| Chỉ số | Kết quả |
|---|---:|
| WNS | +2,226 ns |
| TNS | 0 ns |
| Setup endpoint lỗi | 0 / 84.277 |
| WHS | +0,034 ns |
| THS | 0 ns |
| Hold endpoint lỗi | 0 / 84.277 |
| Routable net hoàn tất | 70.739 / 70.739 |
| Net routing error | 0 |

Vivado kết luận `All user specified timing constraints are met`. Margin này
chỉ áp dụng cho constraint 50 MHz; nó không chứng minh thiết kế đạt 100 MHz.

## DRC, methodology và RO audit

DRC đầy đủ có 0 Error/Critical Warning và 165 warning đã phân loại:

| Rule | Số lượng | Phân loại |
|---|---:|---|
| `DPOP-2` | 4 | DSP NTT chưa dùng MREG; khuyến nghị power/performance |
| `LUTLP-2` | 32 | vòng tổ hợp có chủ đích của 32 ring oscillator |
| `PDCN-1569` | 128 | pin giữ LUT của cấu trúc RO vật lý |
| `ZPS7-1` | 1 | thiết kế pure-PL cố ý không instantiate Zynq PS7 |

Methodology report còn 72 `TIMING-17`, 2 `LUTAR-1`, 4 `TIMING-18` và 32
`TIMING-23`. Phần lớn liên quan clock bất định/vòng tổ hợp của RO-PUF; đây chưa
phải CDC/RDC hoặc sign-off ASIC. Audit synthesized netlist xác nhận:

- 128 LUT RO;
- 128 feedback net;
- 128/128 feedback net có `ALLOW_COMBINATORIAL_LOOPS=TRUE`.

## Regression đi kèm

Sau khi tối ưu KDF, `make -j1 crypto-freeze-gate` PASS toàn bộ:

- FIPS 202: 50/50;
- KDF SHAKE256 fixed-profile: bit-exact, cycle 148;
- ML-KEM KeyGen/Encaps/Decaps: 25/25 mỗi nhóm;
- implicit rejection: 175/175;
- full UART/PUF/FE/KDF/ML-KEM: PASS ở 956.564 cycle;
- Kyber raw single-attempt: 1.024/1.024, mismatch/retry bằng 0;
- ASIC portability/elaboration và freeze manifest: PASS.

## Cổng còn lại trước freeze cuối

1. Kết nối lại board và xác nhận JTAG/UART.
2. Nạp bitstream candidate volatile, chạy `info`, enroll và reconstruct.
3. Chạy stress 10.000 giao dịch single-attempt, fail/timeout bằng 0.
4. Nếu board PASS, quảng bá bitstream candidate thành artifact root, cập nhật
   `ARTIFACTS.sha256`, version/report và tạo tag freeze cuối.
5. Hoàn tất review độc lập serialization, compare/mux rejection, reset và
   zeroization.

Các báo cáo nguồn nằm tại `reports/post_synth_*` và `reports/post_route_*`.

