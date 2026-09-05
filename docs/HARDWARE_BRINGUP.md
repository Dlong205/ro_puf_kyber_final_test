# Hướng dẫn bring-up phần cứng XC7Z020

Quy trình chỉ nạp cấu hình PL volatile, không ghi QSPI và không dùng Xilinx IP
sinh tự động.

## Artifact ML-KEM-512 `0.2.0-rc1`

- Part: `xc7z020clg400-2`
- Clock: 50 MHz tại N18
- Bitstream: `Kyber_System_Top.bit`, 4.045.676 byte
- SHA-256: `183e0af367376ebd7ca6bc2f3747314fd0602306a630af2a2e51858ef1f20e8e`
- Timing: WNS `+2,226 ns`, WHS `+0,034 ns`, TNS/THS `0`
- LUT: 49.909/53.200 (`93,81%`)
- Protocol: 1.2, release capability `0x06`, không retry

## Đấu dây

Dùng USB-UART mức 3,3 V:

| Board | Chân FPGA | Header | Adapter |
|---|---:|---:|---|
| `UART_TXD` | W9 | J24-13 | RX |
| `UART_RXD` | W8 | J24-11 | TX |
| GND | GND | GND | GND |

Không nối UART 5 V vào PL. JTAG và USB-UART là hai kết nối riêng. LED1/K16 báo
hoạt động UART TX; LED2/J16 báo giao dịch Kyber hoàn tất. Reset power-on kéo dài
65.536 cycle; hai phím PL không reset thiết kế trong image này.

## Nạp JTAG

```sh
sha256sum -c ARTIFACTS.sha256
make program VIVADO=/media/donglong/tools/Xilinx/Vivado/2020.1/bin/vivado
```

Thành công kết thúc bằng `PROGRAM_PASS`. Nếu JTAG thấy adapter nhưng không thấy
device, kiểm tra nguồn, hướng cáp và jumper JTAG/boot-mode rồi power-cycle.

Để nạp một candidate cách ly thay vì bitstream mặc định, luôn chỉ rõ file:

```sh
make program-bit \
  BITSTREAM=/duong/dan/tuyet/doi/Kyber_System_Top.bit \
  VIVADO=/media/donglong/tools/Xilinx/Vivado/2020.1/bin/vivado
```

Script xác nhận đúng một target và đúng một XC7Z020 trước khi ghi PL.

## Smoke test UART

UART 115200 8N1. Xác nhận firmware trước:

```sh
python3 host/uart_host.py --port /dev/ttyUSB1 info
```

Response release mong đợi: protocol 1.2, capability `0x06`, shared-secret export
tắt, session diversification và zeroize bật, retry flag tắt.

Giữ helper bên ngoài repo:

```sh
python3 host/uart_host.py --port /dev/ttyUSB1 --helper ../helper-private.bin enroll
python3 host/uart_host.py --port /dev/ttyUSB1 --helper ../helper-private.bin reconstruct
```

Reconstruct thành công phải đi qua marker `ABCDEFG` và trả success không kèm
secret trong release mode. Kyber chỉ chạy một attempt; timeout/mismatch trở thành
lỗi giao dịch nhìn thấy được, sau đó core được zeroize.

## Stress

Chạy theo nấc, không mở hai host cùng một cổng UART:

```sh
python3 -u host/uart_host.py --port /dev/ttyUSB1 --helper ../helper-private.bin stress --count 100
python3 -u host/uart_host.py --port /dev/ttyUSB1 --helper ../helper-private.bin stress --count 1000
python3 -u host/uart_host.py --port /dev/ttyUSB1 --helper ../helper-private.bin stress --count 10000
```

ML-KEM RC1 PASS lần lượt 100/100, 1.000/1.000 và 10.000/10.000. Run dài có
latency 29,608 ms/giao dịch, throughput 33,775 giao dịch/s. Khi host báo
timeout, không tiếp tục gửi lệnh lên luồng mất đồng bộ; nạp lại bitstream rồi
chạy INFO.

## Warning implementation đã biết

- 32 `LUTLP-2`: 32 vòng ring oscillator có chủ ý, đã constraint.
- 128 `PDCN-1569`: input LUT không dùng trong cấu trúc RO được giữ.
- 4 `DPOP-2`: DSP NTT không dùng MREG; timing 50 MHz vẫn đạt.
- 1 `ZPS7-1`: dự kiến vì thiết kế pure-PL không dùng PS7.
- `REQP-1839/1840`: 0 sau khi reset sequencer/status liên quan BRAM được đồng bộ.
- Methodology có 72 `TIMING-17` vì clock RO bất định không được khai báo timing
  clock; report CDC tự động không thay thế review CDC/RDC cho miền RO.

Thiết kế dùng 93,81% LUT nên không tăng clock hay thêm logic mà không chạy lại
implementation/timing/DRC.

## Qualification còn thiếu

Một run dài không thay thế test cold/warm power-cycle, nhiều board, điện áp,
nhiệt độ, aging, entropy/uniqueness hoặc side-channel/fault-injection. Ghi rõ
điều kiện nguồn/nhiệt khi thực hiện các chiến dịch tiếp theo.
