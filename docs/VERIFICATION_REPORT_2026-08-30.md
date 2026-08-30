# Báo cáo xác minh regression — 2026-08-30

Báo cáo này ghi kết quả chạy trực tiếp trên worktree dựa trên commit `c4811ac`.
Các test được chạy tuần tự để giới hạn RAM; không chạy lại Vivado synthesis hoặc
implementation trong đợt này. Bitstream và report timing/DRC được kiểm tra từ
artifact RC2 đã commit.

## Môi trường

- Hệ điều hành: Linux `6.8.0-138-generic`, x86-64
- Verilator: `5.050`, revision `v5.050-60-g3d2421f3b`
- Python: `3.10.12`
- Cách chạy: `make -j1 regression`

## Kết quả

| Bài kiểm tra | Kết quả | Bằng chứng chính |
|---|---|---|
| RO-PUF controller | PASS | Tất cả test busy/done, deterministic digital model và mid-operation reset đạt |
| BCH fuzzy extractor | PASS | 12/12: enroll, clean, 1 lỗi, 8 lỗi, từ chối 12 lỗi và determinism |
| SHAKE256 KDF known-answer | PASS | Input 24 byte `00..17`, output 64 byte khớp từng bit với Python `hashlib.shake_256` |
| Kyber-512 cũ functional loopback | PASS | `K_server == K_client`, hoàn thành tại cycle 15.188 |
| Kyber AXI wrapper | PASS | 32 giao dịch logic; 6 raw mismatch thuộc 5 giao dịch được retry; tối đa 3 attempt |
| Full firmware/UART pipeline | PASS | RO-PUF -> FE -> KDF -> Kyber hoàn thành sau 952.479 cycle; release mode không xuất secret và đã zeroize |
| Standalone source check | PASS | Đủ file, không symlink, không `.xci`, không phụ thuộc đường dẫn workspace cũ |
| Internal release check | PASS | Artifact, timing, DRC, provenance và standalone invariant đạt |
| Artifact checksum | PASS | Bitstream và firmware khớp `ARTIFACTS.sha256` |

Lệnh xác minh bổ sung:

```sh
./scripts/release_check.sh --internal
sha256sum -c ARTIFACTS.sha256
git diff --check
```

Checksum đã xác nhận:

```text
e85e3f2bd0206485aa636b56b9256aae9a38255ab29179f6fb20e37d6b4abdfb  Kyber_System_Top.bit
9f7555fb515593f5c6a0d3b80283b9f81f7acd756cc35118c99b6dcaea3f45bf  firmware/firmware.hex
```

## Thay đổi độ tin cậy của test

- KDF mismatch/timeout nay dùng `$fatal(1, ...)`, tránh CI báo thành công giả.
- Fuzzy-extractor failure/timeout nay dùng `$fatal(1, ...)`.
- Bài Kyber được ghi đúng là functional loopback, không còn nhãn “Full KAT”.
- Standalone checker bỏ qua build/cache/log artifact đã được `.gitignore`, nhưng
  vẫn quét toàn bộ source và tài liệu được phân phối.

## Phạm vi FIPS

Kết quả SHAKE256 chỉ bao phủ một vector cố định của interface KDF 192-bit sang
512-bit. Nó chứng minh đường dữ liệu này khớp reference FIPS 202, nhưng chưa phải
bộ kiểm tra đầy đủ SHA3/SHAKE với multi-block và các biên rate.

Bài Kyber chỉ kiểm tra hai endpoint RTL cũ tạo cùng shared key. Nó không so sánh
encapsulation key, decapsulation key, ciphertext và shared secret với vector
ML-KEM chính thức; do đó chưa chứng minh tương thích FIPS 203 ML-KEM-512 và
không phải chứng nhận FIPS 140-3.

Raw mismatch xuất hiện trong AXI stress vẫn là lỗi chức năng đã biết của core
Kyber cũ. Retry làm 32 giao dịch logic hoàn thành nhưng không biến raw core thành
một implementation ML-KEM đã xác minh.

## Kết luận

Snapshot đạt regression kỹ thuật nội bộ và kiểm tra artifact RC2. Trạng thái phù
hợp là **ứng viên nghiên cứu/đánh giá nội bộ**. Public release vẫn bị chặn bởi
quyền phân phối Kyber RTL/top-level license; production security release còn bị
chặn bởi raw Kyber mismatch, thiếu FIPS 203 KAT, qualification PUF và đánh giá
side-channel/fault.
