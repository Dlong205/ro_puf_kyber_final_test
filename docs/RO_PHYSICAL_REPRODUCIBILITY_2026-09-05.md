# Báo cáo tái lập placement/routing RO-PUF — 2026-09-05

## Kết luận

Vivado có thể đặt và đi dây ring oscillator khác nhau giữa các lần
implementation. Đối với RO-PUF, thay đổi delay routing có thể làm đổi thứ tự
tần số RO và vì thế đổi response. Luồng full-SoC hiện đã khóa và kiểm tra tự
động phần vật lý RO theo implementation ML-KEM RC1 đã được chấp nhận.

Hai implementation sạch, độc lập `locked_a` và `locked_b` đều tái tạo chính
xác fingerprint vật lý của RC1:

- 128 LUT tạo 32 ring oscillator;
- 128 net vật lý trong các vòng RO;
- 136 cell đầu cuối, gồm 128 LUT RO và 8 LUT mux nhận output `t3`;
- hàm `INIT`, `REF_NAME`, `LOC`, `BEL`, ánh xạ logical-pin → site-pin;
- danh sách leaf pin và chuỗi route có cấu trúc nhánh của từng net;
- `IS_ROUTE_FIXED`, `FIXED_ROUTE`, `IS_LOC_FIXED`, `IS_BEL_FIXED` và
  `LOCK_PINS` đều được audit sau route.

Đây là **PASS về tái lập cấu trúc vật lý RO trong full-SoC**. Nó không chứng
minh ổn định qua nhiệt độ, điện áp, aging hoặc nhiều chip, và không thay thế
qualification entropy/reliability.

## Baseline được khóa

| Thành phần | SHA-256 |
|---|---|
| Bitstream ML-KEM RC1 đã test board | `183e0af367376ebd7ca6bc2f3747314fd0602306a630af2a2e51858ef1f20e8e` |
| Routed DCP nguồn local | `f843e5fa2daa7e0f5c14f776e34166618479dcb33c4e1d1293f7ca4145d401af` |
| XDC physical lock | `3b7ea2cdb5dcb4ebd5f84e4bf97a47b3690ea4cb838ad1b08aaf80c30b5d37de` |
| Fingerprint vật lý V2 | `1fbad9f1d1ec3a04560d506979778991311a00e84d3b31c7e8e56596db464c23` |

Exporter từ chối chạy nếu hash DCP hoặc bitstream nguồn khác các giá trị đã
chốt. DCP chỉ là bằng chứng local trong `build/`; XDC và fingerprint nhỏ, có
thể review được, được commit trong `constraints/` và được bảo vệ bởi
`ARTIFACTS.sha256`.
Negative test dùng DCP `locked_b` làm nguồn export đã bị từ chối đúng tại hash
gate, trước khi ghi XDC/fingerprint.

## Kết quả hai build độc lập

| Hạng mục | `locked_a` | `locked_b` |
|---|---:|---:|
| Physical fingerprint | PASS | PASS |
| Endpoint cell / fixed route | 136 / 128 | 136 / 128 |
| WNS / WHS ở 50 MHz | `+4,732 / +0,034 ns` | `+4,732 / +0,034 ns` |
| Timing constraint | PASS | PASS |
| Design state | Fully Routed | Fully Routed |
| DRC Error / Critical Warning | `0 / 0` | `0 / 0` |
| Warning đã phân loại | 165 | 165 |
| Bitstream SHA-256 | `e7fb41e89e4eb988e92661570df8d9848ed10842fe1aa432bb1f7972ad5325f8` | `6b4e2237125b8ce2e3024d4617909324cd6786541f3fe0b12a9616d9a42c0aa8` |
| Routed DCP SHA-256 | `9bedf16e467fe2a89707a368674865f347dba9250fad86fa9650f576f06d7cbc` | `3f846ed43b006a508754c24d1afa32d78c4d88a38da1bf32bf6cf3837be24331` |

