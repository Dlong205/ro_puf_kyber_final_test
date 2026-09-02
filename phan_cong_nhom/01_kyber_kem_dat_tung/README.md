# Đạt và Tùng — Kyber KEM

## Phạm vi phụ trách

- Luồng Kyber Client/Server, NTT, encode/decode, FIFO và AXI wrapper.
- Tính đúng chức năng, liveness, single-attempt và zeroize giao diện Kyber.
- Phân tích khoảng cách giữa Kyber-512 cũ và FIPS 203 ML-KEM-512.
- Vector kiểm thử KEM và phối hợp với KDF khi thay Keccak/domain separation.

## Source và test liên quan

- `rtl/kyber/`
- `rtl/common/generic_fifo.sv`
- `rtl/common/generic_mult.sv`
- `rtl/soc/soc_peripherals.sv`
- `sim/kyber/`
- `docs/PROVENANCE.md`

## Trạng thái RC4

- Functional loopback: PASS, server/client cùng shared key.
- AXI handshake/zeroize: PASS 32 giao dịch.
- Raw gate: PASS 1.024/1.024, mismatch 0, retry 0, max attempt 1.
- Codec round-trip: PASS.
- Board full pipeline: PASS 10.000/10.000.
- Multiplier NTT dùng RTL trung lập; Vivado infer 4 DSP48E1.
- Chưa đối chiếu `ek`, `dk`, ciphertext và shared secret với KAT FIPS 203.

## Việc tiếp theo

1. Lập bảng mapping từng bước giữa RTL hiện tại và `ML-KEM.KeyGen`,
   `ML-KEM.Encaps`, `ML-KEM.Decaps` của FIPS 203.
2. Chốt giữ core cũ làm baseline hay thay bằng ML-KEM-512 trước ASIC backend.
3. Bổ sung interface xuất dữ liệu chẩn đoán chỉ trong testbench để so sánh từng
   intermediate với implementation tham chiếu; không bật trong release firmware.
4. Chạy KAT chính thức cho key generation, encapsulation và decapsulation, gồm
   nhánh implicit rejection/ciphertext sai.
5. Thêm assertion cho FIFO underflow/overflow, FSM progress, số coefficient và
   quy tắc đúng một attempt.
6. Rà constant-time, zeroization và nguồn randomness cùng Minh và Việt Anh.

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
