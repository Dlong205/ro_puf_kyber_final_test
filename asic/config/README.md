# Cấu hình công nghệ

Repository không chứa PDK hoặc library có hạn chế phân phối. File
`technology.env.example` chỉ liệt kê tên biến mà cổng readiness cần; không
source trực tiếp file mẫu vì các đường dẫn đều là placeholder.

Sau khi được cấp PDK, export các biến bằng đường dẫn tuyệt đối trong shell riêng
rồi chạy:

```sh
make -j1 asic-backend-readiness
```

Cổng này chỉ xác nhận input/tool có mặt. Nó không chứng minh version/corner đã
đúng; checksum và license phải được ghi trong biên bản handoff riêng tư.
