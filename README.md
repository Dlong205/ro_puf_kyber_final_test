# RO-PUF + Fuzzy Extractor + Kyber/ML-KEM trên Zynq-7020

> **Baseline FPGA `0.1.0-rc4` và nhánh phát triển ML-KEM.** Repo dành cho
> nghiên cứu, đánh giá và cộng tác trong nhóm riêng tư. Phát hành công khai vẫn
> bị chặn bởi quyền phân phối Kyber RTL và top-level license. Kết quả hiện tại
> không phải chứng nhận CAVP/FIPS 140-3 và không phải module mật mã production.

Tag `fpga-rc4-baseline` giữ nguyên bitstream FPGA đã xác minh. Nhánh phát triển
đã hoàn tất cổng FIPS 202 byte-oriented và cổng functional bit-exact đầu tiên
cho KeyGen, Encaps, Decaps và implicit rejection của ML-KEM-512. Xem báo cáo
[`docs/FIPS203_VERIFICATION_2026-09-04.md`](docs/FIPS203_VERIFICATION_2026-09-04.md).

Thiết kế pure RTL, chỉ dùng PL, thực hiện chuỗi:

```text
RO-PUF -> BCH fuzzy extractor -> SHAKE256 KDF -> ML-KEM-512 RTL tích hợp
       -> firmware PicoRV32 -> UART host
```

Không có Xilinx IP sinh tự động (`.xci`) và không dùng Zynq PS. Source RTL,
testbench, firmware, constraint, report Vivado, bitstream và host tool đều nằm
trong repo độc lập này.

## Trạng thái baseline RC4 và nhánh phát triển

| Hạng mục | Kết quả |
|---|---|
| FPGA | `XC7Z020-2CLG400I`, Vivado part `xc7z020clg400-2` |
| Clock PL | 50 MHz tại N18 |
| UART | 115200 8N1, RX W8, TX W9 |
| Regression RTL/full-system | PASS |
| Cổng ASIC portability | PASS, không đưa LUT6/CARRY4/DSP primitive vào source list ASIC |
| FIPS 202 cho ML-KEM | PASS 50/50: SHA3-256/512, SHAKE128/256, gồm 20 vector NIST CAVP |
| ML-KEM-512 KeyGen | PASS 25/25 NIST ACVP: `ek` 800 byte, `dk` 1.632 byte bit-exact |
| ML-KEM-512 Encaps | PASS 25/25 NIST ACVP: ciphertext 768 byte, K 32 byte bit-exact |
| ML-KEM-512 Decaps | PASS 25/25 valid + 25/25 rejection; K/J khớp oracle độc lập |
| Timing valid/invalid | PASS, cùng 17.338 cycle trong loopback RTL |
| SHAKE256 KDF KAT | PASS, KDF mới khớp từng bit với Python `hashlib.shake_256` |
| Kyber raw single-attempt gate | PASS 1.024/1.024, mismatch 0, retry 0 |
| Full-system simulation | PASS, 956.548 cycle trên nhánh ML-KEM |
| Timing sau route | PASS ở 50 MHz, WNS `+3,663 ns`, WHS `+0,056 ns`, TNS/THS `0` |
| Route/DRC | 0 net chưa route, 0 lỗi DRC |
| Stress phần cứng | PASS 100/100, 1.000/1.000 và 10.000/10.000 |
| Hiệu năng board | `29,119 ms/giao dịch`, `34,342 giao dịch/s` ở run 10.000 |
| Public release | **BỊ CHẶN**, xem `NOTICE.md` |

Implementation dùng 51.682/53.200 Slice LUT (`97,15%`), 30.554 register,
23,5 BRAM tile và 4 DSP. Thiết kế gần đầy chip; mọi thay đổi RTL phải chạy lại
implementation. RC4 chỉ được xác nhận ở 50 MHz. Margin hiện tại không đủ để chỉ
đổi constraint lên 100 MHz.

## Cấu trúc

- `rtl/`: RTL tổng hợp được cho SoC, PUF, BCH, KDF, Kyber và Keccak
- `sim/`: testbench RO-PUF, BCH, KDF, Kyber/AXI/codec và full-system UART
- `firmware/`: firmware PicoRV32 release và ảnh `firmware.hex`
- `constraints/`: pin/clock/placement cho board XC7Z020
- `scripts/`: tạo project, build, program, audit và đóng gói
- `host/`: host UART enroll/reconstruct/stress
- `reports/`: report synthesis và post-route RC4
- `docs/`: giao thức, nguồn gốc, bring-up, xác minh và mức sẵn sàng
- `phan_cong_nhom/`: tiến độ, phạm vi và tiêu chí hoàn thành của từng thành viên
- `Kyber_System_Top.bit`: bitstream RC4 nạp volatile
- `ARTIFACTS.sha256`: checksum bitstream và firmware

Build/cache, waveform, helper data PUF gắn với board và dữ liệu local khác được
loại bằng `.gitignore`.

## Phân công nhóm

| Thành viên | Phụ trách |
|---|---|
| Đạt và Tùng | Nghiên cứu/đối chiếu Kyber KEM và FIPS 203 |
| Minh | Nghiên cứu lưu khóa và vòng đời khóa |
| Việt Anh | Nghiên cứu/đối chiếu KDF, Keccak và FIPS 202 |
| Long | Chủ trì implementation, tích hợp, kiểm thử, RO-PUF và backend FPGA/ASIC |

