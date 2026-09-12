# Báo cáo bring-up RO-PUF trên Arty A7-35T — 2026-09-10

## Kết luận

Ảnh characterization-only đã được build, route, đạt timing 100 MHz, nạp
volatile và giao tiếp UART thành công trên một Arty A7-35T. Campaign 10.000
mẫu ở điều kiện phòng có khoảng cách Hamming tối đa 6 bit so với mẫu enrollment;
không mẫu nào vượt bán kính BCH `t=8`. Đây là **PASS bring-up sơ bộ**, không
phải qualification hoặc release PUF.

## Định danh

| Thuộc tính | Giá trị |
|---|---|
| Board/part | Arty A7-35T / `xc7a35ticsg324-1L` |
| JTAG | Digilent `210319A27898A`, device `xc7a35t_0` |
| Top | `Puf_Characterization_Top` |
| Clock/UART | 100 MHz / 115200 baud |
| Bitstream SHA-256 | `8745921eb230ee14436cc2816b65b2995a5adeee78ee3b13acdbc34a67598d6b` |
| Kiểu nạp | Volatile JTAG; không ghi QSPI |

## Build vật lý

- 128 LUT RO và 128 feedback net tồn tại sau synthesis; 128 LUT còn nguyên
  sau route.
- 574/20.800 LUT (2,76%); ảnh này chỉ chứa PUF và protocol đo.
- Timing 100 MHz: WNS `+4,532 ns`, WHS `+0,044 ns`, TNS/THS `0`.
- Synthesis báo 32 critical warning về timing loop RO có chủ đích. DRC sau
  route không có Error/Critical Warning; có 32 `LUTLP-2` cho 32 vòng RO và 128
  `PDCN-1569` do các chân cấu hình LUT được nối nhưng không xuất hiện trong
  phương trình LUT; hai nhóm này đã được phân loại, chưa được coi là sign-off
  silicon.
- Pin E3/A9/D10/H5/J5/A8/C11 theo master XDC của Digilent. `CFGBVS=VCCO` và
  `CONFIG_VOLTAGE=3.3` đã khai báo; cảnh báo `CFGBVS-1` không còn.

## Campaign 10.000 mẫu

| Chỉ số | Kết quả |
|---|---:|
| HD so với enrollment: mean / p95 / p99 / max | 1,5319 / 3 / 4 / 6 bit |
| Mẫu vượt BCH `t=8` | 0/10.000 |
| HD so với consensus: mean / max | 1,5319 / 6 bit |
| Bit từng dao động | 36/264 |
| Flip-rate tệ nhất của bit biên | 37,46% |
| Response khác nhau | 477/10.000 |
| Mode rate của toàn response | 16,67% |
| Uniformity trung bình | 36,689% bit 1 |
| Challenge lặp lại trong response | 31/90.000 mismatch (0,0344%) |
| Response toàn 0 / toàn 1 | 0 / 0 |

Tóm tắt máy đọc nằm tại
`reports/arty_puf_characterization/hardware_raw_10000.json`; file không chứa
raw response. Campaign 1.000 mẫu trước đó được giữ cạnh bên để đối chiếu.
Test protocol mô phỏng và 5 unit test metric đều PASS.

## Giới hạn và quyết định

- Chỉ đo một board, một lần cấp nguồn và nhiệt độ/điện áp phòng; chưa có
  cold/warm boot, power-cycle, PVT, aging hoặc inter-device uniqueness.
- Placement LOC/BEL và routing RO của ảnh này **chưa khóa**. Không dùng helper
  hoặc enrollment của ảnh characterization này cho ảnh Edge sau đó.
- Uniformity 36,7% và sáu bit có flip-rate trên 14% cho thấy cần margin theo
  bit và qualification thật; PASS BCH trong 10.000 mẫu không đủ để freeze PUF.
- `edge_puf_mlkem_core` 94,07% LUT mới là OOC synthesis; ảnh nhỏ này không
  chứng minh full Edge place/route hoặc chạy board.

Quyết định: giữ kết quả làm baseline bring-up. Bước đúng tiếp theo là hoàn
thiện board top/transport tối thiểu của Edge, full P&R trên A7-35T, sau đó mới
khóa placement/route RO từ checkpoint Edge được chấp nhận và enroll lại.

## Kiểm tra lại sau khi cắm board — 2026-09-12

Board Digilent `210319A278D0A` được nhận qua JTAG/UART, ảnh PUF-only cùng hash
ở trên được nạp volatile và thu 1.000 mẫu mới. HD so với consensus có mean
`1,554`, p99 `4`, max `5`; HD so với mẫu enrollment có mean `2,188`, max `5`.
Không có mẫu nào vượt BCH `t=8`, uniformity trung bình `48,211%` và không có
response toàn 0/toàn 1.

Kết quả này chỉ xác nhận biên sửa lỗi tại điều kiện hiện tại. Có 11 bit từng
dao động; bit 218 có minority rate `45,4%`, bit 121 `40,1%` và bit 228 `32,0%`.
Do placement/routing RO vẫn chưa khóa, đây là **PASS sanity/ECC margin nhưng
NO-GO cho PUF freeze**. Tóm tắt không chứa raw response nằm tại
`reports/arty_puf_characterization/hardware_replug_sanity_1000_2026-09-12.json`.
