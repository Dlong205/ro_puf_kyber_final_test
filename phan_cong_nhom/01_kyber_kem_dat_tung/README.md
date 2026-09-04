# Đạt và Tùng — Kyber KEM

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
- `docs/PROVENANCE.md`

## Trạng thái hiện tại

- Functional loopback: PASS, server/client cùng shared key.
- AXI handshake/zeroize: PASS 32 giao dịch.
- Raw gate: PASS 1.024/1.024, mismatch 0, retry 0, max attempt 1.
- Codec round-trip: PASS.
- Board full pipeline: PASS 10.000/10.000.
- Multiplier NTT dùng RTL trung lập; Vivado infer 4 DSP48E1.
- ML-KEM-512 KeyGen/Encaps/Decaps PASS 25/25 vector NIST ACVP AFT cho mỗi
  nhóm; `ek`, `dk`, ciphertext và shared secret khớp bit-exact.
- Implicit rejection PASS 175/175; timing valid/invalid bằng nhau trong các
  test hiện có.
- Candidate PASS Vivado implementation 50 MHz nhưng chưa chạy lại board.

## Việc tiếp theo

1. Review độc lập bảng mapping giữa RTL và `ML-KEM.KeyGen`, `ML-KEM.Encaps`,
   `ML-KEM.Decaps` của FIPS 203.
2. Bổ sung interface xuất dữ liệu chẩn đoán chỉ trong testbench để so sánh từng
   intermediate với implementation tham chiếu; không bật trong release firmware.
3. Mở rộng corpus ngoài 25 vector ACVP sample nếu hướng tới chứng nhận; thêm
   test API khóa/ciphertext ngoài thay vì chỉ seed nội bộ.
4. Thêm assertion cho FIFO underflow/overflow, FSM progress, số coefficient và
   quy tắc đúng một attempt.
5. Rà constant-time, zeroization và nguồn randomness cùng Minh và Việt Anh.
6. Chạy JTAG/UART và stress 10.000 giao dịch với bitstream candidate.

Đạt và Tùng chuẩn bị tài liệu, mapping và nhận xét review. Long thực hiện thay
đổi RTL, tích hợp test và chốt kết quả trên nhánh chính của dự án.

## Definition of Done

- Vector ML-KEM-512 chính thức khớp bit-exact hoặc tài liệu ghi rõ quyết định
  không tuyên bố FIPS 203.
- Không mismatch, timeout, FIFO starvation hay retry trong regression dài.
- Interface/latency được tài liệu hóa và full-system simulation PASS.
- Nếu RTL thay đổi: Vivado timing/DRC và board stress được chạy lại.

## Lệnh kiểm tra hiện có

```sh
make kyber
make axi
make kyber-strict
make kyber-codec
make kyber-long
make system
```
