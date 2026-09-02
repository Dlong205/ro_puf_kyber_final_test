# Minh — Lưu khóa và vòng đời khóa

## Phạm vi phụ trách

- Kiến trúc lưu/giữ key sau fuzzy extractor và KDF.
- Quyền truy cập, trạng thái key-valid, zeroization và hành vi khi reset/lỗi.
- Phân biệt rõ helper data công khai, khóa bí mật volatile và dữ liệu persistent.
- Giao diện với firmware, Kyber và host; không để secret lọt qua UART/LED/debug.

## Source và tài liệu liên quan

- `rtl/soc/soc_peripherals.sv`
- `rtl/kyber/kyber_axi_wrapper.v`
- `rtl/top/Kyber_System_Top.sv`
- `firmware/main.c`
- `host/uart_host.py`
- `docs/UART_PROTOCOL_V1.md`
- `SECURITY.md`

## Trạng thái RC4

- Release firmware có capability `0x06` và không xuất shared secret qua UART.
- Seed/status/key Kyber được zeroize sau giao dịch.
- Helper PUF được host lưu ngoài repo; helper không được xem là secret nhưng gắn
  với board/lần enroll.
- Chưa có kiến trúc lưu khóa persistent đã chốt, anti-rollback, access control
  phần cứng hoặc threat model cho mất điện/debug/physical attack.

## Việc tiếp theo

1. Viết threat model và quyết định khóa chỉ volatile hay cần persistent storage.
2. Nếu volatile: thiết kế register/SRAM key vault, valid bit, quyền đọc một chiều
   sang KDF/Kyber và zeroize trên reset, timeout, mismatch, tamper.
3. Nếu persistent: không ghi raw key; xác định flash/OTP/eFuse hoặc wrapped-key,
   key-encryption-key, integrity, nonce/counter và quy trình provisioning.
4. Tách helper data khỏi secret và định nghĩa format/version/CRC của helper.
5. Thêm test reset giữa giao dịch, lỗi từng stage, lệnh UART không hợp lệ và
   chứng minh secret không xuất hiện trên bus/host ở release mode.
6. Phối hợp Long về PUF lifecycle, Việt Anh về đầu vào KDF và Đạt–Tùng về
   zeroization key/ciphertext của Kyber.

## Definition of Done

- Có sơ đồ vòng đời khóa từ PUF đến zeroize và threat model được review.
- Mọi đường đọc/ghi key có access policy rõ; release interface không đọc được
  secret.
- Zeroize PASS khi hoàn tất, reset, timeout, mismatch và lỗi giao thức.
- Không commit helper/key thật; test dùng vector giả hoặc dữ liệu tạo lúc chạy.

## Lệnh kiểm tra hiện có

```sh
make axi
make system
./scripts/release_check.sh --internal
```
