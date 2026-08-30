# Giao thức UART v1.2

UART dùng 115200 baud, 8 bit dữ liệu, không parity, một stop bit. Các word helper
nhiều byte và word key chẩn đoán dùng little-endian. Sau reset, thiết bị gửi banner
ASCII `START` đúng một lần rồi nhận command một byte.

## Trạng thái và lỗi chung

- `AA`: thành công.
- `FF <code>`: thất bại.
- `?`: command không xác định.

| Mã lỗi | Ý nghĩa |
|---:|---|
| `01` | Timeout nhận UART |
| `02` | Timeout PUF |
| `03` | Timeout fuzzy extractor |
| `04` | Fuzzy extractor decode thất bại |
| `05` | Timeout KDF |
| `06` | Lỗi cấu hình Kyber |
| `07` | Timeout Kyber |
| `08` | Key server/client không khớp |

## `00` — INFO

Response: `4B 50 <major> <minor> <capabilities>` (`KP`, phiên bản, cờ tính năng).

Capability bit 0 là xuất key chẩn đoán, bit 1 là diversify theo session và bit 2
là Kyber zeroize. Bit 3 từng biểu thị retry trong v1.1 nhưng đã bỏ ở v1.2 sau khi
sửa lỗi raw NTT. Response release v1.2 là `4B 50 01 02 06`.

## `01` — ENROLL

Khi thành công, response là `AA` theo sau đúng 33 byte helper data công khai. Khi
thất bại, response là `FF <code>` và không có helper data theo sau.

## `02` — RECONSTRUCT/KEM

1. Thiết bị gửi `X`.
2. Host gửi tám helper word, mỗi word 4 byte. Thiết bị ACK từng word bằng ASCII
   từ `0` đến `7`.
3. Host gửi byte helper cuối. Thiết bị ACK bằng ASCII `8`.
4. Thiết bị gửi marker tiến độ `ABCDEFG` khi các giai đoạn PUF, BCH, KDF và Kyber
   tiến triển. Kyber chỉ chạy đúng một attempt. Khi timeout hoặc key mismatch,
   marker tiếp theo được thay bằng `FF <code>` và core được zeroize.
5. Thành công trả `AA <result-flags>`. Firmware release trả flag `00` và không có
   key. Firmware chẩn đoán có thể trả flag `01` rồi 32 byte key.

Sau thành công hoặc bất kỳ lỗi giai đoạn Kyber nào, firmware yêu cầu zeroize core,
seed và status Kyber. Ứng dụng host nên dùng `host/uart_host.py` thay vì tự triển
khai byte handshake này.

Việc bỏ retry làm mọi lỗi raw trở thành lỗi giao dịch nhìn thấy được. Điều này
không biến core Kyber cũ thành FIPS 203 ML-KEM và không phải chứng nhận mật mã.
