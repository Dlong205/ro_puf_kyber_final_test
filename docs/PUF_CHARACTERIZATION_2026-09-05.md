# Báo cáo characterization RO-PUF — 2026-09-05

## Kết luận

RO-PUF **đạt gate ổn định ngắn hạn ban đầu** trên một board, một image PUF-only
và điều kiện phòng: 10.000 mẫu có Hamming distance tối đa 1 bit so với mẫu
enrollment riêng, thấp hơn khả năng sửa `t=8` của BCH. Chỉ bit 149 dao động.

Kết quả chưa đủ để freeze hoặc tuyên bố PUF production/golden. Image đo giữ
LOC/BEL theo RC1 nhưng chưa giữ routing và tải của SoC. Chưa có cold/warm boot,
PVT, nhiều board, count-margin, same-root trên image release hoặc ước lượng
min-entropy có tính helper leakage.

Cập nhật sau campaign: route-lock full-SoC đã được xuất từ RC1 và tái tạo chính
xác qua hai build độc lập (136 endpoint, 128 route, gồm cả LUT mux nhận `t3`).
Điều này loại rủi ro route RO đổi giữa các build full-SoC tương lai. Nó không
làm image PUF-only đã đo trở thành tương đương với RC1 và không thay các gate
PVT/same-root/entropy bên dưới.

Image tái lập `locked_b` cũng PASS INFO/enroll/reconstruct và stress
10.000/10.000 trên board, rồi board được nạp lại RC1. Helper enroll giữa hai
image lệch 30 bit, nằm trong kiểu dao động helper đã biết; đây không phải raw
HD và không được dùng để tuyên bố same-root.

Review cũng phát hiện giới hạn kiến trúc: 264 output dùng 32 RO vật lý và 255
challenge duy nhất. Nếu bỏ nhiễu và coi mỗi RO có một tần số vô hướng, output
so sánh là hàm của thứ tự 32 tần số. Số mẫu so sánh khác nhau không vượt
`32!`, tương đương `log2(32!) = 117,663 bit`. Đây là upper bound cấu trúc,
không phải số entropy đo được; entropy thực tế có thể thấp hơn. KDF 512 bit
không làm tăng entropy nguồn. Vì vậy chưa có cơ sở cho tuyên bố root PUF
192-bit hoặc mức an toàn ML-KEM-512 từ PUF hiện tại.

## Định danh image đo

- Top: `Puf_Characterization_Top`
- Part: `xc7z020clg400-2`
- Clock: 50 MHz
- UART: 115200 8N1
- Bitstream SHA-256:
  `53082d99324bfb7c966d70d686be23102c4b8d596edf395b5828be996a302058`
- Seed: `0x42`; `REF_CYCLES=255`; response 264 bit
- LOC/BEL: 128/128 LUT khớp map trích từ checkpoint RC1 ở cả synth và route
- Routing RO: chưa khóa
- Raw response: tool không chủ động ghi response ra file; JSON chỉ chứa thống
  kê. Chính sách swap/core dump của máy đo vẫn cần kiểm soát khi làm lab thật.

Hash trên là hash file local được truyền cho host tool. Giao thức UART v1 chưa
có attestation để tự chứng minh PL đang chạy đúng hash đó; JTAG program PASS
được ghi nhận ngay trước campaign.

## Kết quả FPGA implementation PUF-only

| Hạng mục | Kết quả |
|---|---:|
| Slice LUT | 572; trong đó 128 LUT RO được cố định |
| Register | 1.025 |
| WNS / WHS | `+13,721 ns` / `+0,105 ns` |
| Timing có constraint | PASS |
| DRC Error / Critical Warning | 0 / 0 |
| DRC warning | 32 LUTLP-2; 128 PDCN-1569; 1 ZPS7-1 |

Timing report còn 360 pin `no_clock`, 206 endpoint không có max-delay và 32
loop liên quan miền RO. Vì vậy con số WNS chỉ có ý nghĩa cho logic đồng bộ đã
được ràng buộc, không phải sign-off timing/CDC cho oscillator và counter RO.

## Kết quả raw trên board

Campaign bắt đầu `2026-09-05T10:24:52Z`, kéo dài 67,191 giây. Host lấy một
mẫu enrollment riêng, sau đó đo 10.000 response; tool không tạo file raw.

