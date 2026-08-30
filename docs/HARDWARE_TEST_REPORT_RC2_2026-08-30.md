# Báo cáo test phần cứng RC2 — 2026-08-30

## Phạm vi và kết quả cuối

Ứng viên kỹ thuật nội bộ `0.1.0-rc2` đã được build, nạp và chạy trên một board
XC7Z020-2CLG400I. Image cuối PASS INFO, enroll, 1.000/1.000 giao dịch
reconstruct/Kyber và một run stress riêng 10.000/10.000 trong cùng lần cấp nguồn,
không có lỗi nhìn thấy từ bên ngoài.

Đây là kết quả trên một board, một lần cấp nguồn và điều kiện môi trường phòng.
Nhiệt độ môi trường và điện áp nguồn không được đo. Nó không phải qualification
góc PUF hoặc bằng chứng phù hợp cho mật mã production.

## Định danh artifact cuối

- File: `Kyber_System_Top.bit`
- Kích thước: 4.045.676 byte
- SHA-256: `e85e3f2bd0206485aa636b56b9256aae9a38255ab29179f6fb20e37d6b4abdfb`
- Đích: `xc7z020clg400-2`
- Constraint clock: 50 MHz
- Timing sau route: WNS `+4.108 ns`, WHS `+0.048 ns`, TNS/THS `0 ns`
- Route: 0 net lỗi, chưa route hoặc route một phần
- Tài nguyên: 51.774/53.200 Slice LUT, 23,5 BRAM tile, 4 DSP
- DRC: 0 lỗi, 165 warning đã ghi nhận
- Firmware: release mode, giao thức 1.1, capability `0x0e`

## Thiết lập test

- JTAG target: `Digilent/260515110006`
- Thiết bị Vivado: `xc7z020_1`
- USB-UART: CH340 tại `/dev/ttyUSB1`, 115200 8N1
- Chế độ nạp: chỉ cấu hình PL volatile, không ghi QSPI/flash
- Xuất shared secret: tắt
- Helper data: enroll mới cho từng lệnh stress và lưu ngoài gói release

## Xác minh trước hardware

- Test controller/CDC RO-PUF: PASS
- Test BCH fuzzy extractor: PASS (12/12)
- FIPS 202 SHAKE256 KAT: PASS
- Loopback fixed-vector Kyber-512 cũ: PASS
- Stress retry logic AXI: PASS, 32 giao dịch; 6 raw mismatch, 5 giao dịch phục hồi,
  tối đa 3 attempt
- Mô phỏng full-system giao thức release: PASS, 952.479 cycle
- Audit độc lập/internal release: PASS
- Timing implementation và DRC: PASS

## Vấn đề phát hiện khi stress board

Một image trung gian có SHA-256 bitstream
`0f440e556b0c6bb90aa56d42b384e3d774e1f2a9212478f14fed210b87af7013`
đã retry raw key mismatch nhưng trả lỗi ngay khi raw Kyber watchdog timeout. Nó
PASS 100/100, sau đó test 1.000 vòng dừng ở giao dịch logic 162 sau marker
`ABCDEF`; firmware báo lỗi `0x07` (Kyber timeout). Host tiếp tục gửi dữ liệu rồi
mất đồng bộ, nên các lỗi sau đó trong run bị hủy không phải giao dịch độc lập.

RC2 sửa bằng cách:

1. Retry raw watchdog timeout cùng với raw key mismatch trong giới hạn 16 attempt.
2. Dùng watchdog riêng Kyber ngắn hơn để reset raw attempt bị treo nhanh.
3. Cho host một khoảng đợi riêng, có giới hạn, dành cho marker `G`.
4. Dừng host stress ngay tại lỗi đầu tiên để bảo toàn bằng chứng giao thức.

## Kết quả cuối trên board

| Bài test | Kết quả |
|---|---|
| Nạp JTAG volatile | PASS, DONE=HIGH |
| Response INFO | PASS, `4B 50 01 01 0E` |
| 1.000 giao dịch logic full-pipeline | PASS, 1.000/1.000 |
| 10.000 giao dịch logic full-pipeline | PASS, 10.000/10.000 |
| Lỗi UART/giao thức trong run cuối | 0 |
| Lỗi PUF/FE/KDF/Kyber nhìn thấy bên ngoài trong run cuối | 0 |

Firmware không xuất raw retry counter, nên kết quả không cho biết bao nhiêu raw
mismatch/stall đã được phục hồi. Nó xác nhận hợp đồng giao dịch logic có retry
giới hạn, không khẳng định lỗi raw core đã được loại bỏ.

## Qualification phần cứng còn thiếu

- Chiến dịch enroll/reconstruct qua cold và warm power-cycle
- Góc nhiệt độ và điện áp
- Đo uniqueness/độ tin cậy trên nhiều board
- Test aging/restart thời gian dài
- Đánh giá side-channel và fault-injection

RC2 chỉ đạt connected-board qualification ở mức ứng viên nghiên cứu/kỹ thuật nội
bộ. Nó không phải FIPS 203 ML-KEM-512 và không phải release production.
