# Trạng thái xác minh — integration `0.2.0-rc2-dev`, artifact `0.2.0-rc1`

Bằng chứng cập nhật đến **2026-09-17**. Nhánh phát triển FPGA hiện tại là
`codex/fpga-v2-split`; artifact FPGA được chấp nhận nằm tại tag
`fpga-mlkem512-0.2.0-rc1`. Tag `fpga-rc4-baseline` chỉ được giữ làm mốc so
sánh Kyber/FPGA cũ. Các kết quả characterization và physical route-lock sau
RC1 là bằng chứng bổ sung, không phải một phiên bản production mới.

## Tóm tắt theo cổng quyết định

Cập nhật phát triển **2026-09-09—10**: nhánh `codex/fpga-v2-split` tách từ
`73988d6`, triển khai [master plan đã hiệu chỉnh](MASTER_PLAN_REVIEW_2026-09-09.md).
Đợt đầu đã đóng gói/kiểm snapshot v4 và hoàn tất synthesis OOC các khối trên
Arty-35T: KeyGen/Decaps 11.100 LUT, Encaps 13.687, KDF legacy 9.129, FE 4.090,
PUF 197. Bản `edgecore` đầu tiên dùng 25.540 LUT (122,79%) và không fit. Đường
Edge sau đó được thay bằng KDF SHAKE256 compact; full top
`edge_puf_mlkem_core` nối RO-PUF + FE + KDF + scrub + KeyGen/Decaps đã
place/route ở 100 MHz với **19.166/20.800 LUT logic (92,14%)**, 19.403
register, 14 BRAM tile và 2 DSP. Bản cuối dùng reset đồng bộ cho scrub
state/address, đạt WNS +0,092 ns, WHS +0,053 ns, 0 net chưa route và không còn
warning reset–BRAM `REQP-1839/1840`. Xem [report và giới hạn resource ban đầu](FPGA_SPLIT_RESOURCE_BASELINE_2026-09-09.md)
và [timing closure 100 MHz](ARTY_A7_35T_100MHZ_CLOSURE_2026-09-12.md). Kết
kết luận mới là **OOC TIMING/RESOURCE FIT**, không phải board fit. Board top,
UART chẩn đoán và pin/I/O constraint đã có nhưng NO-FIT ở 26.815/20.800 Slice
LUT; chưa có confirmation release-grade hay bitstream full Edge Arty. Các
kết quả board ngày 08-09 là lịch sử của Zynq, không chứng minh Edge image mới
đã chạy trên Arty.

Ngày 2026-09-13, full Edge OOC đã PASS thêm một implementation với toàn vùng
PUF khóa placement, 136 endpoint khóa pin và 128 feedback net khóa route. Bản
v08 đạt WNS +0,053 ns, WHS +0,046 ns và 0 routing error; fingerprint vật lý
khớp baseline. Việc này đóng cổng tái lập implementation OOC, nhưng chưa thay
thế qualification trên board vì chưa có full Edge board image dùng khóa này.

Controller đã PASS KDF compact thật, mapping `d/z`, busy/held-start,
abort/no-late-start, scrub state và quét RAM Kyber. KDF compact PASS KAT
bit-exact và zeroize ở 411 chu kỳ. `edge_mlkem_core` nối Server thật đã PASS
một ca valid và một ca ciphertext sửa, cùng latency 19.800 chu kỳ đến
`secret_valid`, rồi full scrub đạt 21.850 chu kỳ. Full wrapper PUF/FE/Edge đã
PASS unit test cạnh handoff FE→KDF, elaborate và OOC synth. UART transport đã
PASS bit-level unit test và integration thật với Kyber Client/Server: nhận đủ
public key/ciphertext, `equal=1`, shared secret khớp và trả result tag. Full
board top Zynq đã fit/route ở 100 MHz với WNS `+0,562 ns`, WHS `+0,045 ns`;
bitstream sau sửa đã PASS INFO, ENROLL, SESSION đầy đủ và stress 100/100. Xem
[báo cáo bring-up Zynq 100 MHz](ZYNQ_EDGE_100MHZ_BRINGUP_2026-09-17.md).

