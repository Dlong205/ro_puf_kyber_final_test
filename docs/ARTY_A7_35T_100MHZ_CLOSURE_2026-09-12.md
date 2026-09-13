# Kết quả timing 100 MHz — full Edge core trên Arty A7-35T

## Kết luận

Full `edge_puf_mlkem_core` đã đạt timing OOC ở 100 MHz trên part
`xc7a35ticsg324-1L`. Đây là bằng chứng core fit và đóng timing; chưa phải
bitstream board. Phép thử board top/UART ngày 2026-09-13 đã xác nhận NO-FIT;
xem [báo cáo dung lượng board top](ARTY_A7_35T_BOARD_TOP_CAPACITY_2026-09-13.md).

## Kết quả cuối

| Chỉ tiêu | Kết quả |
|---|---:|
| Clock period | 10,000 ns |
| Setup slack (WNS) | +0,092 ns |
| Total negative slack | 0,000 ns |
| Hold slack | +0,053 ns |
| LUT logic | 19.166 / 20.800 (92,14%) |
| Register | 19.403 / 41.600 (46,64%) |
| BRAM tile | 14 / 50 (28,00%) |
| DSP | 2 / 90 (2,22%) |
| Unrouted / partially routed | 0 / 0 |

Candidate `state10pulse_v05` đầu tiên đóng timing ở WNS +0,072 ns nhưng còn
40 warning reset bất đồng bộ lái chân địa chỉ/enable BRAM. Candidate cuối
`syncscrub_v06` đổi riêng state/address scrub sang reset đồng bộ, loại toàn bộ
`REQP-1839/1840`, giảm 91 LUT và đóng timing ở WNS +0,092 ns.

## Bổ sung 2026-09-13: khóa vật lý RO-PUF

Candidate `kdfwidece_puflock_v08` áp dụng khóa placement cho toàn bộ 1.166
primitive của `u_puf`, LOCK_PINS cho 136 endpoint và FIXED_ROUTE cho 128 net
RO. Sau khi tách các bank `lane_b` và `seed_out` của KDF thành process riêng
với enable fanout có giới hạn, bản khóa vật lý đã route 100% và đạt:

| Chỉ tiêu | v08 khóa RO |
|---|---:|
| Setup slack (WNS) | +0,053 ns |
| Hold slack (WHS) | +0,046 ns |
| LUT logic | 19.935 / 20.800 (95,84%) |
| Slice LUT tổng | 20.126 / 20.800 (96,76%) |
| Register | 19.398 / 41.600 (46,63%) |
| Unrouted / partially routed / routing error | 0 / 0 / 0 |

Validator độc lập xác nhận 136 endpoint và 128 route đều cố định; fingerprint
v08 khớp byte-for-byte baseline. Regression KDF KAT/zeroize, Edge controller,
scrub và ML-KEM valid/invalid đều PASS sau thay đổi RTL. Bộ bằng chứng nằm tại
[`../reports/fpga_100mhz_arty35t_puflock_2026-09-13/`](../reports/fpga_100mhz_arty35t_puflock_2026-09-13/).

## Thay đổi RTL tạo closure

- Thay decode toàn bộ `next_state` của `squeeze_init_early` bằng bốn cung vào
  state capture cục bộ.
- Tạo `keccak_init_pulse` state 10 trực tiếp từ `state` và `pad_ctr`, tránh kéo
  feedback FIFO/NTT của toàn FSM vào control cone có fanout lớn.
- Giữ `core_reset` fail-safe bất đồng bộ, nhưng reset state/address của scrub
  controller đồng bộ để BRAM được suy luận và điều khiển đúng mẫu phần cứng.
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

- Đã bổ sung board top/pinout/UART chẩn đoán ngày 2026-09-13, nhưng synthesis
  xác nhận NO-FIT (26.815/20.800 Slice LUT); vì vậy không tạo/nạp bitstream
  full Edge sai điều kiện lên Arty-35T.
- Chưa có timing sign-off với package I/O delay thực tế.
- Placement/routing RO đã được khóa và audit trong full Edge OOC. Vẫn cần board
  top và đúng image khóa RO để kiểm tra power-cycle/PVT/count-margin/nhiều board;
  timing closure của logic đồng bộ không thay thế qualification vật lý của PUF.
- DRC không có error và còn 166 warning: 160 warning gắn với cấu trúc RO-PUF
  có chủ đích (32 `LUTLP-2`, 128 `PDCN-1569`) và 6 warning tối ưu vật lý/DSP
  (2 `DPOP-2`, 2 `PDRC-153`, 2 `PLHOLDVIO-2`). Không còn warning
  `REQP-1839/1840`.
- JTAG/UART đã được nhận lại và ảnh PUF-only đã được nạp/test. Board top/UART
  full Edge đã được viết và unit-test, nhưng không fit A7-35T nên không có
  image tích hợp để nạp.

Các báo cáo cuối nằm trong
`reports/fpga_100mhz_arty35t_syncscrub_2026-09-12/`; thư mục không có hậu tố
`syncscrub` được giữ làm lịch sử candidate v05.
