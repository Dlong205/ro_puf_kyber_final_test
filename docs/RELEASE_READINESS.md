# Mức độ sẵn sàng phát hành — 0.1.0-rc2

Đích: XC7Z020-2CLG400I, chỉ PL, clock ngoài 50 MHz, không có Xilinx IP sinh tự
động. Tài liệu này phân biệt ứng viên kỹ thuật nội bộ với sản phẩm mật mã production.

## Các cổng kỹ thuật RC

| Cổng kiểm tra | Trạng thái |
|---|---|
| Cây source độc lập, không liên kết workspace cũ | PASS |
| Pure RTL, không XCI/Xilinx IP sinh tự động | PASS |
| Firmware release build với warning là lỗi | PASS |
| Regression controller RO-PUF | PASS |
| Regression sửa lỗi/từ chối BCH | PASS |
| FIPS 202 SHAKE256 KAT một vector cố định | PASS |
| Loopback server/client Kyber-512 cũ | PASS |
| Regression AXI start/restart/key-match/zeroize/retry | PASS |
| Mô phỏng full-pipeline firmware/UART | PASS |
| Tắt xuất shared secret trong firmware mặc định | PASS |
| Loại bỏ LED phụ thuộc secret | PASS |
| Firmware wait và Kyber retry có giới hạn | PASS |
| Synthesis/place/route/timing/DRC mới | PASS, WNS +4.108 ns, WHS +0.048 ns, 0 lỗi DRC |
| INFO/nạp board RC2 | PASS |
| Stress board RC2 | PASS, 1.000/1.000 và 10.000/10.000 |
| Danh mục license thành phần | PASS |
| Quyền phân phối công khai | BỊ CHẶN, xem `NOTICE.md` |

## RC2 chứng minh được gì

RC2 chứng minh stack RTL/firmware/host độc lập có thể build, đạt timing và hoàn
thành 10.000 giao dịch full-pipeline liên tiếp trên board chỉ định trong cùng một
lần cấp nguồn. Giao thức serial mặc định trả success hoặc mã lỗi theo giai đoạn,
không trả shared secret. Seed và trạng thái core được reset sau mỗi giao dịch logic.

Kyber core cũ được nhập có raw key mismatch phụ thuộc vector và hiếm khi bị treo.
Firmware zeroize rồi retry với `m` mới đã diversify cho cả hai trường hợp, tối đa
16 lần. Stress phần cứng xác nhận wrapper availability logic; không chứng minh
raw attempt luôn không lỗi. RC2 hiện không xuất telemetry số lần retry.

SHAKE256 KDF có test tham chiếu FIPS 202 khớp từng bit. Test Kyber chỉ chứng minh
hai endpoint RTL nhập vào tạo cùng kết quả. Nó không phải NIST algorithm KAT chính
thức và thiết kế phải được gọi là Kyber-512 cũ/thử nghiệm, không phải FIPS 203
ML-KEM-512.

## Các mục NO-GO trước production

1. Thu thập và lưu quyền phân phối Kyber RTL rõ ràng.
2. Chọn top-level license tương thích cho file thuộc dự án.
3. Thay diversify theo cycle counter bằng nguồn entropy đã đặc trưng và DRBG đã review.
4. Thay hoặc xác minh độc lập core cũ với FIPS 203 ML-KEM có phiên bản và vector chính thức.
5. Sửa lỗi raw Kyber mismatch/stall thay vì phụ thuộc retry.
6. Qualification PUF qua nhiều power-cycle vật lý, góc nguồn, góc nhiệt độ và
   nhiều thiết bị; ghi failure rate, uniqueness và Hamming distance trong/giữa thiết bị.
7. Review side-channel, fault-injection, vòng đời secret và constant-time.
8. Bổ sung xác minh độc lập và môi trường CI/build tái lập được.

Cho đến khi hoàn thành, nhãn đúng là **ứng viên nghiên cứu/đánh giá kỹ thuật nội
bộ**, không phải hardware bảo mật production.

## Định danh implementation RC2

- Bitstream: `Kyber_System_Top.bit`, 4.045.676 byte
- SHA-256: `e85e3f2bd0206485aa636b56b9256aae9a38255ab29179f6fb20e37d6b4abdfb`
- Timing sau route: WNS `+4.108 ns`, TNS `0 ns`, WHS `+0.048 ns`, THS `0 ns`
- Tài nguyên sau route: 51.774/53.200 Slice LUT (`97,32%`), 23,5 BRAM tile và 4 DSP
- DRC sau route: 0 lỗi; 4 `DPOP-2`, 32 `LUTLP-2` có chủ ý, 128 `PDCN-1569`
  riêng cho RO và một warning `ZPS7-1` dự kiến vì thiết kế chỉ PL
- Giao thức: 1.1, INFO `4B 50 01 01 0E`
- Bằng chứng board: `HARDWARE_TEST_REPORT_RC2_2026-08-30.md`
