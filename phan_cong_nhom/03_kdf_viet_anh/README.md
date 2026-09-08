# Việt Anh — KDF, Keccak và FIPS 202

Cập nhật **2026-09-08**. Pha implementation FIPS 202 phục vụ ML-KEM đã hoàn
thành ở mức functional; phần của Việt Anh hiện chuyển sang review độc lập.
Long thực hiện mọi thay đổi RTL và chạy lại gate khi review phát hiện vấn đề.

## Phạm vi nghiên cứu/đối chiếu

- Keccak-f[1600], SHA3/SHAKE padding, absorb/squeeze và byte/bit ordering.
- SHAKE256 KDF từ khóa fuzzy extractor sang seed dùng bởi Kyber.
- Bộ known-answer test FIPS 202 đầy đủ và giao diện domain separation với KEM.

## Source và test liên quan

- `rtl/top/kdf_keccak.sv`
- `rtl/hash_core/`
- `rtl/common/keccak_pkg.sv`
- Các file Keccak/SHAKE trong `rtl/kyber/ref/`
- `sim/fips202/`
- `sim/kdf_kat/`
- `sim/mlkem/`
- `docs/FIPS202_VERIFICATION_2026-09-03.md`
- `docs/FIPS203_VERIFICATION_2026-09-04.md`

## Đã hoàn thành

- SHA3-256, SHA3-512, SHAKE128 và SHAKE256 byte-oriented: PASS 50/50, gồm
  20 vector NIST CAVP, biên rate, multi-block, stall và reset.
- KDF SHAKE256 fixed-profile 24-byte → 64-byte: PASS bit-exact ở cycle 148.
- Candidate v4 KDF/Keccak zeroize PASS: input shift, seed output, controller và
  sponge state được xóa; KDF KAT + zeroize test PASS.
- Full-system PUF → KDF → ML-KEM v4: PASS ở 958.516 cycle, protocol 1.3.
- Đúng source/image v4 PASS Vivado 50 MHz và board stress 10.000/10.000; đây
  là regression tích hợp, không thay thế review FIPS 202 độc lập.
- KDF fixed-profile được giữ riêng với controller FIPS 202 tổng quát để giảm
  LUT; artifact RC1/candidate v2 đã fit XC7Z020 ở 49.909 LUT sau route.
- Chưa hỗ trợ SHA3-224/SHA3-384 hoặc message bit-oriented; PASS không đồng nghĩa
  triển khai đã được chứng nhận CAVP.

Kết luận đúng là **FIPS 202 functional scope cần cho ML-KEM đã DONE**. Không mở
rộng primitive chỉ để tăng số lượng thuật toán nếu đặc tả hệ thống không cần.

## Còn mở

1. Review độc lập mapping `H=SHA3-256`, `G=SHA3-512`, `J/PRF=SHAKE256` và
   `XOF=SHAKE128` theo FIPS 203.
2. Review endianness/serialization tại ranh giới Keccak ↔ ML-KEM.
3. Đề xuất thêm vector CAVP hoặc ACVP coverage còn thiếu nếu cần chứng nhận.
4. Review báo cáo do Long chạy; mọi thay đổi RTL và tích hợp do Long thực hiện.
5. Review ranh giới accelerator-zeroize; không suy claim sang CPU/bus/scan.

## Definition of Done còn lại

- Có biên bản review cả SHA3-256, SHA3-512, SHAKE128 và SHAKE256.
- Padding, byte-order, domain separation và mapping H/G/J/PRF/XOF được đối
  chiếu độc lập với test hiện có.
- Mọi claim ghi rõ đây là regression functional, không phải chứng nhận CAVP.
- Nếu review yêu cầu sửa RTL: FIPS 202, ML-KEM và full-system phải PASS lại.

## Lệnh kiểm tra hiện có

```sh
make fips202
make kdf
make mlkem
make kyber
make system
make -j1 crypto-freeze-gate
```
