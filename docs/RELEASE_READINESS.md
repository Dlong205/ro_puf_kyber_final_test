# Mức độ sẵn sàng — integration `0.2.0-rc2-dev`, artifact `0.2.0-rc1`

Đích hiện tại là XC7Z020-2CLG400I, pure RTL chỉ PL, clock ngoài 50 MHz. Version
`0.2.0-rc2-dev` ngăn việc đóng gói nhánh sau route-lock dưới cùng tên với RC1
đã tag; nó chưa phải artifact phần cứng mới. Tài liệu này phân biệt hoàn thành
nội dung triển khai FPGA với public/production release. Trạng thái cập nhật đến
**2026-09-07**.

## Định danh trạng thái

- RTL tạo artifact RC1: commit `8d2e8cd`.
- Commit quảng bá/tag artifact: `7abbd79`, tag
  `fpga-mlkem512-0.2.0-rc1`.
- Physical lock/characterization sau RC1: đã tích hợp đến commit `36fc6da` trước
  đợt đồng bộ tài liệu này.
- `Kyber_System_Top.bit` và `reports/post_route_*` ở root vẫn là bằng chứng của
  artifact RC1, không phải implementation mới của toàn nhánh `rc2-dev`.
- Hai image/DCP `locked_a` và `locked_b` là bằng chứng tái lập trong `build/`,
  được giữ ngoài Git; XDC/fingerprint và báo cáo tóm tắt được track.

| Mức phát hành | Quyết định hiện tại |
|---|---|
| Chia sẻ nội bộ source + RC1 trong repo private | **GO**, kèm các giới hạn trong `NOTICE.md` và `SECURITY.md` |
| Chốt crypto RTL freeze cuối | **CHƯA**; v4 accelerator scrub và full manifest gate PASS offline, còn review độc lập/Vivado/board v4 |
| Chốt PUF là golden/production | **NO-GO**, thiếu same-root/PVT/nhiều board/entropy |
| Bắt đầu khảo sát ASIC frontend | **GO có điều kiện**, dùng portability gate |
| Full ASIC backend/sign-off | **CHƯA**, thiếu PDK/macro/memory/SDC/DFT và các freeze đầu vào |
| Public release | **BỊ CHẶN** bởi quyền phân phối/top-level license |

## Cổng kỹ thuật FPGA

| Cổng | Trạng thái |
|---|---|
| Source độc lập, không link workspace cũ | PASS |
| Không XCI/Xilinx IP sinh tự động | PASS |
| Firmware release build v4 | PASS, protocol 1.3/`0x06`; startup zeroize fail-closed |
| RO-PUF controller regression | PASS |
| BCH enroll/correct regression | PASS 29/29; characterization 7.728 check trong `t=8` |
| FIPS 202 byte-oriented cho ML-KEM | PASS 50/50, gồm 20 vector NIST CAVP |
| ML-KEM-512 KeyGen | PASS 25/25 NIST ACVP AFT, `ek`/`dk` bit-exact |
| ML-KEM-512 Encaps | PASS 25/25 NIST ACVP AFT, ciphertext/K bit-exact |
| ML-KEM-512 Decaps và implicit rejection | PASS 25/25 + 175/175; K/J exact, timing bằng nhau |
| SHAKE256 KDF KAT | PASS bit-exact, datapath cố định 24-byte → 64-byte |
| Kyber functional loopback | PASS |
| AXI accelerator-zeroize | PASS deep RAM/FIFO/sponge/core, live abort, stalled RDATA và competing write |
| Kyber single-attempt 1.024 vector | PASS, mismatch 0, retry 0 |
| Ciphertext codec round-trip | PASS |
| Full-system firmware/UART simulation v4 | PASS, 958.516 cycle |
| Abstraction backend FPGA/ASIC và ASIC-generic elaboration | PASS; chưa phải ASIC synthesis/P&R |
| Crypto RTL freeze candidate v4 | Full offline freeze gate + ba manifest PASS; chưa freeze/promote |
| Candidate v4 Vivado/board | **PENDING/PENDING** |
| Audit netlist RO Xilinx | PASS, 128/128 feedback net được constraint |
| Tái lập placement/pin/route RO full-SoC | PASS, 2 build sạch khớp fingerprint RC1 |
| Board regression image route-lock | PASS INFO/enroll/reconstruct và 10.000/10.000; đã restore RC1 |
| Shared-secret export tắt | PASS |
| Watchdog có giới hạn, không retry | PASS |
| Synthesis/place/route/timing artifact RC1/v2 | PASS ở 50 MHz, WNS `+2,226 ns`, WHS `+0,034 ns` |
| DRC/route artifact RC1/v2 | PASS, 0 lỗi, 0 net chưa route |
| Candidate v3 Vivado impact | PASS 50 MHz: 49.886 LUT, WNS `+4,732 ns`, WHS `+0,034 ns`, route đủ, 0 Error DRC |
| Candidate v3 board regression | PASS INFO/enroll/reconstruct và 100/1.000/10.000 vòng; board đã restore RC1 |
| INFO/enroll/reconstruct artifact RC1/v2 trên board | PASS, protocol 1.2/capability `0x06`; bằng chứng lịch sử |
| INFO/enroll/reconstruct RC4 trên board | PASS |
| Stress board RC4 | PASS 100, 1.000 và 10.000 vòng |
| Stress board ML-KEM RC1 | PASS 100, 1.000 và 10.000 vòng |
| Report/checksum/provenance | PASS |
| Waveform trình bày/video demo | HOÃN theo kế hoạch |
| Quyền phân phối công khai | **BỊ CHẶN** |

