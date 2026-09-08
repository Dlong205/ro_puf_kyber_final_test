# Trạng thái bảo mật

`0.2.0-rc1` là artifact nghiên cứu/đánh giá FPGA đã được chấp nhận; nhánh tích
hợp hiện là `0.2.0-rc2-dev`. Đường thuật toán ML-KEM-512
đã PASS cổng functional bit-exact nội bộ nhưng thiết kế không tuyên bố có chứng
nhận FIPS 203, FIPS 140-3, Common Criteria, constant-time hay khả năng chống
side-channel/fault-injection.

Firmware mặc định dùng `RELEASE_BUILD=1`: chỉ trả match/fail, không xuất shared
secret qua UART. Candidate v4/protocol 1.3 đợi một handshake
crypto-accelerator zeroize trước khi trả thành công hoặc lỗi sau khi đã tạo dữ
liệu bí mật. Boundary này xóa trạng thái PUF, FE, KDF và ML-KEM, gồm quét sâu
RAM/FIFO/sponge theo các test RTL. Bản chẩn đoán `RELEASE_BUILD=0` cố ý có thể
xuất khóa và không được dùng làm artifact release.

Sau banner khởi động, firmware v4 bắt buộc đợi accelerator zeroize trước khi
vào command dispatcher. Nếu handshake timeout, thiết bị trả `FF 09` và không
nhận lệnh tiếp theo trong boot đó. Đây là fail-closed ở boundary accelerator,
không mở rộng boundary thành CPU/SoC erase.

“Crypto-accelerator zeroize” không có nghĩa whole-SoC secure erase. PicoRV32
register/pipeline, firmware stack và SoC BRAM, bus/peripheral staging, JTAG,
scan/DFT, memory remanence và các bản sao sau synthesis nằm ngoài boundary đã
chứng minh. CPU/firmware/bus master nội bộ hiện thuộc trusted computing base.
Nếu threat model cho phép attacker đọc các miền này, zeroize toàn SoC là một
yêu cầu kiến trúc bổ sung, không phải waiver tài liệu.

Mỗi lần boot, message seed được diversify từ KDF output của PUF, session counter
và cycle counter RISC-V. Cơ chế này tránh lặp input đơn giản trong một boot,
nhưng không phải TRNG đã đặc trưng hay DRBG được phê duyệt. Sản phẩm thực tế cần
nguồn entropy và thiết kế sinh số ngẫu nhiên được xác minh độc lập.

RC3 đã bỏ hoàn toàn retry Kyber; RC4 tách các backend phụ thuộc FPGA để chuẩn bị
cho ASIC. RC1 ML-KEM bổ sung KeyGen/Encaps/Decaps và implicit rejection theo
FIPS 203, đối chiếu bit-exact bằng vector/oracle độc lập. Các lỗi FIFO
starvation/underfill của NTT/SHAKE được sửa ở RTL và được kiểm tra bằng 1.024
giao dịch raw single-attempt trong mô phỏng cùng 10.000 giao dịch end-to-end
trên board, đều không lỗi. Kết quả này làm tăng độ tin cậy chức năng nhưng không
chứng minh mọi input và không phải formal verification hay chứng nhận FIPS.

Helper data RO-PUF là dữ liệu công khai nhưng gắn với board/lần enroll. Không
commit các file như `helper.bin`, `hardware_helper.bin` hoặc bản helper dùng khi
bring-up.

Miền RO của full-SoC hiện đã được khóa và kiểm tra bằng fingerprint vật lý
(136 endpoint, 128 route) qua hai build sạch. Đây chỉ là kiểm soát tái lập
implementation. Campaign PUF-only 10.000 mẫu trên một board có HD tối đa 1,
nhưng chưa tương đương image full-SoC và chưa bao phủ same-root, PVT hay nhiều
board. Với 32 RO vật lý, upper bound cấu trúc theo mô hình thứ tự tần số là
`log2(32!) = 117,663 bit`; không được tuyên bố entropy 192/512 bit từ độ dài
fuzzy-extractor/KDF khi chưa có đánh giá entropy và helper leakage.

Các khoảng trống trước production:

1. Đặc trưng PUF trên nhiều board và nhiều power-cycle ở các góc điện áp/nhiệt độ.
2. Đo entropy, reliability, intra/inter-device Hamming distance và aging.
3. Mở rộng corpus ML-KEM ngoài sample ACVP và hoàn tất review mật mã độc lập.
4. Phân tích constant-time, side-channel, fault-injection, remanence, CPU/bus và
   vòng đời secret; chốt policy debug/scan/DFT.
5. Formal/property verification cho FIFO, FSM và các điều kiện liveness.
6. Giải quyết quyền phân phối và top-level license trước public release.

Candidate v4 đã PASS full offline `crypto-freeze-gate`, gồm source/verification
manifest, regression, ASIC portability và Kyber raw 1.024/1.024 ngày
2026-09-07, nhưng chưa chạy Vivado hay board. Kết quả FIPS 202/ML-KEM bit-exact
là functional verification nội bộ, không phải NIST validation hoặc
certification. Xem `docs/CRYPTO_RTL_FREEZE_CANDIDATE_V4_2026-09-07.md`.
