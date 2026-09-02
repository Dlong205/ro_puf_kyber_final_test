# Việt Anh — KDF, Keccak và FIPS 202

## Phạm vi phụ trách

- Keccak-f[1600], SHA3/SHAKE padding, absorb/squeeze và byte/bit ordering.
- SHAKE256 KDF từ khóa fuzzy extractor sang seed dùng bởi Kyber.
- Bộ known-answer test FIPS 202 đầy đủ và giao diện domain separation với KEM.

## Source và test liên quan

- `rtl/top/kdf_keccak.sv`
- `rtl/hash_core/`
- `rtl/common/keccak_pkg.sv`
- Các file Keccak/SHAKE trong `rtl/kyber/ref/`
- `sim/kdf_kat/`

## Trạng thái RC4

- KDF SHAKE256 với input 24 byte: PASS bit-exact so với Python
  `hashlib.shake_256`.
- Full-system PUF → KDF → Kyber: PASS.
- Chưa có ma trận KAT đầy đủ cho SHA3-256, SHAKE128, SHAKE256, input rỗng,
  boundary rate và multi-block.
- PASS hiện tại không đồng nghĩa toàn bộ Keccak RTL đã được chứng nhận FIPS 202.

## Việc tiếp theo

1. Chốt API theo mode SHA3-256/SHAKE128/SHAKE256 và tài liệu hóa rate,
   suffix/domain bits, padding `pad10*1`, endianness.
2. Thêm vector NIST cho input rỗng, ngắn, đúng/sát biên rate, multi-block và
   output squeeze qua nhiều block.
3. So sánh bit-exact với ít nhất một implementation tham chiếu độc lập.
4. Kiểm tra reset giữa absorb/squeeze, back-to-back request, valid/ready stall
   và độ dài không hợp lệ.
5. Xác định hàm hash/XOF/KDF nào FIPS 203 yêu cầu và thống nhất interface với
   nhóm Kyber trước khi sửa datapath.
6. Thêm cổng `make fips202` chạy toàn bộ KAT và đưa vào release-check/CI.

## Definition of Done

- SHA3-256, SHAKE128 và SHAKE256 đều PASS vector FIPS 202, gồm multi-block.
- Padding, byte-order và domain separation có test riêng, không chỉ test KDF
  24-byte hiện tại.
- Kết quả tái lập được bằng một lệnh và thất bại trả exit code khác 0.
- Full-system và Kyber regression không bị phá sau khi tích hợp.

## Lệnh kiểm tra hiện có

```sh
make kdf
make kyber
make system
```
