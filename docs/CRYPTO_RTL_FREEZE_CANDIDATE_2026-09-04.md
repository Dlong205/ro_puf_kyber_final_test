# Crypto RTL freeze candidate — 2026-09-04

Trạng thái: **CANDIDATE, chưa phải freeze cuối**. Functional ML-KEM-512/FIPS
203 và portability ASIC đã PASS; Vivado implementation và board regression của
RTL mới chưa chạy vì máy hiện không có executable Vivado.

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
| Full system | PASS ở 956.548 cycle |
| Kyber raw single-attempt | PASS 1.024/1.024, mismatch/retry bằng 0 |
| ASIC portability | PASS, top elaborates với `KP_TARGET_ASIC` |
| Freeze manifest | PASS tập file và SHA-256 |
| Vivado/board RTL mới | **PENDING** |

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

1. Chạy `make -j1 impl VIVADO=/duong-dan/toi/vivado` trên đúng
   `xc7z020clg400-2`; synthesis, place/route, timing và DRC phải PASS.
2. Kiểm tra utilization sau thay đổi BRAM; không dùng báo cáo RC4 để đại diện
   cho RTL ML-KEM mới.
3. Nạp bitstream mới, chạy INFO, enroll, reconstruct và stress 10.000 giao dịch
   single-attempt trên board.
4. Cập nhật report, SHA-256 bitstream và provenance theo đúng commit candidate.
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
