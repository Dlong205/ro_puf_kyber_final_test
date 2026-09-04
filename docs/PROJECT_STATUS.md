# Trạng thái xác minh dự án — RC4 + nhánh ML-KEM-512

| Hạng mục | Trạng thái |
|---|---|
| Controller/CDC RO-PUF | PASS |
| BCH fuzzy extractor | PASS 12/12 |
| FIPS 202 byte-oriented cho ML-KEM | PASS 50/50, gồm 20 vector NIST CAVP |
| ML-KEM-512 KeyGen | PASS 25/25 NIST ACVP AFT, `ek`/`dk` bit-exact |
| ML-KEM-512 Encaps | PASS 25/25 NIST ACVP AFT, ciphertext/K bit-exact |
| ML-KEM-512 Decaps hợp lệ | PASS 25/25 vector độc lập pq-crystals, `equal=1` |
| ML-KEM-512 implicit rejection | PASS 175/175 `J(z || c_sai)`, `equal=0` |
| Timing Decaps valid/invalid | PASS: cùng 12.287 cycle isolated; 17.338 cycle loopback |
| SHAKE256 KDF known-answer | PASS sau khi chuyển sang sponge mới, cycle 122 |
| ML-KEM-512 integrated functional loopback | PASS, cycle 17.338 |
| AXI register/handshake/zeroize | PASS, 32 giao dịch single-attempt |
| Kyber raw gate dài | PASS 1.024/1.024, mismatch 0, recovered 0, max attempts 1 |
| Ciphertext codec round-trip | PASS |
| Firmware release PicoRV32 | PASS, protocol 1.2, capability `0x06` |
| Full-system UART/PUF/FE/KDF/ML-KEM | PASS, 956.548 cycle |
| Standalone/pure RTL audit | PASS, không symlink, `.xci` hay dependency source ngoài |
| ASIC portability gate | PASS, ASIC-generic elaboration và primitive vendor đã cô lập |
| Crypto RTL freeze candidate | PASS functional/portability + manifest; chờ Vivado/board mới |
| Netlist RO Xilinx | PASS, 128 LUT/128 feedback net/128 constraint loop |
| Vivado synthesis/implementation | PASS, `xc7z020clg400-2`, không IP sinh tự động |
| Route | PASS, 0 failed/unrouted/partially-routed net |
| Timing 50 MHz | PASS, WNS `+3,663 ns`, WHS `+0,056 ns`, TNS/THS `0` |
| DRC | PASS, 0 lỗi; 165 warning đã phân loại |
| JTAG/INFO/enroll/reconstruct | PASS trên `xc7z020_1` |
| Stress board RC4 | PASS 100/100, 1.000/1.000 và 10.000/10.000 |
| Đặc trưng nhiều board/power-cycle/điện áp/nhiệt độ | CHƯA CHẠY |
| Public redistribution license | BỊ CHẶN |

## Lỗi Kyber đã xử lý trong RC3

Stress dài phát hiện FSM từng rời cửa sổ sinh ma trận theo số cycle cố định trước
khi rejection sampling tạo đủ coefficient. NTT Client/Server sau đó chờ FIFO đã
cạn và có thể treo hoặc tạo mismatch. RC3 thay điều kiện kết thúc bằng số word
thực nhận, giữ SHAKE ở matrix pattern đúng giai đoạn, và chỉ tăng NTT counter khi
FIFO có dữ liệu. Firmware và testbench không còn retry.

Vector từng tái hiện lỗi và toàn bộ dải 1.024 vector nay PASS single-attempt. Trên
board, lỗi cũ ở khoảng giao dịch 209 không tái hiện trong run 10.000 liên tiếp.
Đây là bằng chứng chức năng mạnh hơn RC2. Nhánh phát triển sau RC4 còn bổ sung
KAT ML-KEM bit-exact và implicit rejection; vẫn chưa phải formal proof.

## Định danh artifact RC4

- Bitstream: `Kyber_System_Top.bit`, 4.045.676 byte
- SHA-256: `bd8153f8ab58f0a704b2f696c54ed1f57d1a31b951d273f547b33926d239f348`
- Firmware SHA-256: `d8774e78d37c8fbc34d799426ce7a0150715569217bb921df3c0c1519348ec8e`
- Tài nguyên: 51.682/53.200 LUT (`97,15%`), 30.554 register, 23,5 BRAM, 4 DSP
- Warning DRC: 4 `DPOP-2`, 32 `LUTLP-2`, 128 `PDCN-1569`, 1 `ZPS7-1`
- Methodology: 72 `TIMING-17` do clock RO bất định; không phải CDC/ASIC sign-off
- Board run 10.000: 29,119 ms/giao dịch, 34,342 giao dịch/s, Fail 0

Xem `HARDWARE_TEST_REPORT_RC4_2026-09-03.md`,
`FIPS202_VERIFICATION_2026-09-03.md` và
`FIPS203_VERIFICATION_2026-09-04.md`. Nhãn phù hợp của nhánh hiện tại là
**ML-KEM-512 internal algorithm functional PASS**; không phải chứng nhận
CAVP/FIPS 140-3 hay release production. API kiểm tra `ek/dk` ngoài, mở rộng
corpus ngoài sample, review độc lập và implementation FPGA mới vẫn chưa đóng.

Phạm vi, manifest và điều kiện nâng candidate thành freeze cuối được ghi tại
[`CRYPTO_RTL_FREEZE_CANDIDATE_2026-09-04.md`](CRYPTO_RTL_FREEZE_CANDIDATE_2026-09-04.md).

Phạm vi phụ trách và công việc tiếp theo của Đạt–Tùng, Minh, Việt Anh và Long
được theo dõi tại [`phan_cong_nhom/`](../phan_cong_nhom/README.md).
