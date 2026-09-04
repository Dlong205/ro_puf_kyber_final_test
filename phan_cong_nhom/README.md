# Phân công và tiến độ nhóm

Thư mục này là bản đồ công việc trên baseline FPGA nội bộ `0.1.0-rc4` và nhánh
ML-KEM candidate hiện tại. Source RTL chính thức vẫn nằm trong `rtl/`; không
copy RTL vào các thư mục cá nhân để tránh tồn tại nhiều phiên bản khác nhau của
cùng một module.

## Baseline chung

- Mốc nền bất biến: tag `fpga-rc4-baseline` tại commit `6f734fc`.
- FPGA XC7Z020 ở 50 MHz: implementation/timing/DRC PASS, 0 net chưa route.
- Board: INFO, enroll, reconstruct và stress 10.000/10.000 PASS.
- ML-KEM-512 đã PASS functional bit-exact nội bộ theo FIPS 203 và Vivado
  implementation; board regression của candidate còn PENDING.
- Bốn primitive FIPS 202 byte-oriented cho ML-KEM đã PASS 50/50 test.
- Public release vẫn bị chặn bởi quyền phân phối Kyber RTL và top-level license.

## Phân chia nội dung

| Thành viên | Nội dung | Trạng thái hiện tại | Thư mục |
|---|---|---|---|
| Đạt và Tùng | Nghiên cứu Kyber KEM | ML-KEM functional/KAT PASS; chờ review độc lập | [`01_kyber_kem_dat_tung/`](01_kyber_kem_dat_tung/README.md) |
| Minh | Nghiên cứu lưu khóa | Có zeroize và không xuất secret; kiến trúc lưu khóa chưa chốt | [`02_luu_khoa_minh/`](02_luu_khoa_minh/README.md) |
| Việt Anh | Nghiên cứu KDF | FIPS 202 PASS 50/50; KDF fixed-profile PASS | [`03_kdf_viet_anh/`](03_kdf_viet_anh/README.md) |
| Long | Chủ trì toàn bộ implementation | Candidate implementation PASS; chờ board/PVT/ASIC | [`04_ro_puf_long/`](04_ro_puf_long/README.md) |

Các thành viên Đạt, Tùng, Minh và Việt Anh cung cấp nghiên cứu/đối chiếu. Long
là người thực hiện thay đổi RTL, tích hợp, chạy gate và chốt artifact để tránh
nhiều nhánh implementation không đồng bộ.

## Quy tắc làm việc chung

1. Mỗi thay đổi bắt đầu từ RC4 hoặc commit tích hợp mới nhất và đi qua Pull
   Request; không push thẳng thay đổi chưa kiểm tra vào `main`.
2. Mỗi Pull Request ghi rõ module bị ảnh hưởng, test đã chạy, kết quả và warning
   mới. Không dùng retry để che mismatch/timeout.
3. Không commit shared secret, helper gắn với board, waveform lớn, build cache,
   file Vivado tạm hoặc dữ liệu PUF đo thô có thông tin thiết bị.
4. Thay đổi interface giữa hai phần phải được hai người phụ trách liên quan
   thống nhất và cập nhật full-system test.
5. Trước khi tích hợp chạy tối thiểu test của phần mình; trước RC tiếp theo chạy:

```sh
make -j1 regression
make -j1 kyber-long
make -j1 asic-portability
./scripts/release_check.sh --internal
```

Nếu thay RTL tổng hợp, phải chạy lại Vivado implementation và board smoke/stress;
không tái sử dụng timing hoặc bitstream của RC4 cho netlist mới.
