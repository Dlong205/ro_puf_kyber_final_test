# Đạt và Tùng — Kyber/ML-KEM-512

Cập nhật **2026-09-06**. Đây là phạm vi nghiên cứu và review độc lập; Long là
người thực hiện thay đổi RTL, tích hợp test và chốt artifact.

## Phạm vi nghiên cứu/đối chiếu

- Luồng Kyber Client/Server, NTT, encode/decode, FIFO và AXI wrapper.
- Tính đúng chức năng, liveness, single-attempt và zeroize giao diện Kyber.
- Phân tích khoảng cách giữa Kyber-512 cũ và FIPS 203 ML-KEM-512.
- Đề xuất vector kiểm thử KEM và đối chiếu domain separation với phần KDF.

## Source và test liên quan

- `rtl/kyber/`
- `rtl/common/generic_fifo.sv`
- `rtl/common/generic_mult.sv`
- `rtl/soc/soc_peripherals.sv`
- `sim/kyber/`
- `sim/mlkem/`
- `docs/FIPS203_VERIFICATION_2026-09-04.md`
- `docs/CRYPTO_RTL_FREEZE_CANDIDATE_2026-09-04.md`
- `manifests/crypto_rtl_freeze_candidate.sha256`
- `docs/PROVENANCE.md`

## Chia trách nhiệm review

### Đạt — thuật toán và đặc tả

- Mapping RTL với `ML-KEM.KeyGen`, `ML-KEM.Encaps` và `ML-KEM.Decaps`.
- Vector NIST ACVP, oracle pq-crystals, serialization và domain separation.
- Compare/mux implicit rejection, claim FIPS được phép dùng và provenance.

### Tùng — vi kiến trúc RTL

- Client/Server, NTT, SHAKE stream, encode/decode và ciphertext codec.
- FIFO/BRAM/AXI handshake, liveness, single-attempt và watchdog.
- Assertion cho underflow/overflow/progress, latency và tài nguyên.

## Đã hoàn thành

- Legacy Kyber functional loopback: PASS, server/client cùng shared key.
- AXI handshake/zeroize: PASS 32 giao dịch.
- Raw gate: PASS 1.024/1.024, mismatch 0, retry 0, max attempt 1.
- Codec round-trip: PASS.
- Board full pipeline: PASS 10.000/10.000.
- Multiplier NTT dùng RTL trung lập; Vivado infer 4 DSP48E1.
- ML-KEM-512 KeyGen/Encaps/Decaps PASS 25/25 vector NIST ACVP AFT cho mỗi
  nhóm; `ek`, `dk`, ciphertext và shared secret khớp bit-exact.
- Implicit rejection PASS 175/175; timing valid/invalid bằng nhau trong các
  test hiện có.
- Candidate PASS Vivado implementation 50 MHz và board stress 10.000/10.000.

Kết luận đúng là **ML-KEM-512 internal algorithm functional PASS**. Đây không
phải chứng nhận CAVP, FIPS 140-3 hoặc review mật mã độc lập.

## Còn mở

1. Review độc lập bảng mapping giữa RTL và `ML-KEM.KeyGen`, `ML-KEM.Encaps`,
   `ML-KEM.Decaps` của FIPS 203.
2. Bổ sung interface xuất dữ liệu chẩn đoán chỉ trong testbench để so sánh từng
   intermediate với implementation tham chiếu; không bật trong release firmware.
3. Mở rộng corpus ngoài 25 vector ACVP sample nếu hướng tới chứng nhận; thêm
   test API khóa/ciphertext ngoài thay vì chỉ seed nội bộ.
4. Thêm assertion cho FIFO underflow/overflow, FSM progress, số coefficient và
   quy tắc đúng một attempt.
5. Rà constant-time, zeroization và nguồn randomness cùng Minh và Việt Anh.
6. Ký xác nhận review báo cáo JTAG/UART và stress 10.000/10.000 đã có; nếu phát
   hiện sai khác phải mở lại candidate và chạy lại gate.

Đạt và Tùng chuẩn bị tài liệu, mapping và nhận xét review. Long thực hiện thay
đổi RTL, tích hợp test và chốt kết quả trên nhánh chính của dự án.

## Definition of Done còn lại

- Có biên bản review độc lập cho mapping FIPS 203, serialization và rejection.
- Các invariant FIFO/FSM/single-attempt được review hoặc có assertion phù hợp.
- Phạm vi API nội bộ và lý do chưa hỗ trợ khóa ngoài được ghi rõ.
- Corpus/API chỉ cần mở rộng khi claim dự án mở rộng; không gọi bộ test hiện tại
  là chứng nhận FIPS.
- Nếu RTL thay đổi: Vivado timing/DRC và board stress được chạy lại.

## Lệnh kiểm tra hiện có

```sh
make kyber
make mlkem
make axi
make kyber-strict
make kyber-invalid
make kyber-codec
make kyber-long
make system
make -j1 crypto-freeze-gate
```
