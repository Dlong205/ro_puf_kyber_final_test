# Kế hoạch qualification RO-PUF

## Kết luận hiện tại

Board regression 10.000/10.000 xác nhận các giao dịch báo thành công trong
một phiên nguồn. Review ngày 2026-09-05 cho thấy phép thử **chưa kiểm tra khóa
phục hồi có bằng khóa enroll**: FE kiểm tra codeword BCH hợp lệ; firmware dùng
khóa vừa phục hồi để chạy cả hai phía KEM, nên hai phía vẫn có thể khớp khi
khóa gốc đã đổi. Cần kiểm tra same-root riêng trước khi kết luận ổn định.
Release firmware cũng chưa xuất raw response hoặc số lỗi BCH đã sửa.

Phép đo proxy ngày 2026-09-04 trên một board, một bitstream và điều kiện phòng:

- helper enroll lặp 1.000 lần: 2 giá trị; HD lớn nhất so với mẫu đầu là 29;
- helper enroll lặp 10.000 lần: 4 giá trị;
- giá trị chủ đạo: 9.370/10.000 (`93,70%`);
- ba giá trị còn lại: 625 (`6,25%`), 4 (`0,04%`) và 1 (`0,01%`);
- HD helper so với mode: 29, 36 và 37;
- reconstruct bằng helper tạo trước khi PL mất cấu hình rồi được nạp lại: PASS.

Khoảng cách helper không phải raw-response Hamming distance. Một raw data-bit
thay đổi có thể làm nhiều parity-bit BCH thay đổi, vì vậy không được diễn giải
HD helper 29 là 29 raw bit lỗi. Kết quả xác nhận helper có dao động; các lượt
reconstruct đã thử báo thành công, chưa có phép đối chiếu same-root.

## Phase A — Gate release-mode không xâm lấn

1. Enroll một helper chuẩn và giữ ngoài repository.
2. Reconstruct 10.000 lần trong cùng phiên nguồn; bổ sung đối chiếu khóa enroll
   trong môi trường chẩn đoán riêng (không công bố raw key hoặc fingerprint).
3. Reconstruct lại bằng đúng helper sau mỗi lần nạp lại PL.
4. Chạy helper proxy để phát hiện thay đổi thống kê mà không lưu raw helper:

```sh
make puf-stability-proxy PUF_SAMPLES=10000
```

5. Lặp tối thiểu 100 warm reset và 100 cold power-cycle. Mỗi vòng ghi timestamp,
   số thứ tự boot, nhiệt độ/điện áp nếu có và kết quả decode.

Gate nghiên cứu sơ bộ: failure/timeout và sai khóa gốc đều bằng 0. Rule-of-three
`3/10.000` chỉ có ý nghĩa với sự kiện đã được đo đúng và giả định các trial
độc lập; các run hiện tại chỉ đo failure/timeout báo qua giao thức, chưa đo
silent wrong-root, PVT hay phụ thuộc theo thời gian.

## Phase B — Bitstream characterization raw PUF

Tạo image chẩn đoán riêng, không thay artifact release và không bật trong
firmware production. Image phải xuất:

- raw response 264 bit;
- `count0`, `count1` hoặc ít nhất `abs(count0-count1)` cho từng challenge;
- seed/challenge index, measurement-window và boot/session index;
- số lỗi BCH đã sửa và cờ over-noise.

XDC release khóa LUT pin và giữ vòng feedback, chưa khóa `LOC/BEL` từng RO.
Image `Puf_Characterization_Top` dùng map trích từ RC1 và kiểm tra chính xác
128 LUT × 2 thuộc tính ở synth/post-route. Map chỉ cố định vị trí LUT; chưa
cố định routing, mux/counter hoặc tải hoạt động của SoC. Vì vậy dataset từ
image PUF-only phải có SHA-256 bitstream riêng và **không gộp với dataset RC1**.
Để đo trực tiếp RC1 cần instrumentation tích hợp, đối chiếu routing/loading
hoặc giải pháp quan sát không làm đổi implementation.

Image chẩn đoán v1 chỉ xuất raw 264 bit qua UART (`INFO=0x00`, `RAW=0x70`).
Các trường count-margin và số lỗi BCH bên dưới vẫn là hạng mục tiếp theo,
chưa được coi là hoàn thành bởi phép đo raw v1.

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

## Các khoảng trống phải giải quyết trước khi freeze PUF

- `success` BCH là kiểm tra codeword, không phải xác thực khóa enroll. Nhiễu
  vượt `t` có thể chuyển sang codeword hợp lệ khác; không thể yêu cầu BCH
  phát hiện mọi mẫu lỗi trên 8 bit. Thêm kiểm tra same-root và chính sách
  xác thực helper/khóa phù hợp threat model.
- LFSR 8 bit, seed `0x42`, lặp sau 255 challenge; 264 phép đo lặp lại 9
  challenge đầu. Phải đánh giá tương quan và không coi 264 bit là độc lập.
- INIT LUT FPGA không dùng các chân `cfg` để đổi hàm logic RO; challenge
  chọn cặp trong 32 RO. Độ dài FE 192 bit/KDF 512 bit không chứng minh entropy
  tương ứng. Cần dữ liệu nhiều board và mô hình entropy có tính helper leakage.
- CDC/RDC và timing của counter/comparator thuộc miền RO còn cần kiểm tra
  vật lý; mô hình RO xác định trong mô phỏng không chứng minh độ ổn định PVT.
