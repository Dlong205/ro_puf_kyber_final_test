# Crypto RTL freeze candidate — 2026-09-04

Trạng thái: **CANDIDATE v2, chưa phải freeze cuối**. Functional
ML-KEM-512/FIPS 203, portability ASIC, Vivado implementation và board regression
đã PASS. Cổng kỹ thuật còn lại trước freeze cuối là review độc lập.

## Phạm vi được khóa

Manifest `manifests/crypto_rtl_freeze_candidate.sha256` khóa đúng các file
Verilog/SystemVerilog trong:

- `rtl/common/`;
- `rtl/hash_core/`;
- `rtl/kyber/`;
- `rtl/top/kdf_keccak.sv`.

PUF, fuzzy extractor, RISC-V SoC và top-level board nằm ngoài manifest mật mã;
chúng vẫn được kiểm tra trong full regression và cổng ASIC portability.

## Phạm vi API đã chốt cho candidate

Candidate là accelerator **ML-KEM-512 tích hợp nội bộ**: KeyGen nhận seed,
Encaps/Decaps trao đổi ciphertext kích thước cố định và secret key được giữ bên
trong thiết kế. Nó không phải API thư viện ML-KEM tổng quát để nhập `ek/dk` tùy
ý. Vì vậy `encapsulationKeyCheck`, `decapsulationKeyCheck` và lỗi độ dài khóa
ngoài chưa thuộc claim của candidate.

Nếu yêu cầu sản phẩm đổi sang API nhập khóa ngoài, phải mở lại đặc tả interface,
thêm kiểm tra Sections 7.2/7.3 của FIPS 203, bổ sung malformed/length tests và
tạo manifest mới trước khi backend.

## Bằng chứng candidate

| Cổng | Kết quả |
|---|---|
| FIPS 202 | PASS 50/50, gồm 20 vector NIST CAVP |
| ML-KEM-512 KeyGen | PASS 25/25 NIST ACVP, `ek/dk` bit-exact |
| ML-KEM-512 Encaps | PASS 25/25 NIST ACVP, `c/K` bit-exact |
| ML-KEM-512 Decaps | PASS 25/25 oracle pq-crystals độc lập |
| Implicit rejection | PASS 175/175, J exact tại 7 vị trí sửa/ciphertext |
| Timing functional valid/invalid | PASS, cùng 12.287 cycle isolated và 17.338 cycle loopback |
| KDF SHAKE256 cố định | PASS bit-exact ở 148 cycle |
| Full system | PASS ở 956.564 cycle |
| Kyber raw single-attempt | PASS 1.024/1.024, mismatch/retry bằng 0 |
| ASIC portability | PASS, top elaborates với `KP_TARGET_ASIC` |
| Freeze manifest | PASS tập file và SHA-256 |
| Vivado synthesis/place/route | PASS, 49.909 LUT; timing/route/DRC đạt |
| Board RTL mới | PASS INFO/enroll/reconstruct; stress 10.000/10.000 |

Implementation tương ứng source commit
`8d2e8cda6d31e04e1557d64ca53d187cd85afc92`, Vivado 2020.1, part
`xc7z020clg400-2`, clock 50 MHz. Bitstream local 4.045.676 byte có SHA-256
`183e0af367376ebd7ca6bc2f3747314fd0602306a630af2a2e51858ef1f20e8e`.
Artifact đã được quảng bá thành `Kyber_System_Top.bit` cho version
`0.2.0-rc1` sau khi board PASS.
Chi tiết tại
[`HARDWARE_TEST_REPORT_MLKEM_CANDIDATE_2026-09-04.md`](HARDWARE_TEST_REPORT_MLKEM_CANDIDATE_2026-09-04.md).

Chạy lại toàn bộ cổng candidate bằng một lệnh. Makefile ép các pha chạy tuần tự
kể cả khi lệnh ngoài có tùy chọn `-j`:

```sh
make -j1 crypto-freeze-gate
```

Chỉ kiểm tra source có còn đúng manifest:

```sh
make crypto-freeze-check
```

## Điều kiện nâng thành freeze cuối

1. ~~Chạy Vivado implementation trên đúng `xc7z020clg400-2`.~~ **PASS**.
2. ~~Kiểm tra utilization riêng của RTL ML-KEM mới.~~ **PASS**, 49.909 LUT,
   30.649 register, 25 BRAM và 4 DSP sau route.
3. ~~Nạp bitstream mới, chạy INFO, enroll, reconstruct và stress 10.000 giao
   dịch single-attempt trên board.~~ **PASS**, 10.000/10.000, fail 0.
4. ~~Cập nhật report, SHA-256 và quảng bá artifact root.~~ **PASS**, version
   `0.2.0-rc1`.
5. Có review độc lập cho serialization, compare/mux rejection, reset và
   zeroization.
6. Chạy lại `make -j1 crypto-freeze-gate` trên working tree sạch, rồi mới tạo
   tag freeze cuối. Giữ tag `fpga-rc4-baseline` bất biến để so sánh.

## Change control

Không tự cập nhật hash để làm cổng PASS. Bất kỳ thay đổi hoặc file mới trong
phạm vi manifest phải:

1. giải thích lý do và review diff;
2. chạy lại FIPS 202, toàn bộ ML-KEM KAT/negative và full-system regression;
3. chạy lại portability cùng Vivado/board nếu thay đổi ảnh hưởng hardware;
4. tạo manifest và candidate/tag mới, không sửa lịch sử tag cũ.