| Metric | Kết quả |
|---|---:|
| Sample đo | 10.000 + 1 enrollment reference |
| Raw response khác nhau | 2 |
| HD min / mean / p50 / p95 / p99 / max | `0 / 0,3798 / 0 / 1 / 1 / 1` |
| Mẫu có HD > 8 so với enrollment | 0 / 10.000 |
| Bit dao động | 1 / 264: bit 149 |
| Tỷ lệ minority của bit 149 | 37,98% (3.798/10.000) |
| Whole-response mode | 62,02% |
| Transition liên tiếp | 3.776 |
| Response toàn 0 / toàn 1 | 0 / 0 |
| Mismatch ở 9 cặp challenge lặp | 0 / 90.000 phép so sánh |
| Uniformity theo mẫu | 43,1818% đến 43,5606% |

Trong điều kiện này, khoảng cách raw nằm dư 7 bit so với bán kính sửa BCH.
Bit 149 gần biên và cần count-margin/PVT để biết nguyên nhân; việc BCH hiện có
thể sửa nó không biến bit này thành nguồn entropy ổn định.

## Kết quả mô phỏng liên quan

- RO controller/model: PASS busy, timeout, pulse done, deterministic same-seed,
  reset giữa operation và restart.
- UART characterization: PASS cả `CLKS_PER_BIT=16` và đúng board `434`; INFO,
  status + 33 raw byte, mọi giá trị byte, chốt response, lệnh lặp/sai, timeout
  đủ `2^24` cycle và reset giữa giao dịch.
- BCH characterization: 7.728 check, 1.420 ca phục hồi đúng root, mọi vị trí
  lỗi đơn và 128 mẫu cho mỗi trọng số 0–8, gồm data/parity/mixed; reset giữa
  decode/verify và restart đều PASS.
- Giới hạn BCH được tái hiện: XOR một codeword delta trọng số 41 cho
  `success=1` nhưng `wrong_root=1`. BCH không thể phát hiện mọi lỗi vượt `t`.
- Host metric: 5 unit test PASS, gồm consensus không phải mẫu quan sát, fixed
  enrollment khác post-hoc consensus, challenge lặp và stuck capture.

## Ý nghĩa đối với kết quả 10.000 giao dịch cũ

Firmware release dùng `fe_success` để chấp nhận codeword, rồi dùng khóa vừa
phục hồi tạo seed cho cả Kyber server và client. Vì hai phía dùng cùng khóa mới,
KEM vẫn có thể match nếu FE lặng lẽ trả một root hợp lệ khác. Do đó kết quả
10.000/10.000 trước đây chứng minh giao thức/KEM không timeout hoặc mismatch;
nó chưa trực tiếp đo same-root với enrollment.

Phép đo raw PUF-only cùng kiểm thử BCH cho thấy cùng-root sẽ được giữ trong
10.000 mẫu của campaign này, vì raw error tối đa 1. Không được chuyển kết luận
đó sang bitstream RC1 cho tới khi routing/loading tương đương hoặc có phép đo
same-root trực tiếp trên image tích hợp.

## Gate tiếp theo

1. Thêm telemetry `count0`, `count1`, tie/zero và `abs(count0-count1)` để phát
   hiện RO không chạy hoặc challenge sát biên; ưu tiên bit 149.
2. Chốt chiến lược entropy: tăng số nguồn vật lý độc lập/đổi kiến trúc response
   hoặc hạ tuyên bố entropy; đo min-entropy và helper leakage trên nhiều board.
3. Thêm kiểm tra same-root dành cho qualification, không xuất root trong image
   release.
4. Chạy ít nhất 100 warm reset, 100 cold power-cycle, PVT an toàn, aging và
   tối thiểu 5 board (nên 10+), luôn gắn dataset với bitstream hash.
5. Giữ audit route-lock full-SoC trong mọi build; bổ sung phép đo same-root hoặc
   instrumentation trên chính image tích hợp trước khi freeze PUF.

Sau campaign, board đã được nạp lại bitstream ML-KEM RC1. INFO protocol 1.2,
enroll/reconstruct và stress 100/100 PASS; artifact root và bitstream build cùng
SHA-256 `183e0af367376ebd7ca6bc2f3747314fd0602306a630af2a2e51858ef1f20e8e`.

Số liệu máy đọc nằm tại
`reports/puf_characterization/raw_stability_room_10000_2026-09-05.json`.
