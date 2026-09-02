# Long — Chủ trì implementation và RO-PUF

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
- `sim/portability/`
- `constraints/kp_zynq_7020.xdc`
- `scripts/inspect_ro_netlist.tcl`
- `docs/ASIC_PORTABILITY.md`

## Trạng thái RC4

- Controller simulation/reset/restart: PASS.
- Backend behavioral, Xilinx LUT và ASIC macro boundary đã tách.
- Netlist FPGA có 128 LUT, 128 feedback net và 128/128 loop constraint.
- Board full pipeline stress 10.000/10.000 PASS trong một phiên test.
- Counter đã dùng asynchronous-assert/synchronous-release và đồng bộ enable.
- Methodology còn 72 `TIMING-17` vì clock RO vật lý bất định; report CDC tự
  động không phải CDC/RDC sign-off cho miền RO.
- Chưa có macro RO Liberty/LEF/GDS và chưa characterize nhiều board/PVT.

## Việc tiếp theo

1. Lập protocol đo nhiều board, cold/warm power-cycle, voltage và temperature.
2. Thu response có định danh điều kiện; tính intra-device HD, inter-device HD,
   bit-alias, min-entropy và failure rate của fuzzy extractor.
3. Rà CDC/RDC bằng tool chuyên dụng; chốt handshake/reset và waiver có lý do.
4. Định nghĩa contract macro ASIC: `en`, `cfg`, `ro_clk`, trạng thái khi disable,
   test/bypass, PVT characterization và timing/power views.
5. Khi có PDK, dựng macro RO vật lý với keep-out/shielding/placement matching;
   không synthesize vòng inverter như logic chuẩn.
6. Phối hợp Minh về helper/provisioning và tiêu chí reject khi PUF không ổn định.

## Definition of Done

- Có dataset và báo cáo thống kê nhiều board/PVT/power-cycle tái lập được.
- Reliability và entropy đạt ngưỡng đã chốt; over-noise bị phát hiện đúng.
- CDC/RDC được sign-off hoặc có waiver cụ thể cho từng đường.
- ASIC macro có đủ Liberty, LEF, GDS, netlist và test-mode contract trước P&R.

## Lệnh kiểm tra hiện có

```sh
make ro-puf
make fuzzy
make asic-portability
/media/donglong/tools/Xilinx/Vivado/2020.1/bin/vivado \
  -mode batch -nolog -nojournal -source scripts/inspect_ro_netlist.tcl
```
