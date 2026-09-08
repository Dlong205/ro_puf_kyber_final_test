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

Đây là hướng dẫn mặc định cho artifact RC1 ở root. Candidate v4 dùng protocol
1.3 và accelerator-zeroize sâu; đúng build cách ly `candidate_v4_final` đã PASS
Vivado/board ngày 2026-09-08. Không dùng file root để tái kiểm v4: phải nạp
`build/soc_repro/candidate_v4_final/kyber_ro_puf_candidate_v4_final.runs/impl_1/Kyber_System_Top.bit`,
kiểm SHA-256
`bc3a8ab8cac94c00ad3f02f5c3165ff9f8bbacf13db7ba0952003bb90946260a`
và mong đợi INFO `4B 50 01 03 06`.

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
VIVADO_BIN=/absolute/path/to/Vivado/2020.1/bin/vivado
make program-bit BITSTREAM="$PWD/Kyber_System_Top.bit" VIVADO="$VIVADO_BIN"
```

Thành công kết thúc bằng `PROGRAM_PASS`. Nếu JTAG thấy adapter nhưng không thấy
device, kiểm tra nguồn, hướng cáp và jumper JTAG/boot-mode rồi power-cycle.
Luôn dùng `program-bit` với đường dẫn tuyệt đối khi xác nhận artifact: target
`program` có thể ưu tiên một bitstream mới còn tồn tại trong `build/vivado/`.

Để nạp một candidate cách ly thay vì bitstream mặc định, luôn chỉ rõ file:

```sh
make program-bit \
  BITSTREAM=/absolute/path/to/Kyber_System_Top.bit \
  VIVADO=/absolute/path/to/Vivado/2020.1/bin/vivado
```

Script xác nhận đúng một target và đúng một XC7Z020 trước khi ghi PL.

## Smoke test UART

UART 115200 8N1. Xác nhận firmware trước:

```sh
PORT=/dev/serial/by-id/usb-1a86_USB_Serial-if00-port0
python3 host/uart_host.py --port "$PORT" info
```

Với artifact RC1 root, response mong đợi là protocol 1.2/capability `0x06`.
Với candidate v4, phải thấy protocol 1.3/capability `0x06`; bit 2 khi đó là
crypto-accelerator zeroize. Cả hai đều tắt shared-secret export và retry flag.

Giữ helper bên ngoài repo:

```sh
python3 host/uart_host.py --port "$PORT" --helper ../helper-private.bin enroll
python3 host/uart_host.py --port "$PORT" --helper ../helper-private.bin reconstruct
```

Reconstruct thành công phải đi qua marker `ABCDEFG` và trả success không kèm
secret trong release mode. Kyber chỉ chạy một attempt; timeout/mismatch trở thành
lỗi giao dịch nhìn thấy được, sau đó core được zeroize.

## Stress

Chạy theo nấc, không mở hai host cùng một cổng UART:

```sh
python3 -u host/uart_host.py --port "$PORT" --helper ../helper-private.bin stress --count 100
python3 -u host/uart_host.py --port "$PORT" --helper ../helper-private.bin stress --count 1000
python3 -u host/uart_host.py --port "$PORT" --helper ../helper-private.bin stress --count 10000
```

ML-KEM RC1 PASS lần lượt 100/100, 1.000/1.000 và 10.000/10.000. Run dài có
latency 29,608 ms/giao dịch, throughput 33,775 giao dịch/s. Khi host báo
timeout, không tiếp tục gửi lệnh lên luồng mất đồng bộ; nạp lại bitstream rồi
chạy INFO.

Candidate v4 đúng image cũng PASS 100/100, 1.000/1.000 và 10.000/10.000; fail
0. Run 10.000 đạt 29,694 ms/giao dịch và 33,677 giao dịch/s. Báo cáo đầy đủ ở
[`HARDWARE_TEST_REPORT_CRYPTO_CANDIDATE_V4_2026-09-08.md`](HARDWARE_TEST_REPORT_CRYPTO_CANDIDATE_V4_2026-09-08.md).

## Warning implementation đã biết

- 32 `LUTLP-2`: 32 vòng ring oscillator có chủ ý, đã constraint.
- 128 `PDCN-1569`: input LUT không dùng trong cấu trúc RO được giữ.
- 4 `DPOP-2`: DSP NTT không dùng MREG; timing 50 MHz vẫn đạt.
- 1 `ZPS7-1`: dự kiến vì thiết kế pure-PL không dùng PS7.
- `REQP-1839/1840`: 0 sau khi reset sequencer/status liên quan BRAM được đồng bộ.
- Methodology có 72 `TIMING-17` vì clock RO bất định không được khai báo timing
  clock; report CDC tự động không thay thế review CDC/RDC cho miền RO.

Artifact RC1 dùng 93,81% LUT. Candidate v4 dùng 95,68% LUT và 99,87% slice
(chỉ còn 17/13.300 slice), nên không tăng clock hay thêm logic mà không chạy
lại implementation/timing/DRC/capacity audit. Xem
[`VIVADO_IMPACT_REPORT_CRYPTO_CANDIDATE_V4_2026-09-08.md`](VIVADO_IMPACT_REPORT_CRYPTO_CANDIDATE_V4_2026-09-08.md).

## Qualification còn thiếu

Một run dài không thay thế test cold/warm power-cycle, nhiều board, điện áp,
nhiệt độ, aging, entropy/uniqueness hoặc side-channel/fault-injection. Ghi rõ
điều kiện nguồn/nhiệt khi thực hiện các chiến dịch tiếp theo.

Physical route-lock full-SoC đã tái lập qua hai build và image thử đã PASS board
10.000/10.000. Kết quả đó kiểm soát thay đổi placement/routing giữa các build,
nhưng vẫn không chứng minh same-root, count-margin hoặc PVT. Xem
[`RO_PHYSICAL_REPRODUCIBILITY_2026-09-05.md`](RO_PHYSICAL_REPRODUCIBILITY_2026-09-05.md)
và [`PUF_QUALIFICATION_PLAN.md`](PUF_QUALIFICATION_PLAN.md).
