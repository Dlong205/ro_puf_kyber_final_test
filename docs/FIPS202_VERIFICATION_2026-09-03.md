# Báo cáo xác minh FIPS 202 cho nhánh ML-KEM — 2026-09-03

## Kết luận

Bốn primitive mà ML-KEM-512 cần đã PASS kiểm tra tương thích chức năng theo
FIPS 202 trên giao tiếp byte:

| Primitive | Rate | Suffix | Kết quả |
|---|---:|---:|---|
| SHA3-256 | 136 byte | `0x06` | PASS |
| SHA3-512 | 72 byte | `0x06` | PASS |
| SHAKE128 | 168 byte | `0x1f` | PASS |
| SHAKE256 | 136 byte | `0x1f` | PASS |

Tổng cộng **50/50 test PASS**. Kết quả này là bằng chứng regression/KAT nội bộ,
không phải chứng nhận CAVP, FIPS 140-3 hay chứng nhận sản phẩm.

## Thay đổi RTL

`rtl/hash_core/fips202_sponge.sv` bổ sung controller sponge tổng quát dùng lại
datapath `ALGORITHM` Keccak-f[1600] 24 round hiện có. Giao tiếp mới:

- nhận message theo byte với `valid/ready` và độ dài byte tường minh;
- tự sinh domain suffix cùng padding `pad10*1`;
- tự permutation khi absorb đầy rate, kể cả trường hợp message kết thúc đúng
  biên block cần thêm block padding;
- tự permutation khi SHAKE squeeze vượt một rate block;
- hỗ trợ backpressure đầu vào/đầu ra, input rỗng và SHAKE output dài 0;
- reject độ dài output sai của SHA3-256/SHA3-512;
- đưa giao diện về idle an toàn khi reset giữa absorb hoặc squeeze.

`rtl/top/kdf_keccak.sv` dùng controller 32-bit chuyên dụng cho đúng profile cố
định `SHAKE256(key 24 byte, output 64 byte)` và giữ quy ước digest byte 0 ở
`seed_out[7:0]`. Controller tổng quát vẫn là oracle RTL cho FIPS 202; KDF tích
hợp bỏ một bản sao state 1600-bit để fit XC7Z020. KDF chuyên dụng được kiểm tra
bit-exact độc lập với Python sau thay đổi.

Mode chuẩn dùng thống nhất trong dự án:

```text
00 = SHA3-512
01 = SHAKE256
10 = SHAKE128
11 = SHA3-256
```

## Ma trận kiểm thử

### Vector sinh độc lập bằng Python hashlib: 26 test

Mỗi primitive có message rỗng, `abc`, `rate-1`, `rate`, `rate+1` và
`2*rate+17`. SHAKE còn kiểm tra output 0 byte, đúng/sát biên rate và output qua
nhiều block. Expected được tạo bởi `sim/fips202/generate_vectors.py` rồi lưu
trong `fips202_vectors.txt` để regression không phụ thuộc mạng.

### Vector NIST CAVP byte-oriented: 20 test

Tập con kiểm tra message rỗng, 1 byte, sát/đúng/qua biên rate và variable-output
được trích từ các response file CAVS 19.0 của NIST:

- SHA-3 byte vectors: `sha-3bytetestvectors.zip`, SHA-256
  `cd07701af2e47f5cc889d642528b4bf11f8b6eb55797c7307a96828ed8d8fc8c`;
- SHAKE byte vectors: `shakebytetestvectors.zip`, SHA-256
  `debfebc3157b3ceea002b84ca38476420389a3bf7e97dc5f53ea4689a16de4c7`.

Nguồn URL và checksum được ghi ngay trong `nist_cavp_vectors.txt`. Script
`import_nist_cavp.py` tái tạo tập con và kiểm tra lại từng response bằng
`hashlib` trước khi ghi file.

### Corner case giao thức: 4 test

- reject SHA3-256 output 31 byte;
- reset giữa absorb rồi chạy lại thành công;
- reset giữa squeeze rồi chạy lại thành công;
- SHAKE256 nối tiếp SHA3-256 không reset.

Driver cố ý chèn stall theo chu kỳ ở cả input và output để kiểm tra handshake.

## Regression tích hợp

Các lệnh đã chạy tuần tự trên Verilator 5.050:

```sh
make -j1 fips202
make -j1 kdf
make -j1 regression
make -j1 asic-elaboration
```

Kết quả:

- FIPS 202 byte-oriented: PASS 50/50;
- KDF SHAKE256: PASS bit-exact, hoàn tất tại cycle 148;
- ML-KEM-512 loopback/AXI/strict/codec: PASS;
- full UART → PUF → fuzzy extractor → KDF → ML-KEM: PASS, 956.564 cycle;
- full top với `KP_TARGET_ASIC`: elaborate PASS, source list ASIC không chứa
  `LUT6_L`, `CARRY4` hay primitive DSP48 trực tiếp.

## Phạm vi và giới hạn

1. API hiện nhận message byte-aligned. Bộ bit-oriented FIPS 202 không nằm trong
   phạm vi vì ML-KEM làm việc trên chuỗi byte.
2. SHA3-224 và SHA3-384 chưa được triển khai vì không phải primitive ML-KEM-512
   cần dùng.
3. Chỉ một tập con CAVP được check-in; đây không phải quy trình cấp chứng nhận.
4. PASS FIPS 202 không tự chứng nhận toàn bộ ML-KEM; FIPS 203 được xác minh bằng
   bộ cổng riêng trong `FIPS203_VERIFICATION_2026-09-04.md`.
5. Nhánh ML-KEM đã PASS Vivado implementation và board regression 10.000/10.000;
   bitstream RC4 vẫn được giữ bất biến tại tag `fpga-rc4-baseline`.

## Cổng chuyển sang FIPS 203

Phase FIPS 202 byte-oriented phục vụ ML-KEM được coi là hoàn thành về mặt
functional regression. Cổng FIPS 203 tiếp theo cũng đã đạt mức internal
algorithm functional; việc còn lại trước freeze cuối là board regression và
review độc lập, không phải sửa thêm primitive FIPS 202 ở thời điểm này.
