# Phân công và tiến độ nhóm

Thư mục này là bản đồ công việc trên baseline FPGA nội bộ `0.1.0-rc4`. Source
RTL chính thức vẫn nằm trong `rtl/`; không copy RTL vào các thư mục cá nhân để
tránh tồn tại nhiều phiên bản khác nhau của cùng một module.

## Baseline chung

- Commit nền đã xác nhận: `c3a55be` trên nhánh `codex/asic-portability`.
- FPGA XC7Z020 ở 50 MHz: implementation/timing/DRC PASS, 0 net chưa route.
- Board: INFO, enroll, reconstruct và stress 10.000/10.000 PASS.
- Kyber hiện tại là Kyber-512 cũ, chưa phải FIPS 203 ML-KEM-512.
- KDF SHAKE256 đã có một KAT; bộ kiểm thử FIPS 202 đầy đủ chưa hoàn thành.
- Public release vẫn bị chặn bởi quyền phân phối Kyber RTL và top-level license.

## Phân chia nội dung

| Thành viên | Nội dung | Trạng thái hiện tại | Thư mục |
|---|---|---|---|
| Đạt và Tùng | Kyber KEM | Functional baseline PASS; FIPS 203 chưa đạt | [`01_kyber_kem_dat_tung/`](01_kyber_kem_dat_tung/README.md) |
| Minh | Lưu khóa | Có zeroize và không xuất secret; kiến trúc lưu khóa chưa chốt | [`02_luu_khoa_minh/`](02_luu_khoa_minh/README.md) |
| Việt Anh | KDF | SHAKE256 KAT PASS; FIPS 202 coverage còn thiếu | [`03_kdf_viet_anh/`](03_kdf_viet_anh/README.md) |
| Long | RO-PUF | RTL/board/backend split PASS; qualification và ASIC macro còn thiếu | [`04_ro_puf_long/`](04_ro_puf_long/README.md) |

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
