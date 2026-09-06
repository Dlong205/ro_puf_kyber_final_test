# Long — Chủ trì implementation và RO-PUF

Cập nhật **2026-09-06**. Long là implementation owner duy nhất: tiếp nhận các
biên bản nghiên cứu/review, sửa RTL, tích hợp, chạy regression/Vivado/board và
quyết định artifact nào được quảng bá.

## Phạm vi phụ trách

- Thực hiện toàn bộ thay đổi RTL, tích hợp, regression và chốt artifact.
- Tiếp nhận kết quả nghiên cứu/review từ Đạt, Tùng, Minh và Việt Anh.
- Ring oscillator, challenge selection, counter, controller và response capture.
- CDC/RDC giữa system clock và RO clock.
- Backend mô phỏng, Xilinx và macro ASIC.
- Characterization reliability/uniqueness/entropy trên nhiều board và góc PVT.

## Source và test liên quan

- `rtl/puf/`
- `rtl/asic/kp_asic_ro_macro_blackbox.sv`
- `sim/ro_puf/`
- `sim/puf_characterization/`
- `sim/fuzzy_extractor/`
- `sim/portability/`
- `host/puf_raw_characterize.py`
- `host/tests/test_puf_raw_characterize.py`
- `constraints/kp_zynq_7020.xdc`
- `constraints/ro_physical_lock_rc1_zynq7020.xdc`
- `constraints/ro_physical_fingerprint_rc1_zynq7020.tsv`
- `scripts/inspect_ro_netlist.tcl`
- `scripts/audit_ro_physical_lock.tcl`
- `scripts/check_ro_route_repro.sh`
- `docs/ASIC_PORTABILITY.md`
- `docs/PUF_CHARACTERIZATION_2026-09-05.md`
- `docs/RO_PHYSICAL_REPRODUCIBILITY_2026-09-05.md`

## Đã hoàn thành

- Controller simulation/reset/restart: PASS.
- Backend behavioral, Xilinx LUT và ASIC macro boundary đã tách.
- Netlist FPGA có 128 LUT, 128 feedback net và 128/128 loop constraint.
- Board full pipeline stress 10.000/10.000 PASS trong một phiên test.
- Artifact ML-KEM RC1/candidate v2 PASS functional gate, ASIC portability,
  synthesis, place/route, timing/DRC và tạo bitstream ở 50 MHz.
- Artifact này dùng 49.909/53.200 LUT (`93,81%`), WNS `+2,226 ns`; board
  regression PASS 10.000/10.000, fail 0.
- Candidate v3 đã PASS full RTL/ASIC front-end gate, Vivado và đúng-image board
  stress 10.000/10.000; board đã restore RC1. P0 secure-zeroize chặn promote.
- Counter đã dùng asynchronous-assert/synchronous-release và đồng bộ enable.
- Image PUF-only đã lấy 10.000 mẫu ở điều kiện phòng trên một board: HD
  max/p99 bằng 1, không mẫu nào vượt BCH `t=8`, một bit dao động (bit 149).
- Full-SoC đã khóa 128 LUT RO, 8 LUT mux đầu cuối và 128 route; fingerprint gồm
  136 endpoint, `INIT`, LOC/BEL, pin-map và route.
- Hai build sạch độc lập khớp chính xác fingerprint RC1. Image `locked_b` PASS
  INFO/enroll/reconstruct và stress 10.000/10.000; board sau đó đã nạp lại RC1.
- ASIC-generic elaboration PASS; RO, BCH compare và NTT multiplier đã tách khỏi
  primitive vendor trong source list ASIC.

## Giới hạn chưa được phép bỏ qua

- Methodology còn 72 `TIMING-17` vì clock RO vật lý bất định; report CDC tự
  động không phải CDC/RDC sign-off cho miền RO.
- Dataset 10.000 mẫu dùng image PUF-only có loading/routing khác full-SoC; không
  được suy thẳng kết quả này sang RC1.
- KEM match không chứng minh same-root vì hai phía dùng cùng khóa vừa phục hồi.
- 264 output chỉ dùng 32 RO vật lý và 255 challenge duy nhất. Trong mô hình thứ
  tự tần số vô hướng, upper bound cấu trúc là `log2(32!) = 117,663 bit`; chưa có
  cơ sở gọi root PUF 192-bit hay cho rằng KDF 512-bit làm tăng entropy nguồn.
- Chưa có macro RO Liberty/LEF/GDS/netlist, PDK/memory mapping/SDC/DFT và chưa
  characterize nhiều board/PVT.

## Còn mở theo thứ tự ưu tiên

1. Tạo candidate v4 đóng P0 secure-zeroize, chạy lại full gate/Vivado/board rồi
   mới chuyển sang review độc lập và freeze.
2. Thêm count-margin telemetry, tie/zero detection và số lỗi BCH đã sửa; ưu
   tiên challenge tạo bit 149.
3. Đo same-root trên chính full-SoC hoặc bằng instrumentation không làm thay đổi
   physical fingerprint RC1.
4. Chạy tối thiểu 100 warm reset, 100 cold power-cycle, PVT an toàn, aging và
   tối thiểu 5 board (khuyến nghị 10+).
5. Thu response có định danh điều kiện; tính intra-device HD, inter-device HD,
   bit-alias, min-entropy và failure rate của fuzzy extractor.
6. Rà CDC/RDC bằng tool chuyên dụng; chốt handshake/reset và waiver có lý do.
7. Định nghĩa contract macro ASIC: `en`, `cfg`, `ro_clk`, trạng thái khi disable,
   test/bypass, PVT characterization và timing/power views.
8. Khi có PDK, dựng macro RO vật lý với keep-out/shielding/placement matching;
   không synthesize vòng inverter như logic chuẩn.
9. Phối hợp Minh về helper/provisioning và tiêu chí reject khi PUF không ổn định.

## Definition of Done

- Có dataset và báo cáo thống kê nhiều board/PVT/power-cycle tái lập được.
- Reliability và entropy đạt ngưỡng đã chốt; over-noise bị phát hiện đúng.
- CDC/RDC được sign-off hoặc có waiver cụ thể cho từng đường.
- ASIC macro có đủ Liberty, LEF, GDS, netlist và test-mode contract trước P&R.

## Lệnh kiểm tra hiện có

```sh
make ro-puf
make fuzzy
make -j1 fuzzy-characterization
make -j1 puf-characterization-sim
make -j1 puf-metrics-test
make asic-portability
make ro-route-repro-check SOC_REPRO_A=locked_a SOC_REPRO_B=locked_b
```

Các lệnh đo board và build Vivado phải chạy tuần tự bằng `make -j1` và truyền
`VIVADO=/absolute/path/to/vivado` khi công cụ không có trong `PATH`.
