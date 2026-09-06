# Trạng thái xác minh — integration `0.2.0-rc2-dev`, artifact `0.2.0-rc1`

Bằng chứng cập nhật đến **2026-09-06**. Nhánh làm việc tích hợp là
`codex/asic-frontend-mlkem512`, tách từ `codex/fips202-mlkem`; artifact FPGA được chấp nhận nằm tại tag
`fpga-mlkem512-0.2.0-rc1`. Tag `fpga-rc4-baseline` chỉ được giữ làm mốc so
sánh Kyber/FPGA cũ. Các kết quả characterization và physical route-lock sau
RC1 là bằng chứng bổ sung, không phải một phiên bản production mới.

## Tóm tắt theo cổng quyết định

| Cổng | Quyết định | Bằng chứng/điều kiện còn lại |
|---|---|---|
| FIPS 202 byte-oriented cần cho ML-KEM | **DONE functional** | 50/50; chưa phải chứng nhận CAVP |
| ML-KEM-512/FIPS 203 | **DONE functional nội bộ** | KAT/oracle, regression và board PASS; còn review độc lập |
| Crypto RTL freeze cuối | **BLOCKED** | Candidate v3 PASS full gate/Vivado/board nhưng AI pre-review tìm thấy P0 secure-zeroize; còn phải sửa và review độc lập |
| FPGA RC nội bộ | **GO** | Bitstream/firmware/report/checksum và board regression có trong repo |
| Physical reproducibility của RO | **DONE cho full-SoC RC1** | Hai build sạch khớp 136 endpoint/128 route; không thay thế qualification vật lý |
| Freeze RO-PUF | **NO-GO** | Thiếu same-root full-SoC, count-margin, cold/warm boot, PVT, aging và nhiều board |
| ASIC front-end P0/P2 | **ĐANG TRIỂN KHAI** | Top reset thật, filelist/manifest và structural lint PASS; còn warning/PDK/memory/security findings |
| Full ASIC backend/sign-off | **CHƯA BẮT ĐẦU** | Cần PDK/library, macro RO, memory mapping, SDC/CDC/DFT và crypto RTL freeze |
| Public/production release | **NO-GO** | License, security review và qualification PUF chưa đóng |

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
| SHAKE256 KDF known-answer | PASS bit-exact với datapath cố định, cycle 148 |
| ML-KEM-512 integrated functional loopback | PASS, cycle 17.338 |
| AXI register/handshake/clear nhìn thấy | PASS, 32 giao dịch single-attempt; deep scrub chưa đóng ở v3 |
| Kyber raw gate dài | PASS 1.024/1.024, mismatch 0, recovered 0, max attempts 1 |
| Ciphertext codec round-trip | PASS |
| Firmware release PicoRV32 | PASS, protocol 1.2, capability `0x06` |
| Full-system UART/PUF/FE/KDF/ML-KEM | PASS, 956.564 cycle |
| Standalone/pure RTL audit | PASS, không symlink, `.xci` hay dependency source ngoài |
| ASIC portability gate | PASS, ASIC-generic elaboration và primitive vendor đã cô lập |
| Crypto RTL freeze candidate v3 | Full `crypto-freeze-gate`, Vivado impact và board PASS; không promote vì P0 secure-zeroize |
| Netlist RO Xilinx | PASS, 128 LUT/128 feedback net/128 constraint loop |
| Physical lock RO full-SoC | PASS, 136 endpoint/128 fixed route; 2 build khớp fingerprint V2 |
| Board image route-lock `locked_b` | PASS INFO/enroll/reconstruct, stress 10.000/10.000; board đã trở lại RC1 |
| Vivado synthesis/implementation artifact RC1/v2 | PASS, `xc7z020clg400-2`, không IP sinh tự động |
| Route artifact RC1/v2 | PASS, 0 failed/unrouted/partially-routed net |
| Timing 50 MHz artifact RC1/v2 | PASS, WNS `+2,226 ns`, WHS `+0,034 ns`, TNS/THS `0` |
| DRC artifact RC1/v2 | PASS, 0 lỗi; 165 warning đã phân loại |
| Vivado synthesis/implementation candidate v3 | PASS 50 MHz tại `1dcdad8`, 49.886 LUT, 30.649 register, 25 BRAM, 4 DSP |
| Route/timing candidate v3 | PASS, 70.741/70.741 net; WNS `+4,732 ns`, WHS `+0,034 ns`, TNS/THS `0` |
| DRC/physical lock candidate v3 | 0 Error, 165 warning đã phân loại; fingerprint khớp RC1, 136 endpoint/128 route |
| Board regression candidate v3 | PASS INFO/enroll/reconstruct; stress 100/100, 1.000/1.000 và 10.000/10.000; sau đó restore RC1 |
| JTAG/INFO/enroll/reconstruct ML-KEM RC1 | PASS trên `xc7z020_1`, protocol 1.2/capability `0x06` |
| JTAG/INFO/enroll/reconstruct RC4 | PASS trên `xc7z020_1` |
| Stress board RC4 | PASS 100/100, 1.000/1.000 và 10.000/10.000 |
| Stress board ML-KEM RC1 | PASS 100/100, 1.000/1.000 và 10.000/10.000 |
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

## Định danh baseline RC4 bất biến

