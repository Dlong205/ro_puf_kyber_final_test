# Mức độ sẵn sàng phát hành — RC4 và ML-KEM candidate

Đích hiện tại là XC7Z020-2CLG400I, pure RTL chỉ PL, clock ngoài 50 MHz. Tài liệu
này phân biệt hoàn thành nội dung triển khai FPGA với public/production release.

## Cổng kỹ thuật FPGA

| Cổng | Trạng thái |
|---|---|
| Source độc lập, không link workspace cũ | PASS |
| Không XCI/Xilinx IP sinh tự động | PASS |
| Firmware release build | PASS |
| RO-PUF controller regression | PASS |
| BCH enroll/correct/reject regression | PASS 12/12 |
| FIPS 202 byte-oriented cho ML-KEM | PASS 50/50, gồm 20 vector NIST CAVP |
| ML-KEM-512 KeyGen | PASS 25/25 NIST ACVP AFT, `ek`/`dk` bit-exact |
| ML-KEM-512 Encaps | PASS 25/25 NIST ACVP AFT, ciphertext/K bit-exact |
| ML-KEM-512 Decaps và implicit rejection | PASS 25/25 + 175/175; K/J exact, timing bằng nhau |
| SHAKE256 KDF KAT | PASS bit-exact, datapath cố định 24-byte → 64-byte |
| Kyber functional loopback | PASS |
| AXI start/status/key-match/zeroize | PASS |
| Kyber single-attempt 1.024 vector | PASS, mismatch 0, retry 0 |
| Ciphertext codec round-trip | PASS |
| Full-system firmware/UART simulation | PASS |
| Backend FPGA/ASIC và ASIC-generic elaboration | PASS |
| Crypto RTL freeze candidate v2 | PASS regression/manifest/Vivado; chờ board mới |
| Audit netlist RO Xilinx | PASS, 128/128 feedback net được constraint |
| Shared-secret export tắt | PASS |
| Watchdog có giới hạn, không retry | PASS |
| Synthesis/place/route/timing ML-KEM | PASS ở 50 MHz, WNS `+2,226 ns`, WHS `+0,034 ns` |
| DRC/route ML-KEM | PASS, 0 lỗi, 0 net chưa route |
| INFO/enroll/reconstruct ML-KEM trên board | **PENDING** |
| INFO/enroll/reconstruct RC4 trên board | PASS |
| Stress board RC4 | PASS 100, 1.000 và 10.000 vòng |
| Report/checksum/provenance | PASS |
| Waveform trình bày/video demo | HOÃN theo kế hoạch |
| Quyền phân phối công khai | **BỊ CHẶN** |

## Kết luận cho nội dung triển khai FPGA

RC4 đã hoàn thành phần kỹ thuật FPGA cần thiết trước khi chuyển sang ASIC
backend: RTL chức năng, regression, cổng stress raw không retry, firmware/host,
implementation, timing, DRC, bitstream và test end-to-end trên board đều có bằng
chứng. Run dài 10.000 đạt 100%, latency trung bình 29,119 ms và throughput
34,342 giao dịch/s. Primitive LUT6/CARRY4 đã được tách khỏi source list ASIC và
multiplier NTT không còn phụ thuộc tên/primitive DSP48.

Điều này không đồng nghĩa sản phẩm bảo mật production. Bốn primitive FIPS 202
đã PASS regression byte-oriented. Nhánh phát triển ML-KEM-512 đã đối chiếu
bit-exact KeyGen/Encaps với toàn bộ 25 vector ML-KEM-512 AFT tương ứng trong
sample NIST ACVP, 25 Decaps hợp lệ và 175 ca implicit rejection với oracle độc
lập. Candidate đã hoàn tất Vivado implementation nhưng chưa chạy JTAG/UART và
stress lại trên board. Thiết kế cũng chưa có API kiểm tra khóa ngoài.
RO-PUF mới được đo trên một board ở điều kiện phòng.

## Điều kiện NO-GO trước public/production release

1. Có quyền phân phối RTL Kyber/Xing-Li/Tuấn Đạt bằng văn bản.
2. Chọn top-level license tương thích cho code thuộc dự án và GPL của RO-PUF.
3. Bổ sung corpus ngoài sample ACVP, chốt lại API nếu cần nhập khóa ngoài và
   thực hiện review độc lập.
4. Đặc trưng PUF qua nhiều board, cold/warm power-cycle, điện áp, nhiệt độ và aging.
5. Đo entropy/reliability/uniqueness cùng intra/inter-device Hamming distance.
6. Dùng entropy source/DRBG đã review thay cho cơ chế diversify thử nghiệm.
7. Review constant-time, side-channel, fault-injection và zeroization vật lý.
8. Bổ sung formal/property verification và CI build tái lập được.

## Định danh implementation RC4

- Bitstream: `Kyber_System_Top.bit`, 4.045.676 byte
- SHA-256: `bd8153f8ab58f0a704b2f696c54ed1f57d1a31b951d273f547b33926d239f348`
- Timing 50 MHz: WNS `+3,663 ns`, TNS `0`, WHS `+0,056 ns`, THS `0`
- Tài nguyên: 51.682/53.200 LUT (`97,15%`), 30.554 register, 23,5 BRAM, 4 DSP
- DRC: 0 lỗi; 4 `DPOP-2`, 32 `LUTLP-2`, 128 `PDCN-1569`, 1 `ZPS7-1`
- Methodology: 72 `TIMING-17` do counter chạy bằng clock RO vật lý bất định,
  2 `LUTAR-1`, 4 `TIMING-18`, 32 `TIMING-23`; đã phân loại nhưng chưa được coi
  là CDC/RDC sign-off
- Giao thức release: 1.2, INFO `4B 50 01 02 06`
- Board: Digilent `260515110006`, `/dev/ttyUSB1`, stress 10.000/10.000

## Định danh implementation ML-KEM candidate

- Source commit: `8d2e8cda6d31e04e1557d64ca53d187cd85afc92`
- Bitstream local: 4.045.676 byte
- SHA-256 bitstream:
  `183e0af367376ebd7ca6bc2f3747314fd0602306a630af2a2e51858ef1f20e8e`
- Timing 50 MHz: WNS `+2,226 ns`, TNS `0`, WHS `+0,034 ns`, THS `0`
- Tài nguyên: 49.909/53.200 LUT (`93,81%`), 30.649 register, 25 BRAM, 4 DSP
- Route: 70.739/70.739 routable net hoàn tất, 0 routing error
- DRC: 0 Error/Critical Warning; 4 `DPOP-2`, 32 `LUTLP-2`, 128
  `PDCN-1569`, 1 `ZPS7-1`
- Board: PENDING; artifact RC4 ở root chưa bị thay

Trạng thái đúng là **FPGA RC4 hoàn chỉnh cho nghiên cứu nội bộ; ML-KEM-512 đã
đạt cổng functional và implementation FPGA, đang chờ board regression trước
freeze cuối/ASIC**. Public release vẫn phải dừng ở license gate; production
release còn phải dừng ở qualification PUF và xác minh mật mã/bảo mật.
