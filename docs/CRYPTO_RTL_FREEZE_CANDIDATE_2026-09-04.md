# Crypto RTL freeze candidate v3 — cập nhật 2026-09-06

Trạng thái: **CANDIDATE v3, chưa phải freeze cuối**. Candidate
v2/tag cũ vẫn là mốc FPGA đã kiểm chứng. V3 sửa kết nối output của bảy FIFO
wrapper để loại multiple-driver/undriven alias mà lint ASIC phát hiện, đồng thời
thêm policy khóa readback seed/shared-secret cho top ASIC. Full candidate gate
đã PASS tuần tự ngày 2026-09-06; còn phải đánh giá lại Vivado và có review độc
lập trước khi nâng trạng thái.

Thay đổi v3 không đổi depth, width, latency hay full/empty semantics: output của
`generic_fifo_sync` được nối vào wire nội bộ đã có rồi mới assign ra wrapper,
thay vì vừa nối trực tiếp vừa assign thêm từ wire chưa drive.

## Phạm vi được khóa

Manifest `manifests/crypto_rtl_freeze_candidate.sha256` khóa đúng các source
Verilog/SystemVerilog và header `.vh/.svh` trong:

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

## Bằng chứng candidate v3 đã chạy lại

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

## Bằng chứng FPGA kế thừa, chưa gán cho v3

Implementation/board đã PASS tương ứng artifact RC1/candidate v2 tại source
commit
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

1. ~~Chạy lại `make -j1 crypto-freeze-gate` sau sửa FIFO/policy secret.~~
   **PASS** ngày 2026-09-06.
2. Chạy Vivado implementation trên đúng `xc7z020clg400-2`, kiểm utilization,
   timing, route và DRC của candidate v3.
3. Nếu implementation v3 được dùng làm artifact FPGA, nạp đúng bitstream mới
   và chạy INFO/enroll/reconstruct cùng stress board; không tái sử dụng kết quả
   RC1 để gắn nhãn v3.
4. Có review độc lập cho serialization, compare/mux rejection, reset và
   zeroization.
5. Chạy lại `make -j1 crypto-freeze-gate` trên working tree sạch, rồi mới tạo
   tag freeze cuối. Giữ tag `fpga-rc4-baseline` bất biến để so sánh.

## Change control

Không tự cập nhật hash để làm cổng PASS. Bất kỳ thay đổi hoặc file mới trong
phạm vi manifest phải:

1. giải thích lý do và review diff;
2. chạy lại FIPS 202, toàn bộ ML-KEM KAT/negative và full-system regression;
3. chạy lại portability cùng Vivado/board nếu thay đổi ảnh hưởng hardware;
4. tạo manifest và candidate/tag mới, không sửa lịch sử tag cũ.
