# Báo cáo count-margin RO-PUF trên Zynq — 2026-09-16

## Kết luận

Hạng mục instrumentation `count0/count1/count-margin` đã **PASS chức năng và
PASS board** trên một XC7Z020 trong một phiên nguồn. Kết quả đủ để phát hiện
một giới hạn kiến trúc, nhưng **chưa đủ để freeze PUF**:

- 100/100 frame UART hợp lệ, mỗi frame có đủ 264 bản ghi tuần tự;
- không có winner flip và không có tie trong tập 100 mẫu ngắn hạn;
- margin nhỏ nhất quan sát được là 2 count; median của per-position `p01` là
  158 count;
- 264 vị trí chỉ tạo ra 255 challenge duy nhất; 9 challenge đầu bị lặp;
- nếu yêu cầu `margin p01 >= 4`, chỉ còn 263 vị trí/254 challenge duy nhất,
  không đủ để cấp trực tiếp 264 bit cho BCH hiện tại.

Vì vậy không được tạo một reliability mask tùy ý rồi vẫn tuyên bố đầu vào
fuzzy extractor dài 264 bit. Bước thiết kế tiếp theo phải mở rộng candidate
pool/challenge space, hoặc thay đổi hợp đồng fuzzy extractor. Bỏ bit rồi lặp
lại bit khác không tạo thêm entropy.

## Phạm vi image và build

- Top chẩn đoán: `Puf_Characterization_Top`.
- Target: `xc7z020clg400-2`, system clock 50 MHz.
- Giao thức chẩn đoán: 1.1, lệnh raw `0x70`, lệnh margin `0x71`.
- Bitstream SHA-256:
  `20b621c7de06a97b84ef7240f109c0bc9b00603c12ab54ceb268bfc6fdd32d91`.
- 128 RO LUT khớp chính xác 128 LOC/BEL trong placement map.
- Route hoàn tất, WNS `+10,770 ns`, WHS `+0,091 ns`, TNS/THS bằng 0.
- Tài nguyên: 725 Slice LUT, 1.270 register và 1,5 BRAM tile.
- DRC: 0 Error/Critical Warning; 161 warning đã biết gồm 32 `LUTLP-2`,
  128 `PDCN-1569` của RO và 1 `ZPS7-1`. Không còn `REQP-1839/1840`.

Image này là ảnh đo riêng. Nó không thay thế artifact ML-KEM RC1 và dữ liệu
của nó không được gộp với dataset full-SoC RC1 nếu chưa chứng minh tương đương
loading/routing/điều kiện hoạt động.

## Giao thức và kiểm tra nhất quán

Mỗi bản ghi 16 byte chứa index, challenge, winner/tie, `count0`, `count1` và
`abs(count0-count1)`. Host từ chối frame khi index sai, cờ reserved được bật,
winner không khớp hai counter, margin không khớp hoặc tie sai.

RTL/testbench đã kiểm tra INFO, raw response, đủ 264 bản ghi margin, trường hợp
bản ghi cuối và `puf_done` cùng chu kỳ, timeout, reset giữa giao dịch và lệnh
không hợp lệ. Bộ phân tích host có unit test cho frame hỏng, threshold sweep và
challenge lặp.

## Kết quả aggregate 100 mẫu

| Chỉ số | Kết quả |
|---|---:|
| Frame hợp lệ | 100/100 |
| Vị trí mỗi frame | 264 |
| Challenge duy nhất | 255 |
| Nhóm challenge lặp | 9 |
| Vị trí có winner flip | 0 |
| Vị trí có tie | 0 |
| Minimum của margin per-position | 2 |
| Median của margin `p01` per-position | 158 |
| P95 của margin `p01` per-position | 497 |

Threshold sweep dùng `minority rate <= 1%`, không tie:

| Ngưỡng margin `p01` | Vị trí đạt | Challenge duy nhất | Đủ N=264 |
|---:|---:|---:|:---:|
| 0 | 264 | 255 | Có về chiều dài, không độc lập |
| 1 | 264 | 255 | Có về chiều dài, không độc lập |
| 2 | 264 | 255 | Có về chiều dài, không độc lập |
| 4 | 263 | 254 | Không |
| 8 | 259 | 250 | Không |
| 16 | 255 | 246 | Không |
| 32 | 232 | 223 | Không |

Không có flip trong 100 mẫu cùng phiên nguồn chỉ là bằng chứng ngắn hạn. Nó
không chứng minh cold-boot, PVT, aging, uniqueness hay entropy.

## Bảo vệ dữ liệu

JSON chi tiết chứa đặc trưng vật lý theo challenge và được lưu cục bộ dưới tên
`reports/puf_characterization/private_*.json`. Mẫu tên này đã được ignore và
không được đưa lên repository công khai. Tài liệu này chỉ giữ số liệu aggregate
không đủ để tái tạo fingerprint của thiết bị.

## Quyết định cho hạng mục kế tiếp

1. Không đưa fixed reliability mask vào artifact release hiện tại.
2. Mở rộng candidate pool trước khi chọn 264 vị trí ổn định; đồng thời loại
   challenge lặp và định danh mapping bằng version/hash.
3. Sau khi chốt mapping, chạy lại 10.000 mẫu, warm/cold boot, PVT và nhiều board.
4. Kiểm tra same-root bằng reference enroll cố định và ghi số lỗi BCH thực sửa.
5. Chỉ freeze PUF khi entropy/helper-leakage và failure target đều có bằng chứng.

