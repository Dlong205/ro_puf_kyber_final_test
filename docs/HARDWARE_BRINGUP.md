# Hướng dẫn bring-up phần cứng XC7Z020

Quy trình này chỉ nạp cấu hình PL volatile. Nó không sửa QSPI flash và không
instantiate Xilinx IP sinh tự động.

## Artifact hiện tại

- Part: `xc7z020clg400-2`
- Clock vào: 50 MHz tại `N18`
- Bitstream build: `build/vivado/kyber_ro_puf_zynq7020.runs/impl_1/Kyber_System_Top.bit`
- SHA-256: `e85e3f2bd0206485aa636b56b9256aae9a38255ab29179f6fb20e37d6b4abdfb`
- Kích thước: 4.045.676 byte
- Setup sau route: WNS `+4.108 ns`, TNS `0 ns`
- Hold sau route: WHS `+0.048 ns`, THS `0 ns`
- Tài nguyên LUT: 51.774/53.200 (`97,32%`)

## Đấu dây

Dùng USB-to-UART 3,3 V và đấu chéo hai tín hiệu UART:

| Tín hiệu board | Chân XC7Z020 | Header mở rộng | Nối với adapter |
|---|---:|---:|---|
| `UART_TXD` | W9 | J24 chân 13 | RX |
| `UART_RXD` | W8 | J24 chân 11 | TX |
| GND | GND board | chân GND đã ghi trong tài liệu | GND |

Không nối tín hiệu UART 5 V vào chân PL. JTAG và USB-UART là hai kết nối riêng;
cần cả hai để chạy kiểm tra đầy đủ.

Hai LED chỉ dùng chẩn đoán:

- LED1/K16: sáng hoặc nhấp nháy khi UART TX hoạt động.
- LED2/J16: được bật khi giao dịch Kyber hoàn thành.

Reset hiện là power-on reset tự động kéo dài 65.536 cycle. Hai phím PL không reset
thiết kế trong bản build này.

## Nạp qua JTAG

Cấp nguồn board, nối JTAG và xác nhận Vivado thấy đúng một XC7Z020. Từ thư mục
gốc dự án, chạy:

```sh
make program VIVADO=/media/donglong/tools/Xilinx/Vivado/2020.1/bin/vivado
```

Kết quả thành công kết thúc bằng `PROGRAM_PASS`. Nạp lại là thao tác volatile an
toàn; ảnh mất khi tắt nguồn board.

Nếu Vivado thấy adapter Digilent nhưng báo `No devices detected on target`, cầu
USB/JTAG đã xuất hiện nhưng FPGA không nằm trong scan chain. Kiểm tra nguồn board,
đầu nối/hướng cáp JTAG và jumper JTAG/boot-mode, sau đó power-cycle rồi chạy lại
`make program`. Trường hợp này từng xảy ra ngày 2026-08-30 trước khi test RC1.

## Smoke test UART

Cài PySerial nếu cần rồi xác định cổng adapter, thường là `/dev/ttyUSB0` hoặc
`/dev/ttyACM0`. Cấu hình UART: 115200, 8 bit dữ liệu, không parity, một stop bit.

Enroll và lưu 33 byte helper data công khai:

```sh
python3 host/uart_host.py --port /dev/ttyUSB0 --helper helper.bin enroll
```

Reconstruct đọc file đó, tái tạo PUF key, sinh seed SHAKE256, chạy loopback
server/client Kyber-512 cũ và kiểm tra kết quả. Giao thức 1.1 tự động retry raw
key mismatch hoặc watchdog stall bằng `m` mới, tối đa 16 attempt. Firmware release
mặc định chỉ trả cờ thành công và không xuất shared secret:

```sh
python3 host/uart_host.py --port /dev/ttyUSB0 --helper helper.bin reconstruct
```

Firmware chỉ gửi `START` một lần sau reset FPGA nên mặc định host không bắt buộc
đợi chuỗi này. Khi cần chẩn đoán startup, chạy lệnh trước lúc reset/nạp FPGA và
thêm `--wait-start`.

## Lộ trình kiểm tra độ tin cậy

Trước hết chạy stress ngắn trong cùng một lần cấp nguồn:

```sh
python3 host/uart_host.py --port /dev/ttyUSB0 --helper helper.bin stress --count 100
```

Sau đó test nhiều power-cycle vật lý và cuối cùng chạy dài:

```sh
python3 host/uart_host.py --port /dev/ttyUSB0 --helper helper.bin stress --count 10000
```

Không xem mô phỏng hoặc một lần reconstruct thành công là qualification RO-PUF.
Phải ghi lỗi reconstruct qua cold/warm start và toàn dải điện áp/nhiệt độ dự kiến.

## Warning implementation đã biết

- 32 warning `LUTLP-2` là các vòng ring oscillator có chủ ý và đã constraint.
- 128 warning `PDCN-1569` đến từ routing LUT của RO được cố ý giữ lại và input
  phương trình LUT logic không dùng.
- Bốn warning `DPOP-2` cho biết bộ nhân NTT của Kyber không dùng pipeline MREG
  trong DSP. Chúng không gây lỗi timing ở 50 MHz.
- 28 warning `REQP-1839/1840` cũ về reset bất đồng bộ nối BRAM đã được xử lý bằng
  reset đồng bộ cho thanh ghi sequencer/status SHA3/Kyber liên quan. Xác nhận số
  lượng bằng 0 trong report DRC sau route của RC.
- `ZPS7-1` là dự kiến với thiết kế chỉ PL không dùng PS7; clock PL ngoài đi qua N18
  và cấu hình được nạp bằng JTAG.
- LUT dùng 97,32%, nên dư địa routing/tính năng rất ít dù implementation hiện đạt timing.
