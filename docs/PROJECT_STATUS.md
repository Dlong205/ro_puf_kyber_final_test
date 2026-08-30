# Trạng thái xác minh dự án

| Hạng mục | Trạng thái |
|---|---|
| Mô phỏng controller/CDC RO-PUF | PASS |
| Regression BCH fuzzy extractor | PASS (12/12) |
| KAT SHAKE256 KDF | PASS, khớp từng bit với vector FIPS 202 |
| Shared key nội bộ Server/Client Kyber-512 cũ | PASS |
| Thanh ghi/handshake/restart Kyber AXI | PASS; 32 giao dịch logic, 6 raw mismatch, 5 lần phục hồi bằng retry, tối đa 3 attempt |
| Build firmware release PicoRV32 | PASS, text 2.152 byte, BSS 4 byte |
| Mô phỏng end-to-end UART/PUF/FE/KDF/Kyber | PASS, 952.479 cycle |
| Vivado synthesis pure RTL | PASS, XC7Z020, không có IP sinh tự động |
| Place/route và bitstream | PASS, 0 net chưa route, 0 lỗi DRC |
| Timing sau route ở 50 MHz | PASS, WNS +4.108 ns, WHS +0.048 ns |
| Nạp volatile qua JTAG | PASS, `xc7z020_1`, Digilent `260515110006` |
| INFO giao thức 1.1 | PASS, capability `0x0e`, tắt xuất khóa |
| Stress RC2 trong cùng một lần cấp nguồn | PASS, 1.000/1.000 và 10.000/10.000 |
| Đặc trưng điện áp/nhiệt độ/power-cycle | CHƯA CHẠY |

Test trên board đã phát hiện một raw Kyber stall ở giao dịch logic 162 với ảnh
trước RC2, khi firmware mới retry key mismatch nhưng chưa retry watchdog timeout.
Run đó được dừng vì host mất đồng bộ sau lỗi firmware `0x07`; các lỗi xuất hiện
sau đó không phải phép đo độc lập. RC2 reset và retry cả raw mismatch lẫn raw
watchdog timeout trong giới hạn 16 lần, còn host dừng ngay tại lỗi giao thức đầu tiên.

Bitstream RC2 cuối cùng PASS 1.000 rồi 10.000 giao dịch full-pipeline liên tiếp,
không có lỗi nhìn thấy từ bên ngoài, trên cùng một board, nguồn và điều kiện môi
trường. Kết quả xác nhận giao dịch kỹ thuật có retry giới hạn; nó không xác nhận
độ tin cậy hoặc tuân thủ tiêu chuẩn của từng raw Kyber attempt.

Định danh bitstream hiện tại:

- SHA-256: `e85e3f2bd0206485aa636b56b9256aae9a38255ab29179f6fb20e37d6b4abdfb`
- Kích thước: 4.045.676 byte
- DRC: 0 lỗi, 165 warning đã ghi nhận
- Tài nguyên: 51.774/53.200 Slice LUT (97,32%), 23,5 BRAM tile, 4 DSP

Xem `HARDWARE_TEST_REPORT_RC2_2026-08-30.md` để biết phạm vi test phần cứng chính
xác. Core vẫn là Kyber-512 cũ/thử nghiệm, không phải FIPS 203 ML-KEM-512; quyền
phân phối công khai vẫn bị chặn theo `NOTICE.md`.