- Bitstream tại tag `fpga-rc4-baseline`: 4.045.676 byte
- SHA-256: `bd8153f8ab58f0a704b2f696c54ed1f57d1a31b951d273f547b33926d239f348`
- Firmware SHA-256: `d8774e78d37c8fbc34d799426ce7a0150715569217bb921df3c0c1519348ec8e`
- Tài nguyên: 51.682/53.200 LUT (`97,15%`), 30.554 register, 23,5 BRAM, 4 DSP
- Warning DRC: 4 `DPOP-2`, 32 `LUTLP-2`, 128 `PDCN-1569`, 1 `ZPS7-1`
- Methodology: 72 `TIMING-17` do clock RO bất định; không phải CDC/ASIC sign-off
- Board run 10.000: 29,119 ms/giao dịch, 34,342 giao dịch/s, Fail 0

## Artifact ML-KEM `0.2.0-rc1`

- Source commit: `8d2e8cda6d31e04e1557d64ca53d187cd85afc92`
- Bitstream `Kyber_System_Top.bit`: 4.045.676 byte, SHA-256
  `183e0af367376ebd7ca6bc2f3747314fd0602306a630af2a2e51858ef1f20e8e`
- Tài nguyên sau route: 49.909/53.200 LUT (`93,81%`), 30.649 register,
  25 BRAM tile, 4 DSP
- Route: 70.739/70.739 routable net hoàn tất, 0 routing error
- Timing 50 MHz: WNS `+2,226 ns`, WHS `+0,034 ns`, TNS/THS `0`
- DRC: 0 Error/Critical Warning; 165 warning cùng nhóm đã biết của RC4
- Audit RO: 128 LUT, 128 feedback net và 128 constraint loop
- Board run 10.000: 29,608 ms/giao dịch, 33,775 giao dịch/s, Fail 0
- Trạng thái artifact: đã quảng bá lên root sau khi JTAG/INFO/enroll/reconstruct
  và stress board PASS

Xem `HARDWARE_TEST_REPORT_MLKEM_CANDIDATE_2026-09-04.md`,
`HARDWARE_TEST_REPORT_RC4_2026-09-03.md`,
`FIPS202_VERIFICATION_2026-09-03.md` và
`FIPS203_VERIFICATION_2026-09-04.md`. Nhãn phù hợp của nhánh hiện tại là
**ML-KEM-512 internal algorithm functional PASS**; không phải chứng nhận
CAVP/FIPS 140-3 hay release production. API kiểm tra `ek/dk` ngoài, mở rộng
corpus ngoài sample và review độc lập vẫn chưa đóng. Board regression đã PASS
cho artifact RC1 và đúng image candidate v3; v3 chưa được promote do blocker
zeroization sâu trong NTT/FIFO RAM, sponge, FE và KDF.

Vivado impact candidate v3 được định danh tại
[`VIVADO_IMPACT_REPORT_CRYPTO_CANDIDATE_V3_2026-09-06.md`](VIVADO_IMPACT_REPORT_CRYPTO_CANDIDATE_V3_2026-09-06.md).
Board campaign tương ứng nằm tại
[`HARDWARE_TEST_REPORT_CRYPTO_CANDIDATE_V3_2026-09-06.md`](HARDWARE_TEST_REPORT_CRYPTO_CANDIDATE_V3_2026-09-06.md).

Phạm vi, manifest và điều kiện nâng candidate thành freeze cuối được ghi tại
[`CRYPTO_RTL_FREEZE_CANDIDATE_2026-09-04.md`](CRYPTO_RTL_FREEZE_CANDIDATE_2026-09-04.md).

Phạm vi phụ trách và công việc tiếp theo của Đạt–Tùng, Minh, Việt Anh và Long
được theo dõi tại [`phan_cong_nhom/`](../phan_cong_nhom/README.md).

## Thứ tự công việc tiếp theo

Kế hoạch chi tiết tại
[`KE_HOACH_HOAN_THIEN_ASIC.md`](KE_HOACH_HOAN_THIEN_ASIC.md) chia công việc theo
đầu ra và điều kiện chuyển bước:

1. Chốt phạm vi full-system, threat model và PDK/library/tool sớm; lưu baseline
   Git, tạo filelist ASIC và kiểm kê reset/memory/boot.
2. Review độc lập FIPS 202/203, serialization/rejection, nguồn randomness,
   quyền truy cập khóa và zeroization; sửa các điểm ảnh hưởng freeze.
3. Chạy lint và synthesis thử digital core khi đủ đầu vào công nghệ. Có thể
   thử P&R khối này trong lúc triển khai same-root/count-margin, entropy và
   nghiên cứu macro RO ASIC.
4. Hoàn thiện macro RO, memory/pad views, SDC/CDC/DFT, regression/equivalence;
   chốt RTL và đầu vào trước floorplan cuối của toàn hệ thống.
5. Hoàn tất full-system P&R/sign-off/GDS; sau chế tạo mới đo qualification
   PUF ASIC trên nhiều chip, PVT, power-cycle và aging. Campaign FPGA hỗ trợ
   đánh giá baseline FPGA, không thay thế phép đo silicon ASIC.

Waveform trình bày và video demo vẫn được hoãn theo quyết định của nhóm; chúng
không được dùng để che các gate kỹ thuật còn mở ở trên.