Chi tiết, đường dẫn source, bài test và Definition of Done nằm tại
[`phan_cong_nhom/`](phan_cong_nhom/README.md).

## Mô phỏng và kiểm tra

Yêu cầu khuyến nghị: GNU Make, Bash, Python 3, Verilator, C++ compiler và
RISC-V GCC toolchain. Chạy tuần tự để tránh dùng quá nhiều RAM:

```sh
make check
sha256sum -c ARTIFACTS.sha256
make -j1 regression
make -j1 kyber-long
```

`kyber-long` là cổng bắt buộc của internal release: 1.024 message seed khác
nhau, mỗi giao dịch đúng một attempt, không retry. Có thể chạy từng khối bằng
`make ro-puf`, `make fuzzy`, `make fips202`, `make kdf`, `make mlkem`,
`make kyber`, `make kyber-invalid`, `make axi`, `make kyber-codec` và
`make system`.

Kiểm tra khả năng elaborate RTL ở chế độ ASIC-generic (không đưa `LUT6_L`,
`CARRY4` hay primitive DSP48 vào source list ASIC):

```sh
make -j1 asic-portability
```

RO-PUF đã có backend riêng cho mô phỏng, Xilinx và macro ASIC; BCH có đường so
sánh portable; multiplier NTT dùng phép nhân RTL trung lập. Đây mới là cổng
portability, chưa phải ASIC sign-off. Xem `docs/ASIC_PORTABILITY.md` để biết
contract macro RO và các bước PDK/memory/SDC/DFT/backend còn lại.

Firmware mặc định dùng `RELEASE_BUILD=1`: không truyền shared secret qua UART.
Bản `RELEASE_BUILD=0` chỉ dùng chẩn đoán và không được commit/phân phối như
artifact release.

## Build Vivado

Vivado 2020.1:

```sh
make vivado-project
make -j1 impl
```

Nếu Vivado không nằm trong `PATH`:

```sh
make -j1 impl VIVADO=/opt/Xilinx/Vivado/2020.1/bin/vivado
```

Script giới hạn một worker và tối đa hai thread. Bitstream mới nằm ở
`build/vivado/kyber_ro_puf_zynq7020.runs/impl_1/Kyber_System_Top.bit`.
Không thay artifact gốc nếu timing/DRC chưa PASS.

## Nạp và kiểm tra board

Kết nối đúng một XC7Z020 qua JTAG:

```sh
make program VIVADO=/opt/Xilinx/Vivado/2020.1/bin/vivado
python3 host/uart_host.py --port /dev/ttyUSB1 info
python3 host/uart_host.py --port /dev/ttyUSB1 --helper ../helper-private.bin enroll
python3 host/uart_host.py --port /dev/ttyUSB1 --helper ../helper-private.bin reconstruct
python3 host/uart_host.py --port /dev/ttyUSB1 --helper ../helper-private.bin stress --count 10000
```

`make program` chỉ nạp PL volatile, không ghi QSPI. Helper data là dữ liệu công
khai nhưng gắn với từng board/lần enroll; giữ nó ngoài repo. Xem
`docs/HARDWARE_BRINGUP.md` và `docs/HARDWARE_TEST_REPORT_RC4_2026-09-03.md`.

## Phạm vi FIPS và giới hạn

SHA3-256, SHA3-512, SHAKE128 và SHAKE256 đã PASS 50/50 test byte-oriented, gồm
20 vector lấy từ response file NIST CAVP, các biên rate, absorb/squeeze nhiều
block, stall và reset. Đây là phạm vi primitive FIPS 202 mà ML-KEM cần; không
bao gồm SHA3-224/SHA3-384 hay message bit-oriented và không phải chứng nhận
CAVP/FIPS 140-3. Xem `docs/FIPS202_VERIFICATION_2026-09-03.md`.

ML-KEM-512 hiện đã đối chiếu bit-exact `ek`, `dk`, ciphertext và shared secret:
KeyGen/Encaps PASS toàn bộ 25 vector ML-KEM-512 AFT trong sample chính thức
NIST ACVP; Decaps PASS 25 cặp khóa/ciphertext sinh độc lập bằng pq-crystals
reference; 25 nhánh ciphertext sai khớp
`SHAKE256(z || c, 32)`. Đây là cổng functional cho thuật toán nội bộ, chưa phải
chứng nhận FIPS và chưa bao phủ toàn bộ vector/API kiểm tra khóa ngoài.

Các lỗi underfill/starvation Kyber được tìm thấy trong stress đã được sửa bằng
handshake FIFO và điều kiện kết thúc dựa trên số coefficient thực nhận. Gate
1.024 vector và board 10.000 vòng hiện không còn mismatch/timeout, nhưng không
thay thế formal verification, mở rộng ACVP KAT hoặc review mật mã độc lập.

RO-PUF còn thiếu qualification nhiều board, cold/warm power-cycle, điện áp,
nhiệt độ, aging, entropy/uniqueness và side-channel/fault-injection. Xem
`SECURITY.md`, `docs/RELEASE_READINESS.md`, `NOTICE.md` và
`docs/PROVENANCE.md`.

## Git nội bộ

Không chạy `git init` lại. Trước khi commit:

```sh
./scripts/release_check.sh --internal
sha256sum -c ARTIFACTS.sha256
git diff --check
git status
git add .
git commit -m "Xác nhận FPGA RC4 và khả năng chuyển ASIC"
git push origin main
```

Chỉ push RC4 vào repo private/internal cho đến khi hoàn thành các cổng license
trong `NOTICE.md`.
