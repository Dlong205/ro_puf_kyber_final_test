# Kết quả kiểm tra endpoint UART — 05/09/2026

Hai cấu hình đều PASS với Verilator 5.050; build và chạy một luồng.

| Cấu hình | Chu kỳ đã mô phỏng | Kết quả |
|---|---:|---|
| `CLKS_PER_BIT=16` | 16.884.222 | ALL PASS |
| `CLKS_PER_BIT=434` (thông số FPGA) | 19.609.582 | ALL PASS |

Kết quả chung của mỗi lần chạy:

```text
PASS INFO exact 6 bytes, repeated
PASS RAW status+33 bytes, all 256 byte values, response latch, 11 repeated requests
PASS invalid commands return exactly '?', then recover
PASS full 2^24-clock timeout, one failure byte, INFO/RAW recovery
PASS reset while waiting for PUF, INFO/RAW recovery
PASS reset during RAW transmission, INFO/RAW recovery
```

Payload dùng dữ liệu tổng hợp trong testbench, không chứa mẫu RO-PUF thực.
Kết quả xác nhận giao thức UART và cơ chế chốt dữ liệu khi `puf_done`; cần đo
trên board để kết luận độ ổn định của RO-PUF.
