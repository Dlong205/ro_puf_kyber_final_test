# Báo cáo xác minh ML-KEM-512/FIPS 203 — 2026-09-04

## Kết luận hiện tại

Đường thuật toán nội bộ ML-KEM-512 đã vượt cổng functional bit-exact đầu tiên:

| Hạng mục | Oracle | Kết quả |
|---|---|---|
| KeyGen | NIST ACVP `ML-KEM-keyGen-FIPS203`, tgId 1 | PASS 25/25, `ek` 800 byte và `dk` 1.632 byte bit-exact |
| Encaps | NIST ACVP `ML-KEM-encapDecap-FIPS203`, tgId 1 | PASS 25/25, ciphertext 768 byte và K 32 byte bit-exact |
| Decaps hợp lệ | pq-crystals reference trên 25 cặp khóa NIST | PASS 25/25 K 32 byte, `equal=1` |
| Implicit rejection | pq-crystals + Python `hashlib.shake_256(z || c_sai)` | PASS 175/175 J 32 byte, `equal=0` |
| Latency valid/invalid | Isolated / loopback RTL | Bằng nhau: 12.287 / 17.338 cycle |

Nhãn đúng ở milestone này là **ML-KEM-512 internal algorithm functional
PASS**. Đây không phải chứng nhận CAVP/FIPS 140-3 và chưa phải lý do duy nhất để
freeze RTL hoặc phát hành production.

## Các lỗi RTL đã sửa

1. Ma trận Encaps được đổi sang thứ tự `AT00, AT01, AT10, AT11` đúng FIPS 203.
2. NTT Client/Server chờ đủ 64 noise word trước inverse NTT và chỉ pop đúng 64.
3. Bộ đếm squeeze không reset sớm khi Keccak init, tránh đưa hai word cuối rate
   cũ sang polynomial noise kế tiếp.
4. CCA Server dùng đúng lịch patt/eta3/matrix và noise thật thay vì zero preload.
5. OFIFO public key chỉ đọc trong state truyền; cờ last chặn look-ahead read của
   FIFO đồng bộ. Public `t` vì vậy quay về đúng word 0 trước CCA reload.
6. Server lưu nguyên 192 word ciphertext và tính đúng
   `J(z || c) = SHAKE256(z || c, 32)` khi implicit rejection.
7. `J(z || c)` chạy ở cả valid và invalid path; mux cuối chọn `K-bar` hoặc J,
   loại bỏ chênh lệch timing khoảng 310 cycle ở cấp giao thức.
8. Bộ đệm ciphertext 192 x 32 bit dùng `generic_bram` đọc đồng bộ và prefetch,
   tránh tiêu tốn thêm LUT trên XC7Z020 đồng thời giữ đường ánh xạ ASIC-generic.

## Nguồn vector và khả năng tái lập

Vector NIST được trích từ sample `internalProjection.json` của kho
`usnistgov/ACVP-Server`: [KeyGen](https://github.com/usnistgov/ACVP-Server/blob/master/gen-val/json-files/ML-KEM-keyGen-FIPS203/internalProjection.json)
và [Encaps/Decaps](https://github.com/usnistgov/ACVP-Server/blob/master/gen-val/json-files/ML-KEM-encapDecap-FIPS203/internalProjection.json).
File regression đã được check-in để test mặc định không phụ thuộc mạng.

25 vector Decaps độc lập dùng `d,z` và `ek/dk` của NIST KeyGen tgId 1,
randomness `m` tương ứng từ nhóm Encaps tgId 1, rồi sinh `c,K` bằng
pq-crystals reference commit
[`3edd5af5991927164edd4aacebfcbee00b8064e7`](https://github.com/pq-crystals/kyber/commit/3edd5af5991927164edd4aacebfcbee00b8064e7).
Cả `enc_derand` và `dec` phần mềm cho cùng K trước khi vector được đưa vào RTL.
Mỗi ciphertext được sửa tại 7 vị trí đại diện: đầu/cuối hai vùng nén `u`, biên
giữa hai đa thức của `u`, vị trí giữa và đầu/cuối vùng `v`. Mỗi J rejection
được kiểm tra chéo bằng pq-crystals và Python SHAKE256 trước khi chạy RTL.

Chạy toàn bộ cổng hiện có bằng:

```sh
make -C sim/mlkem clean
make -C sim/mlkem -j1 all
make -C sim/kyber clean
make -C sim/kyber -j1 kat
make -C sim/kyber -j1 kat-invalid
make -j1 fips202
make -j1 asic-elaboration
```

## Phạm vi chưa đóng

1. KeyGen/Encaps đã khóa toàn bộ 25 vector AFT ML-KEM-512 trong sample NIST;
   Decaps có 25 cặp oracle độc lập và rejection có 175 ca sửa ciphertext đa vị
   trí. Cần thêm malformed/API-length cases và corpus ngoài sample ACVP.
2. Core hiện là kiến trúc KEM tích hợp tự KeyGen và giữ secret nội bộ. Nó không
   nhận `ek/dk` tùy ý từ API, nên chưa có external
   `encapsulationKeyCheck`/`decapsulationKeyCheck` theo Sections 7.2/7.3.
3. Giao thức stream fixed-size sẽ stall nếu thiếu dữ liệu; chưa có status lỗi
   độ dài/type riêng ở biên API.
4. Chưa có formal proof, constant-time gate-level review, leakage/side-channel,
   fault-injection hoặc zeroization physical sign-off.
5. RTL ML-KEM mới đã PASS Vivado synthesis/place/route/timing/DRC ở 50 MHz và
   tạo bitstream candidate. JTAG/UART/stress candidate chưa chạy lại trên board;
   bitstream RC4 ở root vẫn thuộc tag `fpga-rc4-baseline`.

## Điều kiện freeze RTL mật mã

- Freeze candidate hiện chốt theo phạm vi KEM tích hợp nội bộ nhận seed; chưa
  tuyên bố API tổng quát nhận `ek/dk` ngoài.
- Vector/negative functional, full regression và ASIC portability/elaboration
  của candidate đã PASS.
- Vivado synth/implementation đã PASS; board regression của RTL mới phải PASS
  trước khi nâng candidate thành freeze cuối.
- Review độc lập serialization, compare/mux rejection, reset và zeroization.
- Tạo commit/tag freeze riêng; giữ `fpga-rc4-baseline` bất biến làm oracle.

Xem checklist và quy tắc change-control tại
[`CRYPTO_RTL_FREEZE_CANDIDATE_2026-09-04.md`](CRYPTO_RTL_FREEZE_CANDIDATE_2026-09-04.md).