| Cổng | Quyết định | Bằng chứng/điều kiện còn lại |
|---|---|---|
| FIPS 202 byte-oriented cần cho ML-KEM | **DONE functional** | 50/50; chưa phải chứng nhận CAVP |
| ML-KEM-512/FIPS 203 | **DONE functional nội bộ** | KAT/oracle, regression và board PASS; còn review độc lập |
| Crypto RTL freeze cuối | **CANDIDATE v4** | Offline, Vivado và đúng-image board PASS; còn review độc lập trước freeze/promote |
| FPGA RC nội bộ | **GO cho RC1 đã tag** | Candidate v4 đã có build/board evidence cách ly nhưng chưa thay artifact RC1 ở root |
| Edge Arty-35T | **OOC PASS, full board top NO-FIT** | v08 OOC: 95,84% LUT logic, WNS +0,053 ns, WHS +0,046 ns, route sạch/fingerprint khớp; board top + UART cần 26.815/20.800 Slice LUT nên không có bitstream full Edge |
| Edge Zynq-7020 100 MHz | **P&R + BOARD PASS** | Full board top 20.974 LUT, WNS +0,562 ns, WHS +0,045 ns, route sạch; PASS INFO/ENROLL/SESSION và stress 100/100 |
| Physical reproducibility của RO | **DONE cho full-SoC RC1** | Hai build sạch khớp 136 endpoint/128 route; không thay thế qualification vật lý |
| Count-margin RO-PUF | **PASS bước instrumentation** | Zynq 100/100 frame; 255/264 challenge duy nhất, chưa đủ để chốt mask N=264 |
| Candidate pool 496 cặp | **PASS diagnostic** | RTL/Vivado/Zynq 100/100; 487 cặp đạt margin p01>=4, preview N=264 cân bằng degree |
| Tool chọn mapping RO | **DONE** | Tách training/holdout, kiểm board/bitstream và manifest có hash; 19/19 host test PASS |
| Mapping RO release | **CHƯA CHỐT** | Một-board dataset chỉ đạt provisional; cần tối thiểu 3 training + 2 holdout board |
| Freeze RO-PUF | **NO-GO** | Thiếu mapping train/holdout nhiều board, same-root full-SoC, cold/warm boot, PVT và aging |
| ASIC front-end P0/P2 | **ĐANG TRIỂN KHAI** | Top/reset/filelist/elaboration PASS; accelerator zeroize đã thêm, còn PDK/memory/CPU-bus/DFT/security findings |
| Full ASIC backend/sign-off | **CHƯA BẮT ĐẦU** | Cần PDK/library, macro RO, memory mapping, SDC/CDC/DFT và crypto RTL freeze |
| Public/production release | **NO-GO** | License, security review và qualification PUF chưa đóng |

| Hạng mục | Trạng thái |
|---|---|
| Controller/CDC RO-PUF | PASS |
| BCH fuzzy extractor | PASS 29/29 ở Xilinx và ASIC-portable; reset/zeroize sâu và mid-operation abort được test |
| FE characterization logic | PASS 7.728 check trong bán kính BCH `t=8`; over-noise không được bảo đảm phát hiện |
| FIPS 202 byte-oriented cho ML-KEM | PASS 50/50, gồm 20 vector NIST CAVP |
| ML-KEM-512 KeyGen | PASS 25/25 NIST ACVP AFT, `ek`/`dk` bit-exact |
| ML-KEM-512 Encaps | PASS 25/25 NIST ACVP AFT, ciphertext/K bit-exact |
| ML-KEM-512 Decaps hợp lệ | PASS 25/25 vector độc lập pq-crystals, `equal=1` |
| ML-KEM-512 implicit rejection | PASS 175/175 `J(z || c_sai)`, `equal=0` |
| Timing Decaps valid/invalid | PASS: cùng 12.287 cycle isolated; 17.338 cycle loopback |
| SHAKE256 KDF known-answer | PASS bit-exact với datapath cố định, cycle 148 |
| Edge SHAKE256 compact | PASS KAT bit-exact ở cycle 411 và zeroize; chỉ dùng cho nhánh Edge |
| Edge valid/invalid + scrub | PASS cùng 19.800 cycle đến secret, 21.850 cycle tổng |
| Full Edge OOC Arty-35T | PASS 100 MHz: 19.166/20.800 LUT logic, WNS +0,092 ns, WHS +0,053 ns, route đủ; 40 REQP warning đã loại |
| Full Edge OOC khóa RO Arty-35T | PASS 100 MHz: 19.935/20.800 LUT logic, WNS +0,053 ns, WHS +0,046 ns, 0 routing error; 136 endpoint/128 route và fingerprint PASS |
| PUF-only Arty-35T | PASS bitgen/timing 100 MHz/JTAG/UART; replug 1.000 mẫu có HD max 5, 0 mẫu vượt BCH t=8 nhưng worst-bit 45,4%; chưa khóa route/PVT |
| ML-KEM-512 integrated functional loopback | PASS, cycle 17.338 |
| AXI register/handshake/accelerator scrub | PASS ở diagnostic và locked-secret; kiểm RAM/FIFO/sponge/core, live abort, stalled RDATA và competing write |
| Kyber raw gate dài | PASS 1.024/1.024, mismatch 0, recovered 0, max attempts 1 |
| Ciphertext codec round-trip | PASS |
| Firmware release PicoRV32 candidate v4 | PASS, protocol 1.3, capability `0x06`; bit 2 là accelerator zeroize |
| Full-system UART/PUF/FE/KDF/ML-KEM candidate v4 | PASS, 958.516 cycle; startup zeroize fail-closed |
| Standalone/pure RTL audit | PASS, không symlink, `.xci` hay dependency source ngoài |
| ASIC portability gate | PASS, ASIC-generic elaboration và primitive vendor đã cô lập |
| Crypto RTL freeze candidate v4 | Full `crypto-freeze-gate` PASS, gồm verification manifest, regression, raw 1.024, portability và crypto manifest; chưa freeze/promote vì còn review độc lập |
| Vivado candidate v4 | PASS 50 MHz tại `5943ceb`: 50.902 LUT, 30.958 FF, 30,5 BRAM, 4 DSP; WNS `+3,268 ns`, WHS `+0,037 ns`, route đủ, DRC 0 Error/Critical Warning |
| Board regression candidate v4 | PASS INFO 1.3/`0x06`, enroll/reconstruct; stress 100/100, 1.000/1.000 và 10.000/10.000, fail 0; image đang nạp volatile |
| Physical lock candidate v4 | PASS, fingerprint khớp RC1: 136 endpoint/128 fixed route |
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
cho artifact RC1 và đúng image candidate v3; hai campaign này chỉ là bằng chứng
lịch sử.

