# Bring-up Edge trên Zynq-7020 ở 100 MHz — 2026-09-17

## Kết luận

Full Edge gồm RO-PUF, fuzzy extractor, SHAKE256 KDF compact, ML-KEM-512
KeyGen/Decaps và UART **fit và đạt timing ở 100 MHz** trên
`xc7z020clg400-2`. Clock ngoài của board vẫn là 50 MHz tại N18; một
`PLLE2_BASE` trong board shell tạo clock core 100 MHz. Thiết kế không dùng
Xilinx IP sinh tự động và primitive clock không đi vào ASIC file list.

Kết quả implementation trước bản sửa handshake cuối:

| Chỉ số | Kết quả |
|---|---:|
| Clock vào / clock core | 50 MHz / 100 MHz |
| WNS / WHS | `+0,326 ns` / `+0,041 ns` |
| Routing error | 0 |
| Slice LUT | 20.997 / 53.200 (39,47%) |
| Slice register | 19.907 / 106.400 (18,71%) |
| BRAM tile / DSP | 14 / 2 |
| PLL / BUFG | 1 / 4 |
| RO đã tìm thấy/đặt cố định | 128 / 128 |

Bitstream này đã được nạp volatile và PASS `INFO`, `ENROLL`, tạo đủ public
key. Test SESSION ban đầu treo sau khi nhận ciphertext. Mô phỏng tích hợp mới
đã tái hiện đúng lỗi này và xác định nguyên nhân không phải timing: UART
transport hạ `ready_c` ngay sau word ciphertext thứ 192, trong khi NTT Server
vẫn cần tín hiệu này ở state nội bộ `0x0e` để đi vào CCA datapath.

## Bản sửa chức năng

Transport hiện tại:

1. đệm đủ 192 word (768 byte) trước khi báo `ready_c`;
2. cấp liên tục toàn bộ ciphertext khi Server yêu cầu;
3. giữ `ready_c` đến `secret_valid`, giống contract của `Kyber_Client`;
4. chỉ sau đó xóa trạng thái sẵn sàng và trả kết quả UART.

Các gate đã PASS sau sửa:

- UART transport bit-level unit test;
- Edge ML-KEM valid và invalid ciphertext, cùng latency 19.800 cycle;
- integration thật `UART -> Kyber_Server` với public key 800 byte và
  ciphertext 768 byte do `Kyber_Client` RTL tạo;
- Server `equal=1`, shared secret Client/Server bằng nhau và result tag đúng.

Chạy lại bằng:

```sh
make -j1 edge-uart
make -j1 edge-uart-mlkem
make -j1 -C sim/edge_mlkem clean check
```

## Trạng thái phần cứng cuối

Chưa được phép gọi bitstream implementation ở bảng trên là artifact cuối vì
nó được tạo trước thay đổi giữ `ready_c`. Bản sửa chỉ thêm một thay đổi control
nhỏ nhưng vẫn phải build lại, xác nhận timing/DRC, nạp đúng hash và chạy SESSION
trên board. Tại thời điểm chốt báo cáo này, ổ chứa Vivado chưa được mount nên
cổng build lại đang **PENDING**, không phải FAIL.

Điều kiện đóng hạng mục:

- build sạch top `Edge_Zynq_Diagnostic_100MHz_Top`;
- WNS/WHS không âm, routing error = 0, DRC không có Error/Critical Warning;
- ghi SHA-256 bitstream mới;
- nạp volatile và PASS INFO, ENROLL, SESSION với ciphertext hợp lệ;
- sau test, phục hồi image RC1 nếu tiếp tục dùng board cho baseline release.