## Kết luận cho nội dung triển khai FPGA

ML-KEM RC1 đã hoàn thành baseline kỹ thuật FPGA cần thiết để khảo sát frontend
ASIC: RTL chức năng, regression, cổng stress raw không retry,
firmware/host, implementation, timing, DRC, bitstream và test end-to-end trên
board đều có bằng chứng. Run dài 10.000 đạt 100%, latency trung bình 29,608 ms
và throughput 33,775 giao dịch/s. Primitive LUT6/CARRY4 đã được tách khỏi source
list ASIC và multiplier NTT không còn phụ thuộc tên/primitive DSP48.

Kết luận này chưa bật đèn xanh cho full ASIC backend/sign-off: crypto freeze
độc lập, PUF qualification, PDK, macro RO, memory mapping, SDC/CDC và DFT vẫn
phải được đóng hoặc có kế hoạch/waiver được review. Candidate v4 đã đóng P0
scrub sâu ở phạm vi RTL crypto accelerator, nhưng CPU/register/SoC RAM/bus và
scan/DFT nằm ngoài boundary đã chứng minh.

Điều này không đồng nghĩa sản phẩm bảo mật production. Bốn primitive FIPS 202
đã PASS regression byte-oriented. Nhánh phát triển ML-KEM-512 đã đối chiếu
bit-exact KeyGen/Encaps với toàn bộ 25 vector ML-KEM-512 AFT tương ứng trong
sample NIST ACVP, 25 Decaps hợp lệ và 175 ca implicit rejection với oracle độc
lập. Artifact RC1/candidate v2 tại source `8d2e8cd` đã hoàn tất Vivado
implementation và board regression. Candidate v3 tại `1dcdad8` đã PASS Vivado
implementation cách ly, physical-lock audit và board regression 10.000/10.000,
nhưng không được quảng bá do zeroization sâu chưa đóng. Candidate v4 đã PASS
offline regression và raw 1.024/1.024 sau khi thêm accelerator scrub; Vivado và
board đúng v4 vẫn PENDING. Thiết kế vẫn chưa có API kiểm tra khóa ngoài.
RO-PUF mới được đo trên một board ở điều kiện phòng. Route-lock đã đóng rủi ro
implementation ngẫu nhiên làm đổi miền RO giữa các build full-SoC;
qualification PVT, same-root và nhiều board vẫn chưa đóng.

