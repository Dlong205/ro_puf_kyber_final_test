# Báo cáo test phần cứng RC1 — 2026-08-30

## Phạm vi và kết quả

Báo cáo này mô tả lần thử board đầu tiên của ứng viên `0.1.0-rc1` trên
XC7Z020-2CLG400I. FPGA implementation đã PASS build sign-off, nhưng xác minh board
**BỊ CHẶN** vì thấy adapter JTAG trong khi scan chain FPGA không có thiết bị. Vì
vậy bitstream RC1 chưa được nạp trong lần thử này.

Không gộp kết quả này với baseline 10.000/10.000 trong
`HARDWARE_TEST_REPORT_2026-08-28.md`; test đó dùng image và protocol cũ hơn.

## Định danh artifact RC1

- File: `Kyber_System_Top.bit`
- Kích thước: 4.045.676 byte
- SHA-256: `b2a8c1b3b3d112e26b2ccf6bd78370ca8645a105a6d226c47c1fd92f0f6e68cd`
- Đích: `xc7z020clg400-2`
- Constraint clock: 50 MHz
- Timing sau route: WNS `+4.580 ns`, WHS `+0.055 ns`, TNS/THS `0 ns`
- Route: 0 net lỗi, chưa route hoặc route một phần
- DRC: 0 lỗi, 165 warning đã ghi nhận

## Xác minh trước hardware

- Test controller/CDC RO-PUF: PASS
- Test BCH fuzzy extractor: PASS (12/12)
- FIPS 202 SHAKE256 KAT: PASS
- Loopback server/client Kyber-512 cũ: PASS
- Test AXI start/restart/key-match/zeroize Kyber: PASS
- Mô phỏng full-system giao thức release: PASS, 950.740 cycle
- Audit độc lập và internal release: PASS

## Quan sát kết nối

- Linux phát hiện adapter JTAG tương thích Digilent FT232H.
- Vivado nhận target `Digilent/260515110006`.
- Linux phát hiện USB-UART CH340 tại `/dev/ttyUSB1`.
- Hai lần nạp Vivado, gồm một lần restart hardware server sạch, đều lỗi tại
  `open_hw_target` với `No devices detected on target`.
- Request INFO giao thức v1 qua UART không có response.
- Không thử ghi flash và không thay đổi cấu hình FPGA.

## Các bước tiếp tục bắt buộc

1. Kiểm tra nguồn board và LED báo nguồn.
2. Cắm lại, kiểm tra hướng cáp và đầu nối JTAG phía board.
3. Kiểm tra jumper JTAG/boot-mode theo tài liệu board.
4. Power-cycle board rồi chạy `make program` đến khi có `PROGRAM_PASS`.
5. Chạy INFO, enroll, reconstruct, 100 vòng và 10.000 vòng với helper tạm riêng của board.
6. Ghi hash artifact, điều kiện môi trường, power-cycle và mọi lỗi vào báo cáo này
   hoặc báo cáo kế tiếp có ngày.

Cho đến khi các bước đó PASS, RC1 chỉ là ứng viên kỹ thuật nội bộ đạt mô
phỏng/build, chưa phải release đã xác nhận trên board.
