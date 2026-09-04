# Việt Anh — KDF, Keccak và FIPS 202

## Phạm vi nghiên cứu/đối chiếu

- Keccak-f[1600], SHA3/SHAKE padding, absorb/squeeze và byte/bit ordering.
- SHAKE256 KDF từ khóa fuzzy extractor sang seed dùng bởi Kyber.
- Bộ known-answer test FIPS 202 đầy đủ và giao diện domain separation với KEM.

## Source và test liên quan

- `rtl/top/kdf_keccak.sv`
- `rtl/hash_core/`
- `rtl/common/keccak_pkg.sv`
- Các file Keccak/SHAKE trong `rtl/kyber/ref/`
- `sim/kdf_kat/`

## Trạng thái hiện tại

- SHA3-256, SHA3-512, SHAKE128 và SHAKE256 byte-oriented: PASS 50/50, gồm
  20 vector NIST CAVP, biên rate, multi-block, stall và reset.
- KDF SHAKE256 fixed-profile 24-byte → 64-byte: PASS bit-exact ở cycle 148.
- Full-system PUF → KDF → ML-KEM: PASS ở 956.564 cycle.
- KDF fixed-profile được giữ riêng với controller FIPS 202 tổng quát để giảm
  LUT; candidate đã fit XC7Z020 ở 49.909 LUT sau route.
- Chưa hỗ trợ SHA3-224/SHA3-384 hoặc message bit-oriented; PASS không đồng nghĩa
  triển khai đã được chứng nhận CAVP.

## Việc tiếp theo

1. Review độc lập mapping FIPS 203 của `H`, `G`, `J`, PRF và XOF sang bốn mode
   đã chốt.
2. Review endianness/serialization tại ranh giới Keccak ↔ ML-KEM.
3. Đề xuất thêm vector CAVP hoặc ACVP coverage còn thiếu nếu cần chứng nhận.
4. Review báo cáo do Long chạy; mọi thay đổi RTL và tích hợp do Long thực hiện.

## Definition of Done

- SHA3-256, SHAKE128 và SHAKE256 đều PASS vector FIPS 202, gồm multi-block.
- Padding, byte-order và domain separation có test riêng, không chỉ test KDF
  24-byte hiện tại.
- Kết quả tái lập được bằng một lệnh và thất bại trả exit code khác 0.
- Full-system và Kyber regression không bị phá sau khi tích hợp.

## Lệnh kiểm tra hiện có

```sh
make fips202
make kdf
make kyber
make system
```
