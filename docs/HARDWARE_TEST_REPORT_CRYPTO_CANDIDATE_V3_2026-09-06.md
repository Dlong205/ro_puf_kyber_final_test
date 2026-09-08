# Báo cáo board regression crypto candidate v3 — 2026-09-06

## Kết luận

Bitstream candidate v3 tại source `1dcdad8ccb8c5acda5b11fcf754b2d686818d718`
đã **PASS nạp JTAG, INFO, enroll, reconstruct và stress 10.000/10.000** trên
board XC7Z020 đang dùng. Shared secret không được xuất ở release mode. Sau
campaign, board đã được nạp lại đúng bitstream RC1 ở root và reconstruct smoke
với helper mới đã PASS.

Kết quả này đóng board-regression cho đúng bitstream v3 đã implementation,
nhưng không tự nâng v3 thành crypto freeze cuối. AI pre-review cùng ngày phát
hiện zeroization sâu của NTT RAM/sponge/FE/KDF chưa được chứng minh; RTL phải
được sửa và mọi gate liên quan phải chạy lại dưới một candidate mới.

## Định danh

- Board/JTAG: `xc7z020_1`, Digilent serial `260515110006`.
- UART: CH340 qua symlink ổn định
  `/dev/serial/by-id/usb-1a86_USB_Serial-if00-port0`, 115.200 baud.
- Candidate bitstream:
  `build/soc_repro/candidate_v3/kyber_ro_puf_candidate_v3.runs/impl_1/Kyber_System_Top.bit`.
- Candidate SHA-256:
  `b9f40dce606bcd429b5a97a123df1169e33c7ceca64ec901392651c60b4fa61e`.
- RC1 root SHA-256:
  `183e0af367376ebd7ca6bc2f3747314fd0602306a630af2a2e51858ef1f20e8e`.
- Giao thức: version 1.2, capability `0x06`.
- Chính sách release: tắt shared-secret export; bật session diversification và
  lệnh Kyber zeroize hiện hành.

Helper của campaign được lưu riêng ngoài repository và không commit. Không có
shared secret, raw response định danh board hoặc helper gắn với board trong báo
cáo này.

## Kết quả

| Bước | Kết quả |
|---|---|
| Nhận đúng một target XC7Z020 | PASS |
| Nạp candidate v3 bằng JTAG volatile PL | PASS |
| INFO protocol 1.2/capability `0x06` | PASS |
| Enroll helper mới | PASS, 33 byte |
| Reconstruct ban đầu | PASS, Server/Client match |
| Stress ngắn | 100/100, fail 0 |
| Stress trung bình | 1.000/1.000, fail 0 |
| Stress dài | 10.000/10.000, fail 0 |
| Latency stress dài | 29,152 ms/giao dịch trung bình |
| Throughput stress dài | 34,302 giao dịch/s |
| Khôi phục đúng RC1 root qua JTAG | PASS |
| INFO sau khôi phục RC1 | PASS |
| Reconstruct RC1 với helper vừa enroll | PASS |

Tổng stress candidate v3 được chạy theo ba campaign riêng. Mỗi lệnh `stress`
enroll lại một helper trước vòng reconstruct; con số chính để chốt campaign là
run dài 10.000/10.000.

## Quan sát về helper và độ ổn định PUF

Helper thu được ở các lần enroll không hoàn toàn giống nhau. Đây là dấu hiệu
response RO-PUF có biến thiên đo được; fuzzy extractor đã sửa được sai khác
trong toàn bộ 10.000 vòng của run dài tại điều kiện phòng hiện tại.

Một helper RC1 cũ lưu ngoài repo đã fail tại bước FE decode với mã `0x04`, còn
helper vừa enroll trên candidate v3 reconstruct thành công sau khi khôi phục
RC1. Vì physical fingerprint của hai image khớp nhau, kết quả phù hợp với giả
thuyết helper cũ bị stale/khác điều kiện; nó không được bỏ qua hoặc ghi đè.

Campaign này chưa chứng minh reliability qua cold boot, power-cycle, điện áp,
nhiệt độ, aging hoặc nhiều board. Các gate đó vẫn nằm trong kế hoạch
qualification RO-PUF.

## Lệnh chính đã dùng

```sh
make -j1 program-bit \
  BITSTREAM="$PWD/build/soc_repro/candidate_v3/kyber_ro_puf_candidate_v3.runs/impl_1/Kyber_System_Top.bit" \
  VIVADO=/media/donglong/tools/Xilinx/Vivado/2020.1/bin/vivado

python3 -u host/uart_host.py --port "$PUF_PORT" info
python3 -u host/uart_host.py --port "$PUF_PORT" --helper "$PRIVATE_HELPER" enroll
python3 -u host/uart_host.py --port "$PUF_PORT" --helper "$PRIVATE_HELPER" reconstruct
python3 -u host/uart_host.py --port "$PUF_PORT" --helper "$PRIVATE_HELPER" stress --count 100
python3 -u host/uart_host.py --port "$PUF_PORT" --helper "$PRIVATE_HELPER" stress --count 1000
python3 -u host/uart_host.py --port "$PUF_PORT" --helper "$PRIVATE_HELPER" stress --count 10000

make -j1 program-bit \
  BITSTREAM="$PWD/Kyber_System_Top.bit" \
  VIVADO=/media/donglong/tools/Xilinx/Vivado/2020.1/bin/vivado
```

`PUF_PORT` và `PRIVATE_HELPER` ở đây là biến minh họa; đường helper riêng không
được đưa vào Git.

## Trạng thái sau campaign

- Board đang chạy RC1, không chạy candidate v3.
- Root `Kyber_System_Top.bit` không bị sửa.
- Candidate v3 không được promote/tag thành artifact mới.
- Bước tiếp theo là tạo candidate v4 cho secure zeroize, chạy lại full
  regression, Vivado impact và board regression nếu netlist FPGA thay đổi.
