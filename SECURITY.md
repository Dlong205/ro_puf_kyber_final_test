# Trạng thái bảo mật

`0.1.0-rc3` là ứng viên nghiên cứu/đánh giá FPGA. Thiết kế không tuyên bố đạt
FIPS 203, FIPS 140-3, Common Criteria, constant-time hay khả năng chống
side-channel/fault-injection.

Firmware mặc định dùng `RELEASE_BUILD=1`: chỉ trả match/fail, không xuất shared
secret qua UART, và zeroize seed/status/key Kyber sau mỗi giao dịch. Bản chẩn
đoán `RELEASE_BUILD=0` cố ý có thể xuất khóa và không được dùng làm artifact
release.

Mỗi lần boot, message seed được diversify từ KDF output của PUF, session counter
và cycle counter RISC-V. Cơ chế này tránh lặp input đơn giản trong một boot,
nhưng không phải TRNG đã đặc trưng hay DRBG được phê duyệt. Sản phẩm thực tế cần
nguồn entropy và thiết kế sinh số ngẫu nhiên được xác minh độc lập.

RC3 đã bỏ hoàn toàn retry Kyber. Các lỗi FIFO starvation/underfill của NTT/SHAKE
được sửa ở RTL và được kiểm tra bằng 1.024 giao dịch raw single-attempt trong mô
phỏng cùng 10.000 giao dịch end-to-end trên board, đều không lỗi. Kết quả này làm
tăng độ tin cậy chức năng nhưng không chứng minh mọi input, không phải formal
verification và không biến core Kyber cũ thành FIPS 203 ML-KEM-512.

Helper data RO-PUF là dữ liệu công khai nhưng gắn với board/lần enroll. Không
commit các file như `helper.bin`, `hardware_helper.bin` hoặc bản helper dùng khi
bring-up.

Các khoảng trống trước production:

1. Đặc trưng PUF trên nhiều board và nhiều power-cycle ở các góc điện áp/nhiệt độ.
2. Đo entropy, reliability, intra/inter-device Hamming distance và aging.
3. Đối chiếu ML-KEM-512 KAT chính thức hoặc thay core bằng implementation được review.
4. Phân tích constant-time, side-channel, fault-injection và vòng đời secret.
5. Formal/property verification cho FIFO, FSM và các điều kiện liveness.
6. Giải quyết quyền phân phối và top-level license trước public release.