Candidate v4 đã thêm handshake crypto-accelerator zeroize, scrub sâu
NTT/FIFO/ciphertext RAM, sponge và toàn bộ state PUF/FE/KDF liên quan. Full
regression offline và raw gate 1.024/1.024 PASS; sau khi sửa BRAM inference,
Vivado 50 MHz và đúng-image board 10.000/10.000 cũng PASS ngày 2026-09-08. Claim không
bao gồm register/pipeline PicoRV32, SoC BRAM/stack, bus staging hoặc scan/DFT.
Candidate vẫn chờ review độc lập trước crypto freeze/promote.

Vivado impact candidate v3 được định danh tại
[`VIVADO_IMPACT_REPORT_CRYPTO_CANDIDATE_V3_2026-09-06.md`](VIVADO_IMPACT_REPORT_CRYPTO_CANDIDATE_V3_2026-09-06.md).
Board campaign tương ứng nằm tại
[`HARDWARE_TEST_REPORT_CRYPTO_CANDIDATE_V3_2026-09-06.md`](HARDWARE_TEST_REPORT_CRYPTO_CANDIDATE_V3_2026-09-06.md).
Kết quả tương ứng của candidate v4 nằm tại
[`VIVADO_IMPACT_REPORT_CRYPTO_CANDIDATE_V4_2026-09-08.md`](VIVADO_IMPACT_REPORT_CRYPTO_CANDIDATE_V4_2026-09-08.md)
và
[`HARDWARE_TEST_REPORT_CRYPTO_CANDIDATE_V4_2026-09-08.md`](HARDWARE_TEST_REPORT_CRYPTO_CANDIDATE_V4_2026-09-08.md).

Phạm vi, boundary và điều kiện nâng candidate thành freeze cuối được ghi tại
[`CRYPTO_RTL_FREEZE_CANDIDATE_V4_2026-09-07.md`](CRYPTO_RTL_FREEZE_CANDIDATE_V4_2026-09-07.md).

Phạm vi phụ trách và công việc tiếp theo của Đạt–Tùng, Minh, Việt Anh và Long
được theo dõi tại [`phan_cong_nhom/`](../phan_cong_nhom/README.md).

## Thứ tự công việc tiếp theo

Kế hoạch chi tiết tại
[`KE_HOACH_HOAN_THIEN_ASIC.md`](KE_HOACH_HOAN_THIEN_ASIC.md) chia công việc theo
đầu ra và điều kiện chuyển bước:

1. Review độc lập manifest candidate v4, FIPS 202/203,
   serialization/rejection và accelerator-zeroize; xử lý finding rồi mới
   freeze/promote. Vivado và đúng-image board v4 đã PASS.
2. Chốt threat model cho CPU/bus/SoC RAM/scan ngoài boundary accelerator,
   nguồn randomness, PDK/library/tool và memory/boot contract.
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
