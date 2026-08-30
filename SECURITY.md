# Trạng thái bảo mật

Ứng viên phát hành này dành cho nghiên cứu FPGA và đánh giá kỹ thuật. Nó không
phải module mật mã cho production và không tuyên bố đạt FIPS, Common Criteria
hoặc khả năng chống side-channel.

Firmware mặc định được build với `RELEASE_BUILD=1`. Nó không xuất Kyber shared
secret qua UART, chỉ báo trạng thái match/fail và yêu cầu zeroize seed Kyber,
sticky status và trạng thái core sau mỗi thao tác. Bản chẩn đoán
`RELEASE_BUILD=0` cố ý xuất khóa và không được phân phối như bitstream release.

Seed message theo session được diversify bằng output KDF từ PUF, counter cục bộ
theo lần boot và cycle counter của RISC-V. Cơ chế này giảm lặp input trong cùng
một lần boot nhưng không phải TRNG đã được đặc trưng hoặc DRBG được phê duyệt.
Production cần nguồn entropy đã xác nhận và thiết kế sinh số ngẫu nhiên đã review.

Kyber core cũ được nhập có raw key mismatch phụ thuộc vector và có thể bị treo.
Giao thức 1.1 dùng wrapper reset/retry tối đa 16 lần để tăng availability ở mức
logic. Cách xử lý này không sửa raw core, không chứng minh FIPS 203 ML-KEM-512
và không thay thế đánh giá mật mã độc lập.

Helper data RO-PUF là dữ liệu công khai nhưng gắn với board/lần enroll. Không
đóng gói file cục bộ như `helper.bin` hoặc `hardware_helper.bin` vào release chung.

Các khoảng trống trước production gồm: đặc trưng PUF trên nhiều board; test góc
điện áp, nhiệt độ và power-cycle; phân tích side-channel/fault-injection;
constant-time; KAT thuật toán chính thức và review mật mã độc lập.
