# Hồ sơ nguồn gốc source

Ngày kiểm tra: 2026-08-30. Đây là hồ sơ nguồn gốc kỹ thuật, không phải ý kiến pháp lý.

## Chuỗi thành phần

| Thành phần | Nguồn gốc được khai báo | Bằng chứng hiện có | Trạng thái phát hành |
|---|---|---|---|
| RTL Keccak/SHA3 dùng bởi Kyber và KDF | Chủ dự án Đồng Trường Long | Xác nhận của chủ dự án; lịch sử Git cục bộ ghi các file tại lần import dự án | Thuộc dự án; còn phải chọn top-level license và chốt ranh giới từng file |
| RTL Kyber nền của Xing/Li | `xingyf14/CRYSTALS-KYBER`, commit `70aaad3bbf8265e94f68241683b000bf9d4894bb` | Cấu trúc và file NTT/Kyber khớp source đã nhập; README liên kết bài TCHES | Chỉ ghi mục đích học thuật; chưa có license phân phối chuẩn |
| Repo trung gian của Tuấn Đạt | `tuandat081125/Kyber`, commit `0bb04eee36396c3e9b93cf83c835ac07f1d05338` | Repo mà chủ dự án đã clone trước khi sửa | Chưa có license rõ ràng |
| Implementation/đặc tả CRYSTALS-Kyber chính thức | `pq-crystals/kyber` | Repo thuật toán chính thức và thông báo CC0-hoặc-Apache-2.0 | Không tự động cấp quyền cho RTL Xing/Li/Tuấn Đạt |
| RTL tích hợp, firmware, host và test | Code mới và sửa đổi thuộc dự án | Lịch sử dự án cục bộ | Chờ top-level license tương thích |

## Nguồn đã ghi nhận

- Repo RTL gốc đã đối chiếu: `https://github.com/xingyf14/CRYSTALS-KYBER`
- Commit RTL gốc: `70aaad3bbf8265e94f68241683b000bf9d4894bb`
- Bài báo được repo RTL dẫn: `https://tches.iacr.org/index.php/TCHES/article/view/8797/8397`
- Repo Verilog trung gian được clone: `https://github.com/tuandat081125/Kyber.git`
- Commit repo trung gian: `0bb04eee36396c3e9b93cf83c835ac07f1d05338`
- Repo thuật toán/tham chiếu chính thức: `https://github.com/pq-crystals/kyber`
- License upstream chính thức: `https://raw.githubusercontent.com/pq-crystals/kyber/main/LICENSE`

Chủ dự án cho biết repo Tuấn Đạt là nguồn trung gian. Đối chiếu file cho thấy nền
RTL thực tế xuất phát từ thiết kế Xing/Li, sau đó được clone/sửa qua repo Tuấn
Đạt. Cụm từ “academic use” trong README không phải một license phân phối source
và bitstream đầy đủ; chuỗi quyền vẫn phải được xác nhận bằng văn bản.

## Ranh giới file Keccak tạm thời

Chủ dự án xác định phần Keccak trong Kyber là code thuộc dự án. Các file dưới đây
là ứng viên kỹ thuật hiện tại và phải xác nhận từng file trước khi thêm copyright header:

- `rtl/hash_core/*`
- `rtl/common/keccak_pkg.sv`
- `rtl/kyber/ref/keccak_f1600_client.v`
- `rtl/kyber/ref/keccak_f1600_server.v`
- `rtl/kyber/ref/sha3_shake_core.v`
- `rtl/kyber/ref/decode_keccak.v`
- `rtl/top/kdf_keccak.sv`
- `rtl/hash_core/fips202_sponge.sv`

Không thêm tên tác giả hoặc SPDX header trước khi xác minh lịch sử; một commit Git
thể hiện việc import file không tự nó chứng minh quyền tác giả.

Vector byte-oriented trong `sim/fips202/nist_cavp_vectors.txt` là tập con được
trích từ response file CAVP do NIST công bố. URL, ngày CAVS và checksum hai file
zip nguồn được ghi trong file vector; `import_nist_cavp.py` là script dự án dùng
để tái tạo và kiểm tra tập con đó.

## Bằng chứng cần có để phát hành công khai

1. Xing/Li và Tuấn Đạt thêm license rõ ràng hoặc cung cấp xác nhận có ngày cho
   phép sửa đổi và phân phối RTL ở cả dạng source lẫn FPGA bitstream.
2. Lưu mapping theo file giữa commit Xing/Li, repo trung gian và bản dự án.
3. Chủ dự án xác nhận danh sách file Keccak và nêu rõ mọi source, bảng hoặc đoạn
   code Keccak của bên thứ ba đã dùng.
4. Lưu quyền thu được tại `LICENSES/KYBER-PERMISSION.txt` cùng thông báo
   Apache-2.0/CC0 cần thiết.
5. Chọn top-level license tương thích với source RO-PUF chịu GPL và nghĩa vụ của
   mọi thành phần khác.

Cho đến khi hoàn thành các mục này, chỉ chia sẻ các internal RC trong repo riêng
tư của nhóm; không public source hoặc bitstream ML-KEM.
