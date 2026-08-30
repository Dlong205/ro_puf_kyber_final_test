# Thông báo nguồn gốc và quyền phân phối

Phiên bản ứng viên phát hành: `0.1.0-rc2`.

## Thành phần đã xác định điều khoản

- Dự án RO-PUF nguồn đi kèm GNU GPL phiên bản 3; văn bản được lưu tại
  `LICENSES/GPL-3.0-only.txt`.
- RTL BCH encoder/decoder có Copyright 2014 Russ Dill và BSD-2-Clause; thông báo
  được lưu tại `LICENSES/BSD-2-Clause-BCH.txt`.
- `rtl/soc/picorv32.v` có Copyright 2015 Claire Xenia Wolf và thông báo cấp phép
  kiểu ISC được lưu tại `LICENSES/PicoRV32-ISC.txt`.

## Nguồn gốc Kyber và Keccak

Chủ dự án xác nhận RTL Keccak/SHA3 dùng trong luồng Kyber là code thuộc dự án và
do chủ dự án viết. Phần Kyber cũ không thuộc Keccak được clone từ
`https://github.com/tuandat081125/Kyber.git`, commit nguồn cục bộ
`0bb04eee36396c3e9b93cf83c835ac07f1d05338`; tác giả repo là đồng nghiệp của
dự án và cho biết thiết kế được phát triển với sự tham khảo CRYSTALS-Kyber.

Implementation CRYSTALS-Kyber chính thức tại `https://github.com/pq-crystals/kyber`
được cung cấp theo CC0 hoặc Apache-2.0. License đó không tự động chứng minh quyền
đối với cách thể hiện Verilog độc lập trong repo trung gian. Repo Tuấn Đạt không
có license tại lần kiểm tra lại ngày 2026-08-30. Vì vậy việc phân phối công khai
source và bitstream vẫn bị chặn cho đến khi tác giả RTL thêm license hoặc cung
cấp quyền rõ ràng và lưu tại `LICENSES/KYBER-PERMISSION.txt`.

Xem `docs/PROVENANCE.md` để biết ranh giới thành phần, nguồn và bằng chứng còn
thiếu trước khi phát hành công khai.

Đây là hardware loopback Kyber-512 cũ/thử nghiệm. Regression hiện có chỉ kiểm
tra shared key server/client bằng nhau, không phải NIST ML-KEM-512 KAT chính
thức. Không được gắn nhãn thiết kế là FIPS 203 ML-KEM-512.

## Code thuộc dự án

Chưa chọn top-level license cho RTL tích hợp, firmware, host utility, test và tài
liệu do dự án sở hữu. Chủ sở hữu phải thêm file `LICENSE` tương thích với nghĩa
vụ của mọi thành phần trước khi phát hành công khai.
