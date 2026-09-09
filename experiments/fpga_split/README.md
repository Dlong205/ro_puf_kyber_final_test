# FPGA-1: đo tài nguyên từng khối trên Arty A7-35T

Thư mục này chỉ cung cấp thí nghiệm synthesis OOC cho RTL hiện tại. Chưa có
top hai board, giao tiếp SPI, firmware mới hoặc bitstream Arty.

Các profile: `client` = `Kyber_Client` Encaps; `server` = `Kyber_Server`
KeyGen/Decaps; `edgecore` = KDF + direct seed + scrub controller + Server;
`kdf` = `kdf_keccak`; `fe` = `fuzzy_extractor`; `puf` =
`kp_puf_top` dùng 128 LUT RO Xilinx; `seedctl` = KDF cùng controller đường
seed nội bộ thử nghiệm. Client/Server cố định `k=2`; các input
scrub và toàn bộ output, kể cả K/key/seed/response, được giữ ở biên OOC để
tránh phép đo nhỏ giả tạo do synthesis xóa logic không quan sát được. Các
cổng rộng này phục vụ phép đo, không phải đề xuất đưa secret ra chân board.

Chạy từ root repo, từng lệnh một:

```bash
FPGA_SPLIT_MEMORY_GIB=4 VIVADO=/media/donglong/tools/Xilinx/Vivado/2020.1/bin/vivado \
  bash experiments/fpga_split/run_ooc.sh client arty35t_probe_01
```

Thay `client` bằng `server`, `edgecore`, `kdf`, `seedctl`, `fe`, `puf` để đo
tiếp. Cùng `run-id`
được dùng cho các block khác nhau; mỗi block chỉ được tạo một lần. Mặc định
target `xc7a35ticsg324-1L`, clock tham chiếu 50 MHz, Vivado một thread,
20 phút/block, memory cap 8 GiB. Launcher khóa một worker cho thí nghiệm;
người chạy cần bảo đảm không có build nặng khác của repo chạy đồng thời.
Không có vòng lặp tự động build tất cả.

Lệnh mẫu chủ động hạ cap xuống **4 GiB** cho máy hiện tại. Không tăng giới
hạn để retry tự động khi OOM. Dùng mức 4 GiB cho các lượt tiếp theo trên máy
này và đóng các build nặng khác trước khi chạy.

Có thể chọn `FPGA_SPLIT_PART`, `FPGA_SPLIT_TIMEOUT`, `FPGA_SPLIT_MEMORY_GIB`
tường minh. Script kiểm tra part đúng với thiết bị đã cài. Nếu host hỗ trợ
systemd user session, tiến trình dùng cgroup giới hạn cả cây process ở
100% một CPU, MemoryMax và không swap. Fallback dùng một CPU và giới hạn
virtual memory; khi Vivado không khởi động được trong giới hạn đó, script
dừng. Không tự chạy lại mà bỏ giới hạn.

Kết quả ở `build/fpga_split/<run-id>/<block>/`: log, manifest SHA-256 source
và header, commit/worktree status, utilization phẳng/phân cấp, timing sơ bộ,
check_timing, synthesized DCP. Chỉ có file `COMPLETE` sau khi synthesis và
các kiểm tra blackbox/output hoàn thành; launcher còn xác nhận source không
đổi trong lúc chạy. Xem `console.log` khi lệnh thất bại.

Không được suy ra "nạp được trên Arty" từ OOC PASS. Cần xem tài nguyên,
thêm bộ nhớ/control/giao tiếp thực, chạy synthesis/P&R full top và kiểm tra
timing/pin/board. Không cộng máy móc các số đo OOC vì mỗi top có ranh giới
quan sát/khả năng tối ưu khác khi tích hợp. Timing sau synthesis chỉ là
tham khảo, chưa bao gồm route thật và thiếu IO constraints. PUF profile
không dùng placement/route-lock của Zynq; Arty cần enrollment và kiểm tra
PUF riêng sau khi placement/routing của chính Arty đã được chốt.

Xuất report đã hoàn tất sang thư mục mới (không copy DCP/log Vivado):

```bash
python3 experiments/fpga_split/summarize.py \
  build/fpga_split/arty35t_probe_20260909 reports/fpga_split_2026-09-09/completed
```

Exporter kiểm source chưa đổi, lưu report gốc và summary JSON cùng checksum.
Nếu source/tool đã sửa sau run, không chỉnh manifest để ép PASS; đo lại run
mới hoặc giữ bộ report đã xuất trước khi thay đổi.
Xem [báo cáo đo và giới hạn](../../docs/FPGA_SPLIT_RESOURCE_BASELINE_2026-09-09.md)
và [snapshot baseline v4](../../docs/FPGA_V4_BASELINE_GUIDE.md).
