# Trạng thái bảo mật

`0.2.0-rc1` là ứng viên nghiên cứu/đánh giá FPGA. Đường thuật toán ML-KEM-512
đã PASS cổng functional bit-exact nội bộ nhưng thiết kế không tuyên bố có chứng
nhận FIPS 203, FIPS 140-3, Common Criteria, constant-time hay khả năng chống
side-channel/fault-injection.

Firmware mặc định dùng `RELEASE_BUILD=1`: chỉ trả match/fail, không xuất shared
secret qua UART, và zeroize seed/status/key Kyber sau mỗi giao dịch. Bản chẩn
đoán `RELEASE_BUILD=0` cố ý có thể xuất khóa và không được dùng làm artifact
release.

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

Các khoảng trống trước production:

1. Đặc trưng PUF trên nhiều board và nhiều power-cycle ở các góc điện áp/nhiệt độ.
2. Đo entropy, reliability, intra/inter-device Hamming distance và aging.
3. Mở rộng corpus ML-KEM ngoài sample ACVP và hoàn tất review mật mã độc lập.
4. Phân tích constant-time, side-channel, fault-injection và vòng đời secret.
5. Formal/property verification cho FIFO, FSM và các điều kiện liveness.
6. Giải quyết quyền phân phối và top-level license trước public release.
