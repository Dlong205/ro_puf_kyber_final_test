# Kiểm tra ML-KEM-512 theo FIPS 203

Thư mục này chứa các KAT cho nhánh chuyển đổi từ Kyber RTL cũ sang
ML-KEM-512.

## Phạm vi đã có

`make keygen` chạy `Kyber_Server` với 25 cặp `d,z` rồi so sánh toàn bộ
800 byte `ek` và 1.632 byte `dk` của từng ca với NIST ACVP
`ML-KEM-keyGen-FIPS203`, nhóm `tgId=1`. Phần `dk_PKE` được dựng
lại từ RAM secret NTT theo đúng `ByteEncode_12`; phần đuôi là
`ek || H(ek) || z`.

Ví dụ vector đầu tiên:

- `d = 47B893474672BA92E4B12EE44FB32953AF8E8503B5FB471D1614FB8A021A660A`
- `z = 1F8CB39E9E30BC458A0DC5408884B1187FB217018DF760FA57317703B844A0A9`

`make encap` lần lượt nạp 25 cặp `m,ek` NIST vào Client và so sánh chính xác
768 byte ciphertext cùng 32 byte K với NIST ACVP
`ML-KEM-encapDecap-FIPS203`, toàn bộ `tgId=1`.

`make decap` dùng cặp khóa NIST ở trên, nhưng ciphertext/K được sinh độc lập
bằng `pq-crystals/kyber` reference commit
`3edd5af5991927164edd4aacebfcbee00b8064e7`. Test không nối ciphertext từ
Client sang Server nên bắt được lỗi riêng ở Decaps.

Vector kỳ vọng nằm trong các file `mlkem512_*` của thư mục này. Chạy tuần tự
để hạn chế tải máy:

```bash
cd sim/mlkem
make clean
make -j1 all
make -C ../kyber -j1 kat-invalid
```

## Giới hạn hiện tại

Các KAT hiện xác nhận bit-exact KeyGen `ek/dk`, Encaps `c/K`, Decaps hợp lệ và
implicit rejection `J(z || c)`. Valid/invalid decapsulation có cùng latency
17.338 cycle trong loopback hiện tại.

Đây mới là cổng functional cho thuật toán nội bộ ML-KEM-512, chưa phải chứng
nhận FIPS/CAVP. KeyGen và Encaps đã bao phủ 25/25 vector AFT ML-KEM-512 trong
sample NIST; Decaps mới dùng một vector độc lập và chưa có corpus
Wycheproof/negative mở rộng. Kiến trúc tích hợp tự sinh và giữ khóa bên trong nên chưa
có API nạp khóa ngoài và chưa triển khai `encapsulationKeyCheck` /
`decapsulationKeyCheck`. Quyết định phạm vi API này phải được chốt trước khi
freeze RTL mật mã.

`mlkem_ref_trace.c` và `mlkem_encap_ref_trace.c` là tiện ích chẩn đoán tùy
chọn, dùng source phần mềm tham chiếu ngoài repo. Chúng không tham gia KAT mặc
định và không phải dependency khi chạy regression.
