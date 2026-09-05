# RO-PUF + Fuzzy Extractor + Kyber/ML-KEM trên Zynq-7020

> **Internal FPGA release candidate `0.2.0-rc1` cho ML-KEM-512.** Repo dành cho
> nghiên cứu, đánh giá và cộng tác trong nhóm riêng tư. Phát hành công khai vẫn
> bị chặn bởi quyền phân phối Kyber RTL và top-level license. Kết quả hiện tại
> không phải chứng nhận CAVP/FIPS 140-3 và không phải module mật mã production.

Tag `fpga-rc4-baseline` giữ nguyên bitstream FPGA đã xác minh. Nhánh phát triển
đã hoàn tất cổng FIPS 202 byte-oriented và cổng functional bit-exact đầu tiên
cho KeyGen, Encaps, Decaps và implicit rejection của ML-KEM-512. RTL mới cũng
đã synthesis/place/route, tạo bitstream và PASS board regression 10.000 giao
dịch. Xem báo cáo
[`docs/FIPS203_VERIFICATION_2026-09-04.md`](docs/FIPS203_VERIFICATION_2026-09-04.md)
và
[`docs/HARDWARE_TEST_REPORT_MLKEM_CANDIDATE_2026-09-04.md`](docs/HARDWARE_TEST_REPORT_MLKEM_CANDIDATE_2026-09-04.md).
Qualification RO-PUF mới nhất nằm tại
[`docs/PUF_CHARACTERIZATION_2026-09-05.md`](docs/PUF_CHARACTERIZATION_2026-09-05.md).

Thiết kế pure RTL, chỉ dùng PL, thực hiện chuỗi:

```text
RO-PUF -> BCH fuzzy extractor -> SHAKE256 KDF -> ML-KEM-512 RTL tích hợp
       -> firmware PicoRV32 -> UART host
```

Không có Xilinx IP sinh tự động (`.xci`) và không dùng Zynq PS. Source RTL,
testbench, firmware, constraint, report Vivado, bitstream và host tool đều nằm
trong repo độc lập này.

## Trạng thái ML-KEM-512 RC1

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
| ML-KEM-512 Decaps | PASS 25/25 valid + 175/175 rejection; K/J khớp oracle độc lập |
| Timing valid/invalid | PASS, cùng 17.338 cycle trong loopback RTL |
| SHAKE256 KDF KAT | PASS bit-exact với Python `hashlib.shake_256`, cycle 148 |
| Kyber raw single-attempt gate | PASS 1.024/1.024, mismatch 0, retry 0 |
| Full-system simulation | PASS, 956.564 cycle trên nhánh ML-KEM |
| Implementation ML-KEM | PASS ở 50 MHz, 49.909 LUT; WNS `+2,226 ns`, WHS `+0,034 ns` |
| Route/DRC ML-KEM | 70.739/70.739 net route đủ; 0 Error/Critical Warning DRC |
| Tái lập vật lý RO full-SoC | PASS: 136 cell/128 net, 2 build sạch khớp fingerprint RC1 |
| Test board image route-lock | PASS INFO/enroll/reconstruct; stress 10.000/10.000; sau đó đã nạp lại RC1 |
| Test board ML-KEM RC1 | PASS INFO/enroll/reconstruct; stress 100/100, 1.000/1.000, 10.000/10.000 |
| Stress phần cứng RC4 | PASS 100/100, 1.000/1.000 và 10.000/10.000 |
| Hiệu năng board ML-KEM RC1 | `29,608 ms/giao dịch`, `33,775 giao dịch/s` ở run 10.000 |
| RO-PUF ngắn hạn PUF-only | 10.000 mẫu: HD max/p99 = 1, 0 mẫu > t=8, 1 bit dao động; chưa đạt gate entropy/PVT |
| Public release | **BỊ CHẶN**, xem `NOTICE.md` |

Implementation ML-KEM candidate dùng 49.909/53.200 Slice LUT (`93,81%`),
30.649 register, 25 BRAM tile và 4 DSP. KDF tích hợp dùng datapath SHAKE256 cố
định 24-byte → 64-byte để tránh bản sao state 1600-bit của controller tổng
quát; KDF và full-system đều đã regression lại. Thiết kế vẫn gần đầy chip và
đường tới hạn tại 50 MHz còn khoảng 2,226 ns margin, nên không thể chỉ đổi
constraint lên 100 MHz mà không tái kiến trúc/pipeline và chạy lại sign-off.

## Cấu trúc

