# Crypto RTL freeze candidate v3 — cập nhật 2026-09-06

Trạng thái: **CANDIDATE v3, chưa phải freeze cuối**. Candidate
v2/tag cũ vẫn là mốc FPGA đã kiểm chứng. V3 sửa kết nối output của bảy FIFO
wrapper để loại multiple-driver/undriven alias mà lint ASIC phát hiện, đồng thời
thêm policy khóa readback seed/shared-secret cho top ASIC. Full candidate gate,
Vivado impact và đúng-image board regression đã PASS tuần tự ngày 2026-09-06.
Tuy nhiên AI pre-review phát hiện P0 secure-zeroize nên v3 **bị chặn**, không
được quảng bá hoặc nâng trạng thái; review độc lập của con người vẫn còn thiếu.

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
| Vivado synthesis/place/route/bitgen | PASS ở 50 MHz trên `xc7z020clg400-2` |
| Timing/route | WNS `+4,732 ns`, WHS `+0,034 ns`, 70.741/70.741 net |
| DRC/RO physical lock | 0 Error, 165 warning đã phân loại; 136 endpoint/128 route khớp RC1 |
| Board đúng image v3 | PASS INFO/enroll/reconstruct; stress 100/100, 1.000/1.000 và 10.000/10.000 |

## Vivado impact của candidate v3

Build cách ly tại source `1dcdad8ccb8c5acda5b11fcf754b2d686818d718`
dùng 49.886/53.200 LUT (`93,77%`), 30.649 register, 25 BRAM tile và 4 DSP.
Bitstream 4.045.676 byte có SHA-256
`b9f40dce606bcd429b5a97a123df1169e33c7ceca64ec901392651c60b4fa61e`.
Fingerprint RO SHA-256 `1fbad9f...` khớp byte-for-byte với RC1. Chi tiết tại
[`VIVADO_IMPACT_REPORT_CRYPTO_CANDIDATE_V3_2026-09-06.md`](VIVADO_IMPACT_REPORT_CRYPTO_CANDIDATE_V3_2026-09-06.md).

## Bằng chứng board

Implementation/board đã PASS tương ứng artifact RC1/candidate v2 tại source
commit
`8d2e8cda6d31e04e1557d64ca53d187cd85afc92`, Vivado 2020.1, part
`xc7z020clg400-2`, clock 50 MHz. Bitstream local 4.045.676 byte có SHA-256
`183e0af367376ebd7ca6bc2f3747314fd0602306a630af2a2e51858ef1f20e8e`.
Artifact đã được quảng bá thành `Kyber_System_Top.bit` cho version
`0.2.0-rc1` sau khi board PASS.
Chi tiết tại
[`HARDWARE_TEST_REPORT_MLKEM_CANDIDATE_2026-09-04.md`](HARDWARE_TEST_REPORT_MLKEM_CANDIDATE_2026-09-04.md).

Đúng image candidate v3 SHA-256 `b9f40dce...` đã PASS JTAG, INFO,
enroll/reconstruct và stress dài 10.000/10.000. Board sau đó được khôi phục về
RC1 và reconstruct smoke với helper mới PASS. Chi tiết tại
[`HARDWARE_TEST_REPORT_CRYPTO_CANDIDATE_V3_2026-09-06.md`](HARDWARE_TEST_REPORT_CRYPTO_CANDIDATE_V3_2026-09-06.md).

## Kết quả AI pre-review — blocker mở

Review tĩnh hỗ trợ bằng AI không thay thế reviewer độc lập. Review không thấy
lỗi functional mới trong serialization/rejection fixed-size `k=2`, nhưng tìm
thấy các vùng bí mật chưa được lệnh zeroize hiện tại xóa hoặc chứng minh xóa:

- `s-hat` và dữ liệu trung gian trong NTT/FIFO/ciphertext RAM; reset hiện chỉ
  xóa pointer/control, không ghi đè array;
- bốn state 1.600-bit của `sha3_shake_core`;
- `key_out`/register trung gian của fuzzy extractor và `seed_out` của KDF;
- test AXI hiện chỉ quan sát seed/status/K ở interface, chưa kiểm các vùng trên.

Các điểm P1 còn mở gồm reset giữa mọi phase, mutation ciphertext rộng hơn,
assert đủ compare-event và review leakage sau synthesis. Do đó board PASS không
thể được dùng để bỏ qua P0 zeroization.

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
2. ~~Chạy Vivado implementation trên đúng `xc7z020clg400-2`, kiểm utilization,
   timing, route và DRC của candidate v3.~~ **PASS** ngày 2026-09-06.
3. ~~Nạp đúng bitstream v3 và chạy INFO/enroll/reconstruct cùng stress board.~~
   **PASS** 100/100, 1.000/1.000 và 10.000/10.000 ngày 2026-09-06; đã restore RC1.
4. Sửa secure-zeroize sâu, bổ sung handshake/test RAM/sponge/FE/KDF và tạo
   candidate/manifest mới; không sửa lịch sử v3.
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
