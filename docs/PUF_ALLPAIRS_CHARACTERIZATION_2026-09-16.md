# Characterization 496 cặp RO-PUF trên Zynq — 2026-09-16

## Kết luận

Hạng mục mở rộng candidate pool từ 256 phép chọn chéo bank sang toàn bộ
`C(32,2)=496` cặp không thứ tự đã **PASS RTL, Vivado và board**. Trong 100 mẫu
ngắn hạn trên một XC7Z020:

- 100/100 frame hợp lệ, mỗi frame đủ đúng 496 cặp từ `(0,1)` đến `(30,31)`;
- 487 cặp đạt `margin p01 >= 4`, lớn hơn yêu cầu chọn 264 vị trí;
- mapping preview chọn đủ 264 cặp, mỗi RO được dùng 16–17 lần;
- mapping preview có margin `p01` nhỏ nhất 4, median 237;
- 2/496 cặp có flip/tie; chúng bị loại khỏi preview;
- không có tam giác chu kỳ trong 4.960 bộ ba RO, phù hợp với một thứ tự tần số
  nhất quán trong phiên đo.

Kết quả giải quyết giới hạn “chỉ 255 challenge duy nhất” của image cũ ở mức
candidate pool. Nó **chưa chốt mapping release**, chưa freeze PUF và không làm
tăng entropy vật lý của 32 RO lên 264 bit.

## Kiến trúc diagnostic

Hai mux đo đều có thể chọn từ cùng 32 đầu ra RO. Scheduler phát đúng một lần
mọi cặp canonical `a < b`. Cặp chỉ thay đổi khi RO đã tắt; controller vẫn có
cửa sổ reset/settle trước mỗi phép đo.

Protocol UART 2.0 dùng lệnh margin `0x71`. Mỗi record 16 byte chứa index,
`pair_a`, `pair_b`, winner/tie, `count0`, `count1` và absolute margin. Host từ
chối index sai, cặp không canonical, cặp sai lịch, reserved bit, winner/tie hay
margin không khớp counter.

Đây là kiến trúc tải mới: mỗi RO lái cả hai cây mux 32:1. Do đó dataset này
không được coi là tương đương physical fingerprint với RC1 hoặc image 16x16.

## Build FPGA

| Thuộc tính | Kết quả |
|---|---:|
| Part | `xc7z020clg400-2` |
| RO LUT | 128/128 |
| LOC/BEL audit | 128 cell, 256 property PASS |
| Slice LUT | 995 (`1,87%`) |
| Register | 1.982 (`1,86%`) |
| BRAM tile | 1,5 |
| Routable net | 2.502/2.502 |
| Routing error | 0 |
| WNS | `+11,186 ns` |
| WHS | `+0,065 ns` |
| TNS/THS | 0/0 |
| Bitstream SHA-256 | `905d8f9b...31639a` |

DRC có 0 Error/Critical Warning. 161 warning còn lại gồm 32 `LUTLP-2`, 128
`PDCN-1569` của cấu trúc RO và 1 `ZPS7-1` do thiết kế PL-only. Không có
`REQP-1839/1840`.

## Kết quả aggregate 100 mẫu

| Ngưỡng margin `p01` | Cặp đạt | Đủ pool N=264 |
|---:|---:|:---:|
| 0 | 494 | Có |
| 1 | 494 | Có |
| 2 | 491 | Có |
| 4 | 487 | Có |
| 8 | 476 | Có |
| 16 | 461 | Có |
| 32 | 440 | Có |

Phân bố `margin p01` trên 496 cặp: minimum 0, P05 9, median 168, P95 562 và
maximum 973. Có 2 cặp xuất hiện flip, 2 cặp xuất hiện tie, tổng 45 tie trong
49.600 phép so sánh; minority count lớn nhất là 7/100.

Winner consensus toàn pool là 225 bit `1`/496. Preview 264 cặp có 117 bit
`1`/264; đây chỉ là kiểm tra bias sơ bộ, không phải entropy estimate.

## Mapping preview và bảo vệ dữ liệu

Host tạo preview bằng margin, flip/tie và giới hạn degree 17. Danh sách cặp,
count và thống kê theo cặp là fingerprint của board, được lưu trong
`reports/puf_allpairs_characterization/private_*.json` và bị `.gitignore`.
Repository chỉ giữ số liệu aggregate trong báo cáo này.

Không đưa preview của một board vào release. Mapping cuối phải được chọn trên
tập training nhiều board/PVT, xác minh trên board holdout, có version/hash và
được ràng buộc với helper/enrollment bằng integrity policy.

## Cổng tiếp theo

1. Thu thập tối thiểu 5 board, ưu tiên 10+, cùng warm/cold boot và PVT an toàn.
2. Chọn mapping 264 cặp từ training set với margin, flip, bias, correlation và
   degree balance; kiểm tra độc lập trên holdout.
3. Tạo mapping manifest có version/hash và test từ chối helper sai mapping.
4. Tích hợp mapping cố định vào đường PUF→BCH, đo same-root và số lỗi BCH sửa.
5. Ước lượng min-entropy/helper leakage; nhớ rằng 496 comparison vẫn chỉ bắt
   nguồn từ 32 tần số RO, với upper bound thứ tự lý tưởng `log2(32!)≈117,66`.
