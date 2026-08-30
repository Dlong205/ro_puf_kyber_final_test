# RO-PUF + Fuzzy Extractor + Kyber-512 cũ trên Zynq-7020

> **Ứng viên phát hành kỹ thuật nội bộ `0.1.0-rc2`.** Chỉ sử dụng repo này
> cho nghiên cứu, đánh giá và cộng tác trong nhóm riêng tư. Việc phát hành công
> khai đang bị chặn cho đến khi có quyền phân phối lại Kyber RTL và giấy phép
> cấp cao nhất tương thích. Đây không phải triển khai FIPS 203 ML-KEM.

Repo này là một bản triển khai độc lập, chỉ dùng PL, gồm chuỗi xử lý:

```text
RO-PUF -> BCH fuzzy extractor -> SHAKE256 KDF -> Kyber-512 cũ
       -> firmware PicoRV32 -> giao thức UART với máy chủ
```

Thiết kế không cần Xilinx IP sinh tự động (`.xci`) và không dùng Zynq PS. Source,
testbench, firmware release, report đã xác nhận và bitstream RC2 được lưu đầy đủ
để thành viên khác có thể đọc, mô phỏng, build lại và thử nghiệm mà không phụ
thuộc workspace phát triển cũ.

## Trạng thái RC2

| Hạng mục | Trạng thái |
|---|---|
| FPGA đích | `XC7Z020-2CLG400I`, part Vivado `xc7z020clg400-2` |
| Clock PL | 50 MHz tại chân N18 |
| UART | 115200 baud, RX W8, TX W9 |
| Regression RTL/test | PASS |
| KAT tham chiếu SHAKE256 | PASS một vector cố định, khớp từng bit |
| Timing sau route | PASS, WNS +4.108 ns, WHS +0.048 ns |
| DRC sau route | PASS, 0 lỗi |
| Stress trên board | PASS, 1.000/1.000 và 10.000/10.000 giao dịch logic |
| Phân phối công khai | **BỊ CHẶN**, xem `NOTICE.md` |
| Phát hành sản phẩm/bảo mật | **CHƯA SẴN SÀNG**, xem `docs/RELEASE_READINESS.md` |

Thiết kế gần đầy chip: 51.774/53.200 Slice LUT (97,32%), 23,5 BRAM tile và
4 DSP. Mọi thay đổi ảnh hưởng placement, fanout hoặc timing đều có rủi ro cao và
phải chạy implementation lại trước khi dùng bitstream mới. RC2 chỉ được xác nhận
ở 50 MHz; report hiện tại cho thấy không thể chỉ đổi constraint để chạy 100 MHz.

## Cấu trúc repo

- `rtl/`: toàn bộ Verilog/SystemVerilog tổng hợp được, chia theo khối chức năng
- `sim/`: test RO-PUF, fuzzy extractor, KDF, Kyber/AXI và system/UART
- `firmware/`: source PicoRV32 và ảnh release `firmware.hex`
- `constraints/`: chân board, clock và constraint implementation
- `scripts/`: tạo project Vivado, build, nạp board, kiểm tra và đóng gói
- `host/`: công cụ UART enroll/reconstruct/stress
- `reports/`: report synthesis/implementation RC2 đã xác nhận
- `docs/`: giao thức, nguồn gốc, bring-up board, bằng chứng test và đánh giá release
- `Kyber_System_Top.bit`: bitstream RC2 đã xác nhận để nạp volatile
- `ARTIFACTS.sha256`: checksum của các artifact nhị phân được commit

Sản phẩm build, object mô phỏng, helper data PUF cục bộ và cache Python được loại
bỏ bằng `.gitignore`.

## Chuẩn bị môi trường

Các công cụ khuyến nghị:

- GNU Make, Bash, Python 3 và trình biên dịch C++
- Verilator để chạy mô phỏng
- `riscv64-unknown-elf-gcc` và `riscv64-unknown-elf-objcopy` để build firmware
- Xilinx Vivado 2020.1 để synthesis, implementation hoặc nạp FPGA

Sau khi clone, kiểm tra snapshot và checksum:

```sh
make check
sha256sum -c ARTIFACTS.sha256
```

Chạy toàn bộ regression nhẹ, tuần tự:

```sh
make -j1 regression
```

Hoặc chạy từng giai đoạn:

```sh
make ro-puf
make fuzzy
make kdf
make kyber
make axi
make system
```

`make system` sẽ build firmware release khi cần. Firmware mặc định chỉ báo kết
quả khớp khóa server/client và không truyền shared secret qua UART. Có thể tạo
bản chẩn đoán bằng `make -C firmware clean all RELEASE_BUILD=0`, nhưng tuyệt đối
không commit hoặc phân phối ảnh chẩn đoán đó như artifact release.

Kết quả regression gần nhất, môi trường chạy, checksum và giới hạn phạm vi FIPS
được ghi tại `docs/VERIFICATION_REPORT_2026-08-30.md`.

## Build lại bằng Vivado

Tạo project mới từ source trong repo, không nhập XPR cũ:

```sh
make vivado-project
make synth
make impl
```

Script cố ý chỉ dùng một worker Vivado để hạn chế RAM. Nếu Vivado không nằm
trong `PATH`, truyền đường dẫn trực tiếp, ví dụ:

```sh
make impl VIVADO=/opt/Xilinx/Vivado/2020.1/bin/vivado
```

Bitstream build lại nằm tại:

```text
build/vivado/kyber_ro_puf_zynq7020.runs/impl_1/Kyber_System_Top.bit
```

Phải so sánh report và checksum với bằng chứng RC2 trước khi thay bitstream ở
thư mục gốc. `make release-check` ưu tiên kiểm tra bitstream vừa build nếu có;
nếu không, script kiểm tra `Kyber_System_Top.bit` đã commit.

## Nạp và thử board

Kết nối đúng một thiết bị XC7Z020 qua JTAG rồi chạy:

```sh
make program
```

Script chỉ nạp cấu hình FPGA volatile, không ghi QSPI flash. Nó ưu tiên bitstream
vừa implementation và dùng bitstream RC2 ở thư mục gốc nếu chưa build lại.

Kiểm tra giao thức UART và chạy stress ngắn:

```sh
python3 host/uart_host.py --port /dev/ttyUSB0 info
python3 host/uart_host.py --port /dev/ttyUSB0 --helper helper.bin enroll
python3 host/uart_host.py --port /dev/ttyUSB0 --helper helper.bin reconstruct
python3 host/uart_host.py --port /dev/ttyUSB0 --helper helper.bin stress --count 100
```

`helper.bin` là dữ liệu công khai nhưng gắn với từng board/lần enroll, phải giữ
cục bộ và đã được Git bỏ qua. Xem `docs/HARDWARE_BRINGUP.md` để biết cách đấu dây,
response mong đợi và quy trình stress đầy đủ.

## Giới hạn quan trọng

Kyber core cũ được nhập có raw key mismatch phụ thuộc vector và đôi khi bị treo.
Giao thức 1.1 zeroize rồi thử lại với input `m` mới, tối đa 16 lần. Kết quả
10.000/10.000 chỉ xác nhận wrapper availability ở mức giao dịch logic, không
chứng minh raw core luôn đúng.

RO-PUF cũng chưa được qualification đầy đủ: còn thiếu test nhiều board, nhiều
lần ngắt/cấp nguồn vật lý, góc điện áp/nhiệt độ, đánh giá entropy và phân tích
side-channel/fault. Xem `docs/RELEASE_READINESS.md`, `SECURITY.md`, `NOTICE.md`
và `docs/PROVENANCE.md` trước khi đổi nhãn hoặc phạm vi phát hành.

## Quy trình Git cho nhóm

Repo này đã tồn tại thì **không chạy `git init` lại**. Sau khi thay đổi và kiểm
tra, dùng:

```sh
git status
git diff --check
git add .
git commit -m "Cập nhật RO-PUF Kyber Zynq-7020 RC2"
git push origin main
```

Trước mỗi release phần cứng, chạy regression, build lại bằng Vivado, xem
`git diff`, cập nhật report/checksum/bằng chứng test rồi chạy:

```sh
./scripts/release_check.sh --internal
```

Chỉ đẩy RC2 lên repo **private/internal** cho đến khi các cổng license trong
`NOTICE.md` được giải quyết.