Fuzzy-extractor characterization đã PASS 7.728 check sửa lỗi trong bán kính
thiết kế `t=8`. Một delta codeword ngoài bán kính có weight 41 vẫn có thể cho
`success=1` nhưng phục hồi sai root; đây là giới hạn expected của decoder, nên
không được tuyên bố mọi over-noise đều bị phát hiện.

## Điều kiện NO-GO trước public/production release

1. Có quyền phân phối RTL Kyber/Xing-Li/Tuấn Đạt bằng văn bản.
2. Chọn top-level license tương thích cho code thuộc dự án và GPL của RO-PUF.
3. Bổ sung corpus ngoài sample ACVP, chốt lại API nếu cần nhập khóa ngoài và
   thực hiện review độc lập.
4. Đặc trưng PUF qua nhiều board, cold/warm power-cycle, điện áp, nhiệt độ và aging.
5. Đo entropy/reliability/uniqueness cùng intra/inter-device Hamming distance.
6. Dùng entropy source/DRBG đã review thay cho cơ chế diversify thử nghiệm.
7. Review constant-time, side-channel, fault-injection, CPU/bus/scan boundary
   và zeroization vật lý/netlist.
8. Bổ sung formal/property verification và CI build tái lập được.

## Định danh baseline RC4 bất biến

- Bitstream tại tag `fpga-rc4-baseline`: 4.045.676 byte
- SHA-256: `bd8153f8ab58f0a704b2f696c54ed1f57d1a31b951d273f547b33926d239f348`
- Timing 50 MHz: WNS `+3,663 ns`, TNS `0`, WHS `+0,056 ns`, THS `0`
- Tài nguyên: 51.682/53.200 LUT (`97,15%`), 30.554 register, 23,5 BRAM, 4 DSP
- DRC: 0 lỗi; 4 `DPOP-2`, 32 `LUTLP-2`, 128 `PDCN-1569`, 1 `ZPS7-1`
- Methodology: 72 `TIMING-17` do counter chạy bằng clock RO vật lý bất định,
  2 `LUTAR-1`, 4 `TIMING-18`, 32 `TIMING-23`; đã phân loại nhưng chưa được coi
  là CDC/RDC sign-off
- Giao thức release: 1.2, INFO `4B 50 01 02 06`
- Board: Digilent `260515110006`, `/dev/ttyUSB1`, stress 10.000/10.000

## Định danh artifact ML-KEM `0.2.0-rc1`

- Source commit: `8d2e8cda6d31e04e1557d64ca53d187cd85afc92`
- Bitstream root: `Kyber_System_Top.bit`, 4.045.676 byte
- SHA-256 bitstream:
  `183e0af367376ebd7ca6bc2f3747314fd0602306a630af2a2e51858ef1f20e8e`
- Timing 50 MHz: WNS `+2,226 ns`, TNS `0`, WHS `+0,034 ns`, THS `0`
- Tài nguyên: 49.909/53.200 LUT (`93,81%`), 30.649 register, 25 BRAM, 4 DSP
- Route: 70.739/70.739 routable net hoàn tất, 0 routing error
- DRC: 0 Error/Critical Warning; 4 `DPOP-2`, 32 `LUTLP-2`, 128
  `PDCN-1569`, 1 `ZPS7-1`
- Board: Digilent `260515110006`, `/dev/ttyUSB1`; INFO/enroll/reconstruct PASS
- Stress: 100/100, 1.000/1.000, 10.000/10.000; fail/timeout/retry bằng 0
- Run 10.000: 29,608 ms/giao dịch, 33,775 giao dịch/s

Trạng thái đúng là **ML-KEM-512 FPGA RC1 đã PASS các gate và board lịch sử;
candidate v4 secure-zeroize đã PASS offline nhưng chưa có Vivado/board v4 và
chưa được crypto freeze**. Public release vẫn phải dừng ở license gate;
production release còn phải dừng ở qualification PUF và xác minh mật mã/bảo
mật. Các PASS FIPS/ACVP nêu ở đây là functional bit-exact, không phải NIST
validation/certification.
