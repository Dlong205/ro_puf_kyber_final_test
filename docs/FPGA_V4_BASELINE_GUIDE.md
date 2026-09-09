# Bảo toàn baseline functional FPGA v4

Baseline này phục vụ so sánh thay đổi kiến trúc FPGA split/ASIC. Không phải
tag release mới, chứng nhận FIPS hoặc sign-off bảo mật độc lập. Artifact RC1
ở root không bị thay thế.

Descriptor chuẩn: `manifests/fpga_v4_baseline.json`. Nó khóa source tạo v4
(`5943ceb`), commit hồ sơ kết quả (`73988d6`), bitstream, routed DCP,
firmware, XDC, fingerprint và report bằng SHA-256. Firmware/XDC được lấy từ
Git commit đã chọn, không lấy tùy tiện từ worktree hiện tại. Không đóng gói
helper, secret hay log UART chứa dữ liệu enrollment.

Chạy từ root repo:

```bash
python3 scripts/check_fpga_v4_baseline.py --check
python3 scripts/check_fpga_v4_baseline.py --snapshot build/baselines/fpga_v4_20260909
python3 scripts/check_fpga_v4_baseline.py --check-snapshot build/baselines/fpga_v4_20260909
python3 -m unittest discover -s scripts/tests -p 'test_fpga_v4_baseline.py' -v
```

`--snapshot` chỉ tạo thư mục mới, không ghi đè snapshot có sẵn. Nếu thư mục
đã tồn tại, dùng `--check-snapshot`, không xóa bản cũ để chạy lại. Snapshot
có `source.tar` của đúng commit và manifest riêng. Lệnh kiểm snapshot không
cần Vivado hoặc build gốc, nhưng vẫn cần descriptor tin cậy của repo này.
Không dùng descriptor do người lạ thay thế để chứng minh tính xác thực;
checksum phát hiện hỏng/thay đổi dữ liệu, không phải chữ ký số.

Thư mục `build/` không được Git theo dõi. Khi chia sẻ snapshot trong nhóm,
gửi nguyên thư mục cùng descriptor/script ở commit đã review; giữ tuân thủ
license và quyền phân phối RTL. Không chỉ gửi bitstream v4 kèm firmware hay
XDC lấy từ root RC1. Tool này không kiểm soát được file sau khi người dùng
chủ động sửa; luôn kiểm lại hash trước khi sử dụng.

Việc dựng lại source có thể tạo byte bitstream khác do metadata/tool run.
Hash snapshot xác nhận đúng artifact đã kiểm thử; tái build cần chạy lại
regression, timing, route fingerprint và board gate, không chỉ so hash bit.
