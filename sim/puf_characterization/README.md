# Kiểm thử UART đo RO-PUF

Chạy nhẹ, một luồng:

```sh
make -C sim/puf_characterization -j1
make -C sim/puf_characterization -j1 CLKS_PER_BIT=434
```

Bài kiểm tra điều khiển và giải mã UART 8N1 trực tiếp bằng C++, không dùng lại
`uart_rx` của RTL làm bộ tham chiếu. Giảm `CLKS_PER_BIT` xuống 16 để rút ngắn
mô phỏng; dòng thứ hai kiểm tra đúng thông số 434 của FPGA. Bộ đếm timeout
24-bit vẫn chạy đủ 2^24 chu kỳ trong cả hai cấu hình.

Các trường hợp được kiểm tra:

- INFO trả đúng sáu byte `50 55 46 01 00 01`, kể cả khi gọi lặp lại.
- RAW trả đúng `AA` và 33 byte từ bit thấp đến cao; bao phủ mọi giá trị byte
  từ `00` đến `FF`, thêm mẫu toàn `00`, `FF`, `AA`.
- Dữ liệu phản hồi được chốt tại `puf_done`, không thay đổi theo bus đầu vào
  trong lúc truyền; `puf_start` chỉ dài một chu kỳ.
- Lệnh sai trả đúng một byte `3F`, các lệnh tiếp theo vẫn hoạt động.
- PUF không trả `done`: timeout thật, chỉ trả một byte `FF`, sau đó hồi phục.
- Reset trong khi chờ PUF và trong khi truyền RAW, sau đó chạy lại INFO/RAW.

Đây là kiểm tra giao thức và điều khiển endpoint UART. Nó không mô phỏng độ
nhiễu, độ ổn định, entropy của RO-PUF hay chứng minh bố trí vật lý trên board.
