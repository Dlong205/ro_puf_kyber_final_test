# Lịch sử thay đổi

## 0.1.0-rc2 — 2026-08-30

- Bổ sung capability `0x08` của giao thức 1.1 cho cơ chế Kyber retry nội bộ có giới hạn.
- Retry cả raw key mismatch giữa server/client và raw Kyber watchdog stall bằng
  `m` mới đã được diversify, tối đa 16 lần.
- Giảm giới hạn watchdog riêng của Kyber và chỉ kéo dài cửa sổ phản hồi phía host sau marker `F`.
- Cho host stress dừng ngay tại giao dịch lỗi đầu tiên để giữ đồng bộ giao thức
  và tránh thống kê cascade gây hiểu nhầm.
- PASS mô phỏng full-system tại 952.479 cycle và stress board 1.000/1.000, sau đó
  10.000/10.000 giao dịch logic.
- Tạo lại implementation: WNS +4.108 ns, WHS +0.048 ns, 0 lỗi DRC,
  51.774/53.200 Slice LUT và SHA-256 bitstream
  `e85e3f2bd0206485aa636b56b9256aae9a38255ab29179f6fb20e37d6b4abdfb`.
- Ghi rõ retry chỉ là biện pháp kỹ thuật tăng availability; nó không loại bỏ lỗi
  raw của core cũ và không chứng minh tuân thủ FIPS 203 ML-KEM-512.

## 0.1.0-rc1 — 2026-08-28

- Bổ sung bản build pure RTL độc lập cho XC7Z020-2CLG400I ở 50 MHz.
- Sửa căn chỉnh luồng/capture Kyber SHAKE và reset khi chạy lặp.
- Bổ sung AXI zeroize, trạng thái sticky key-match và cố định tham số Kyber-512.
- Bổ sung giao thức UART release v1 với device info, timeout có giới hạn và mã lỗi theo giai đoạn.
- Tắt xuất shared secret và LED phụ thuộc secret trong bản mặc định.
- Bổ sung diversify input theo session và zeroize rõ ràng sau mỗi thao tác.
- Bổ sung regression RO-PUF, BCH, FIPS 202 SHAKE256, Kyber loopback, AXI và full-system.
- Sửa source mô phỏng BCH sinh cũ và harness RO-PUF không có clock.
- Chuyển reset trạng thái SHA3/Kyber nối BRAM sang reset đồng bộ.
- Bổ sung công cụ build độc lập, nạp board, host stress và release audit.
- Tạo lại implementation RC1 ngày 2026-08-30: WNS sau route +4.580 ns,
  WHS +0.055 ns, 0 lỗi DRC và SHA-256 bitstream
  `b2a8c1b3b3d112e26b2ccf6bd78370ca8645a105a6d226c47c1fd92f0f6e68cd`.

Phân phối công khai vẫn bị chặn bởi các mục license trong `NOTICE.md`.
