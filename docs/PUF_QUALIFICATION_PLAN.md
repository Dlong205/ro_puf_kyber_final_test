# Kế hoạch qualification RO-PUF

## Kết luận hiện tại

Board regression 10.000/10.000 chứng minh pipeline reconstruct end-to-end ổn
định trong một phiên nguồn. Nó chưa đủ để kết luận raw RO-PUF ổn định hoặc có
entropy phù hợp production vì release firmware không xuất raw response và không
báo số lỗi BCH đã sửa.

Phép đo proxy ngày 2026-09-04 trên một board, một bitstream và điều kiện phòng:

- helper enroll lặp 1.000 lần: 2 giá trị; HD lớn nhất so với mẫu đầu là 29;
- helper enroll lặp 10.000 lần: 4 giá trị;
- giá trị chủ đạo: 9.370/10.000 (`93,70%`);
- ba giá trị còn lại: 625 (`6,25%`), 4 (`0,04%`) và 1 (`0,01%`);
- HD helper so với mode: 29, 36 và 37;
- reconstruct bằng helper tạo trước khi PL mất cấu hình rồi được nạp lại: PASS.

Khoảng cách helper không phải raw-response Hamming distance. Một raw data-bit
thay đổi có thể làm nhiều parity-bit BCH thay đổi, vì vậy không được diễn giải
HD helper 29 là 29 raw bit lỗi. Kết quả chỉ đủ để khẳng định có dao động quan sát
được và fuzzy extractor đã xử lý được các mẫu được thử.

## Phase A — Gate release-mode không xâm lấn

1. Enroll một helper chuẩn và giữ ngoài repository.
2. Reconstruct 10.000 lần trong cùng phiên nguồn.
3. Reconstruct lại bằng đúng helper sau mỗi lần nạp lại PL.
4. Chạy helper proxy để phát hiện thay đổi thống kê mà không lưu raw helper:

```sh
make puf-stability-proxy PUF_SAMPLES=10000
```

5. Lặp tối thiểu 100 warm reset và 100 cold power-cycle. Mỗi vòng ghi timestamp,
   số thứ tự boot, nhiệt độ/điện áp nếu có và kết quả decode.

Gate nghiên cứu sơ bộ: failure/timeout bằng 0. Với 10.000 lần không lỗi, cận trên
95% gần đúng của failure rate vẫn khoảng `3/10.000`; chưa đủ cho production.

## Phase B — Bitstream characterization raw PUF

Tạo image chẩn đoán riêng, không thay artifact release và không bật trong
firmware production. Image phải xuất:

- raw response 264 bit;
- `count0`, `count1` hoặc ít nhất `abs(count0-count1)` cho từng challenge;
- seed/challenge index, measurement-window và boot/session index;
- số lỗi BCH đã sửa và cờ over-noise.

Phải giữ placement của 32 RO giữa các build. XDC hiện khóa LUT pin và giữ vòng
feedback nhưng chưa khóa `LOC/BEL` từng RO; vì vậy cần tạo placement map cố định
trước khi so response giữa bitstream. Nếu placement/routing thay đổi, đó là một
PUF instance khác và không được gộp chung dataset.

Các metric cần tính:

- intra-device HD so với enrollment reference;
- per-bit flip probability và danh sách unstable bit;
- khoảng cách count margin của từng challenge;
- uniformity của response;
- inter-device HD và bit-alias khi có nhiều board;
- fuzzy-extractor failure rate theo từng điều kiện.

Gate ban đầu với BCH `t=8`: mọi mẫu dùng helper cố định phải có raw error count
không vượt 8; nên đặt margin nội bộ chặt hơn, ví dụ percentile 99 nhỏ hơn hoặc
bằng 4, để còn dư địa cho PVT/aging. Ngưỡng production phải được chọn từ threat
model và dữ liệu thực, không lấy heuristic này làm chứng nhận.

## Phase C — Ma trận điều kiện

| Chiến dịch | Số lượng tối thiểu | Mục tiêu |
|---|---:|---|
| Cùng nguồn, điều kiện phòng | 10.000 sample/board | Short-term noise |
| Warm reset | 100 boot/board | Reset/restart stability |
| Cold power-cycle | 100 boot/board | Helper persistence |
| Nhiệt độ thấp/phòng/cao | 1.000 sample/điểm | Temperature drift |
| Điện áp danh định và biên an toàn | 1.000 sample/điểm | Voltage sensitivity |
| Nhiều board | Tối thiểu 5, nên 10+ | Uniqueness/bit-alias |
| Burn-in theo thời gian | 1 h, 8 h, 24 h | Temporal drift |

Không tự thay đổi điện áp hoặc nhiệt độ ngoài giới hạn board. Mọi phép thử PVT
phải ghi thiết bị đo, điều kiện môi trường và giới hạn an toàn.

## Điều kiện để gọi RO-PUF ổn định

Chỉ chốt sau khi có raw dataset và báo cáo tái lập được:

1. fixed-helper reconstruct đạt failure target ở mọi điều kiện;
2. raw intra-HD nằm trong khả năng sửa của BCH với margin đã chốt;
3. không có nhóm challenge có count margin sát zero chưa xử lý;
4. uniqueness/bit-alias được đo trên nhiều board;
5. CDC/RDC và reset miền RO được review hoặc có waiver cụ thể;
6. dataset raw/helper thật không được commit vào repository công khai.