Bitstream và DCP toàn chip không bắt buộc có cùng hash: chúng chứa metadata
build và router vẫn được phép tối ưu phần **ngoài** miền RO. Tiêu chí đúng là
fingerprint của miền RO khớp chính xác, đồng thời toàn thiết kế fully-routed,
timing PASS và DRC không có Error/Critical Warning.

Build `locked_a` ban đầu phát ra 100 critical warning do cùng một `LOCK_PINS`
được khai báo ở cả board XDC và physical XDC. Exporter đã được sửa để board XDC
khóa 128 LUT RO, còn physical XDC chỉ bổ sung pin-lock cho 8 LUT mux. Build
`locked_b` sau sửa có 0 critical warning. Fingerprint trước/sau không đổi.

## Cách tái chạy

Mọi lệnh Vivado dưới đây dùng một worker:

```sh
make -j1 SOC_REPRO_RUN=locked_c soc-repro-build \
  VIVADO=/media/donglong/tools/Xilinx/Vivado/2020.1/bin/vivado

make ro-route-repro-check SOC_REPRO_A=locked_b SOC_REPRO_B=locked_c
```

Luồng `make -j1 impl` chuẩn cũng nạp physical lock mặc định và gọi audit sau
route. Nếu thiếu XDC, thiếu object, route lệch, pin-map lệch hoặc fingerprint
khác RC1, build dừng thay vì tạo một release candidate không tương đương.

`make ro-lock-export` là thao tác bảo trì baseline, không phải bước build thông
thường. Nó cần đúng routed DCP RC1 local và được hash-gate để tránh vô tình
thay fingerprint vàng.

## Trạng thái test board của image tái lập

Lúc `20:42–20:43` ngày 2026-09-05, Linux nhận CH340 UART và FT232H/Digilent
JTAG, nhưng Vivado báo target không có FPGA device. Hai lần thử đều dừng tại
`open_hw_target`, trước `program_hw_devices`; UART của board cũng không trả lời
INFO. Nguyên nhân là board đang tắt; không có lệnh program nào được thực thi
trong hai lần đó.

Sau khi bật board, `locked_b` được nạp đúng theo đường dẫn tuyệt đối và PASS:

| Phép thử | Kết quả |
|---|---:|
| JTAG `xc7z020_1`, DONE HIGH | PASS |
| INFO | protocol 1.2, capability `0x06` |
| Enroll/reconstruct | PASS |
| Stress | 100/100, 1.000/1.000, 10.000/10.000 |
| Fail/timeout/retry | 0 |
| Run 10.000 | `29,616 ms/giao dịch`, `33,765 giao dịch/s` |

Kết thúc campaign, bitstream RC1 root hash `183e...e8e` đã được nạp lại bằng
đường dẫn tuyệt đối. INFO, reconstruct bằng helper của candidate và stress
100/100 đều PASS. Một helper enroll mới trên RC1 khác helper candidate 30 bit;
mức này phù hợp dao động helper từng quan sát, nhưng helper HD không phải raw
response HD. KEM PASS cũng không tự chứng minh same-root do hai phía dùng cùng
khóa vừa phục hồi. Board hiện đang chạy lại RC1, không phải image thử nghiệm.

## Phạm vi còn mở

- Image PUF-only từng đo 10.000 raw sample vẫn có topology/loading khác
  full-SoC và chưa dùng route-lock này; không được chuyển kết luận của dataset
  đó sang image release chỉ dựa trên LOC/BEL.
- Full-SoC release chưa có endpoint raw response/count-margin hoặc phép so
  same-root riêng. Physical equivalence giải quyết biến động do build, không
  giải quyết nhiễu vật lý.
- Vẫn cần warm/cold boot, PVT, aging, tối thiểu 5 board và entropy/helper
  leakage trước khi freeze PUF hay gọi thiết kế production-ready.
