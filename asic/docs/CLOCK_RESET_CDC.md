# Clock, reset, CDC/RDC inventory

Trạng thái: front-end inventory; chưa chạy CDC/RDC sign-off tool.

## Clock domains

| Domain | Nguồn | Có thể dừng | Mục đích |
|---|---|---:|---|
| `clk_sys` | `clk_i` | Không trong functional mode | CPU, UART, FE, KDF, ML-KEM và control PUF |
| `ro_clk0` | RO được mux từ bank 0 | Có | counter PUF 0 |
| `ro_clk1` | RO được mux từ bank 1 | Có | counter PUF 1 |

`clk_sys` dùng constraint khởi đầu 20 ns. Tần số/pha clock RO phụ thuộc macro,
PVT và mismatch; phải có methodology riêng, không khai báo bừa generated clock
chỉ để loại warning.

## Reset tree

- `rst_ni`: external active-low reset, cho phép assert bất đồng bộ.
- `u_reset_sync.release_ff[1:0]`: đồng bộ release vào `clk_sys` trong module
  `reset_sync_n` (async assert, two-cycle synchronous release).
- `rst_sys_n`: reset nội bộ tới SoC/PUF/FE/KDF.
- Mỗi counter RO tạo `local_arst_n = rst_sys_n & ~cnt_rst`, assert bất đồng bộ
  và release qua hai flop bằng chính clock RO.

ASIC reset/pad cell, minimum pulse width, recovery/removal và test override còn
phụ thuộc library. Không blanket false-path reset trước khi review.

## Crossing hiện có

| Crossing | Cơ chế hiện tại | Trạng thái |
|---|---|---|
| `count_en`: sys → RO | hai flop trong từng counter | cần CDC constraint/review cell mapping |
| counter comparator/winner: RO → sys | tắt RO, chờ settle, comparator ổn định, hai flop winner | cần formal/protocol assertion và CDC waiver theo object |
| `cnt_rst`: sys → RO | async assert + sync release cục bộ | cần RDC review |
| challenge/mux select: sys → RO path | chỉ đổi khi RO off; assertion simulation | cần giữ invariant sau synthesis/DFT |

## Cổng phải đóng

- Liệt kê mọi clock/reset sau macro/pad/test integration.
- Chạy CDC/RDC tool hoặc review structural có báo cáo object-level.
- Không còn crossing data nhiều bit không có handshake/stability contract.
- Test reset giữa IDLE/PUF/FE/KDF/KEM, reset khi RO đang bật và clock RO không
  khởi động; hệ thống phải trở về trạng thái xác định.
- SDC functional/test phải có clock groups/exceptions được review từng đường.