- `rtl/`: RTL tổng hợp được cho SoC, PUF, BCH, KDF, Kyber và Keccak
- `sim/`: testbench RO-PUF, BCH, KDF, Kyber/AXI/codec và full-system UART
- `firmware/`: firmware PicoRV32 release và ảnh `firmware.hex`
- `constraints/`: pin/clock/placement cho board XC7Z020
- `scripts/`: tạo project, build, program, audit và đóng gói
- `host/`: host UART enroll/reconstruct/stress
- `reports/`: report synthesis và post-route của ML-KEM candidate hiện tại
- `docs/`: giao thức, nguồn gốc, bring-up, xác minh và mức sẵn sàng
- `phan_cong_nhom/`: tiến độ, phạm vi và tiêu chí hoàn thành của từng thành viên
- `Kyber_System_Top.bit`: bitstream ML-KEM-512 `0.2.0-rc1` đã test board
- `ARTIFACTS.sha256`: checksum bitstream, firmware, physical lock và fingerprint RO

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
make -j1 crypto-freeze-gate
```

`kyber-long` là cổng bắt buộc của internal release: 1.024 message seed khác
nhau, mỗi giao dịch đúng một attempt, không retry. Có thể chạy từng khối bằng
`make ro-puf`, `make fuzzy`, `make fips202`, `make kdf`, `make mlkem`,
`make kyber`, `make kyber-invalid`, `make axi`, `make kyber-codec` và
`make system`.

`crypto-freeze-gate` chạy tuần tự toàn bộ regression, cổng 1.024 giao dịch,
portability ASIC và đối chiếu SHA-256 của tập source mật mã. Manifest hiện là
freeze candidate; xem `docs/CRYPTO_RTL_FREEZE_CANDIDATE_2026-09-04.md`.

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

Script giới hạn một worker và một thread. Bitstream mới nằm ở
`build/vivado/kyber_ro_puf_zynq7020.runs/impl_1/Kyber_System_Top.bit`.
Project full-SoC nạp mặc định physical lock của RC1; sau route, build đối chiếu
`INIT`, LOC/BEL, pin-map, endpoint và route của toàn bộ miền RO. Sai khác làm
build thất bại. Bằng chứng và lệnh tái lập nằm tại
[`docs/RO_PHYSICAL_REPRODUCIBILITY_2026-09-05.md`](docs/RO_PHYSICAL_REPRODUCIBILITY_2026-09-05.md).
Artifact hiện có SHA-256
`183e0af367376ebd7ca6bc2f3747314fd0602306a630af2a2e51858ef1f20e8e`.
File ở root đã được đối chiếu byte-for-byte với bitstream vừa test board.

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
`docs/HARDWARE_BRINGUP.md` và
`docs/HARDWARE_TEST_REPORT_MLKEM_CANDIDATE_2026-09-04.md`.

Số thứ tự `ttyUSB` có thể thay đổi sau khi cắm lại cáp. Với adapter CH340 đang
dùng, đường dẫn ổn định là `/dev/serial/by-id/usb-1a86_USB_Serial-if00-port0`;
kiểm tra `ls -l /dev/serial/by-id/` trước khi chọn cổng.

Khi thử một candidate cách ly, truyền bitstream chính xác để tránh nạp nhầm:

```sh
make soc-repro-program SOC_REPRO_RUN=locked_b \
  VIVADO=/opt/Xilinx/Vivado/2020.1/bin/vivado
```

## Kiểm tra độ ổn định RO-PUF

Review ngày 2026-09-05 xác định cờ `success` của BCH chỉ kiểm tra codeword hợp
lệ; KEM loopback dùng khóa vừa phục hồi cho cả giao dịch. Vì vậy PASS 10.000
giao dịch chưa kiểm chứng khóa gốc có giữ nguyên so với enrollment. Bộ test
mới đối chiếu khóa trực tiếp trong mô phỏng và image đo raw giúp đo bit lỗi.

```sh
make -j1 fuzzy-characterization
make -j1 puf-characterization-sim
make -j1 -C sim/puf_characterization CLKS_PER_BIT=434
make -j1 puf-metrics-test
```

Image PUF-only đo response thô dùng project riêng và map 128 LUT từ RC1:

```sh
make -j1 puf-characterization-bitstream VIVADO=/opt/Xilinx/Vivado/2020.1/bin/vivado
make -j1 puf-characterization-program VIVADO=/opt/Xilinx/Vivado/2020.1/bin/vivado
make -j1 puf-raw-characterize PUF_SAMPLES=10000
make -j1 program VIVADO=/opt/Xilinx/Vivado/2020.1/bin/vivado
```

Image này xuất raw response phục vụ phòng lab. Kết thúc đo phải nạp lại image
release như lệnh cuối. Host chỉ lưu thống kê và không chủ động ghi raw response. Dataset
gắn với SHA-256 bitstream PUF-only; LOC/BEL đã khóa nhưng routing/tải SoC chưa
được bảo toàn, nên chưa suy kết quả đo sang RC1. Full-SoC hiện đã khóa chính
xác 136 endpoint/128 route của RC1 cho các build tương lai, nhưng điều đó không
làm image PUF-only tương đương. Count-margin, same-root trên
board, PVT và nhiều board vẫn cần thực hiện theo
[`docs/PUF_QUALIFICATION_PLAN.md`](docs/PUF_QUALIFICATION_PLAN.md).

## Phạm vi FIPS và giới hạn

SHA3-256, SHA3-512, SHAKE128 và SHAKE256 đã PASS 50/50 test byte-oriented, gồm
20 vector lấy từ response file NIST CAVP, các biên rate, absorb/squeeze nhiều
block, stall và reset. Đây là phạm vi primitive FIPS 202 mà ML-KEM cần; không
bao gồm SHA3-224/SHA3-384 hay message bit-oriented và không phải chứng nhận
CAVP/FIPS 140-3. Xem `docs/FIPS202_VERIFICATION_2026-09-03.md`.

ML-KEM-512 hiện đã đối chiếu bit-exact `ek`, `dk`, ciphertext và shared secret:
KeyGen/Encaps PASS toàn bộ 25 vector ML-KEM-512 AFT trong sample chính thức
NIST ACVP; Decaps PASS 25 cặp khóa/ciphertext sinh độc lập bằng pq-crystals
reference; 175 nhánh ciphertext sai tại 7 vị trí đại diện khớp
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
git commit -m "Cập nhật thay đổi đã kiểm tra"
git push origin HEAD
```

Chỉ push internal RC vào repo private cho đến khi hoàn thành các cổng license
trong `NOTICE.md`.
