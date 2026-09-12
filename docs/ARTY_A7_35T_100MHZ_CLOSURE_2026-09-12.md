# Kết quả timing 100 MHz — full Edge core trên Arty A7-35T

## Kết luận

Full `edge_puf_mlkem_core` đã đạt timing OOC ở 100 MHz trên part
`xc7a35ticsg324-1L`. Đây là bằng chứng core fit và đóng timing; chưa phải
bitstream board vì top OOC chưa gán chân I/O/UART của Arty.

## Kết quả cuối

| Chỉ tiêu | Kết quả |
|---|---:|
| Clock period | 10,000 ns |
| Setup slack (WNS) | +0,072 ns |
| Total negative slack | 0,000 ns |
| Hold slack | +0,058 ns |
| LUT logic | 19.257 / 20.800 (92,58%) |
| BRAM tile | 14 / 50 (28,00%) |
| DSP | 2 / 90 (2,22%) |
| Unrouted / partially routed | 0 / 0 |

Route đầu của candidate `state10pulse_v05` đạt legality nhưng còn WNS
-0,177 ns. Post-route `AggressiveExplore` tối ưu ba net critical và đưa WNS
lên +0,072 ns mà không thêm cell, sau đó incremental route giữ nguyên timing.

## Thay đổi RTL tạo closure

- Thay decode toàn bộ `next_state` của `squeeze_init_early` bằng bốn cung vào
  state capture cục bộ.
- Tạo `keccak_init_pulse` state 10 trực tiếp từ `state` và `pad_ctr`, tránh kéo
  feedback FIFO/NTT của toàn FSM vào control cone có fanout lớn.
- Giữ nguyên clear 1600-bit của sponge. Thử bỏ clear làm LUT tăng lên 26.802
  (128,86%) nên đã bị loại và không nằm trong RTL cuối.

## Regression chức năng sau thay đổi

- FIPS 202: 50/50 PASS.
- KDF KAT và secure zeroize: PASS.
- ML-KEM-512 NIST ACVP: KeyGen 25/25, Encaps 25/25, Decaps valid 25/25 và
  implicit rejection 175/175 PASS bit-exact.
- Edge integration: valid và invalid ciphertext PASS; latency không đổi
  19.800 chu kỳ; shared-key secret và zeroize PASS.

## Phạm vi chưa được chứng minh

- Chưa tạo/nạp bitstream full Edge cho Arty vì chưa có board top và pinout.
- Chưa có timing sign-off với package I/O delay thực tế.
- RO-PUF cần khóa placement/routing và kiểm tra lại nhiều build/PVT; timing
  closure của logic đồng bộ không thay thế qualification vật lý của PUF.
- DRC không có error nhưng còn 208 warning: 160 warning gắn với cấu trúc RO-PUF
  có chủ đích (32 `LUTLP-2`, 128 `PDCN-1569`), 40 warning `REQP-1839/1840`
  do reset bất đồng bộ của scrub controller lái địa chỉ BRAM, và 8 warning tối
  ưu vật lý/DSP. Nhóm REQP phải được xử lý trước board-release bitstream.
- Trong phiên đo, máy host không nhận diện USB Digilent/FTDI của board nên
  chưa thể chạy JTAG/UART hardware test.

Các báo cáo trích xuất nằm trong `reports/fpga_100mhz_arty35t_2026-09-12/`.
