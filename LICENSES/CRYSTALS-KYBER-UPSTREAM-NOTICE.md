# Bản ghi nguồn và license Kyber upstream

## RTL Xing/Li được dùng làm nền

- Repo: `https://github.com/xingyf14/CRYSTALS-KYBER`
- Commit đã đối chiếu: `70aaad3bbf8265e94f68241683b000bf9d4894bb`
- Bài báo: `https://tches.iacr.org/index.php/TCHES/article/view/8797/8397`
- Ngày kiểm tra: 2026-08-30

README của repo này nêu mục đích sử dụng học thuật nhưng không kèm một license
phần mềm chuẩn quy định đầy đủ quyền sửa đổi/phân phối source và bitstream. Bản
ghi này không thay thế `KYBER-PERMISSION.txt`.

## Implementation thuật toán chính thức

- Repo chính thức: `https://github.com/pq-crystals/kyber`
- Nguồn license: `https://raw.githubusercontent.com/pq-crystals/kyber/main/LICENSE`
- Ngày kiểm tra lại: 2026-08-30

Repo chính thức nêu rằng implementation được cung cấp theo tuyên bố public-domain
CC0 hoặc, theo lựa chọn khác, Apache License 2.0. Repo cũng nêu code Keccak và AES
của họ là code public domain, với nguồn và tác giả ghi trong comment đầu file.

Bản ghi CC0/Apache mô tả upstream C/assembly chính thức. Nó không khẳng định RTL
Verilog Xing/Li hoặc bản trung gian `tuandat081125/Kyber` tự động chịu các điều
khoản đó.
