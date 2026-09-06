# Minh — Lưu khóa và vòng đời khóa

Cập nhật **2026-09-06**. Minh phụ trách nghiên cứu, threat model và review;
Long thực hiện mọi thay đổi RTL/firmware/test tích hợp.

## Phạm vi nghiên cứu/đối chiếu

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
- `docs/PUF_CHARACTERIZATION_2026-09-05.md`
- `docs/PUF_QUALIFICATION_PLAN.md`
- `docs/RELEASE_READINESS.md`
- `SECURITY.md`

## Đã hoàn thành trên ML-KEM RC1

- Release firmware có capability `0x06` và không xuất shared secret qua UART.
- Seed/status/key Kyber được zeroize sau giao dịch.
- Helper PUF được host lưu ngoài repo; helper không được xem là secret nhưng gắn
  với board/lần enroll.
- AXI/firmware/full-system regression hiện có đều PASS; đây là bằng chứng chức
  năng, chưa phải chứng minh zeroization vật lý hoặc chống side-channel.

## Rủi ro phải ghi rõ

- Chưa có kiến trúc lưu khóa persistent, anti-rollback, access control phần
  cứng hoặc threat model cho mất điện/debug/physical attack.
- KEM loopback dùng khóa vừa được fuzzy extractor phục hồi cho cả hai phía.
  Vì vậy `K_server == K_client` không tự chứng minh khóa đó vẫn là root lúc
  enrollment; phải có phép kiểm tra same-root riêng trong qualification.
- Helper data công khai vẫn cần version, integrity và quy trình provisioning;
  không được nhầm helper với secret hoặc raw response.

## Còn mở

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

Minh chuẩn bị threat model, policy và nhận xét review. Long thực hiện RTL,
firmware, test tích hợp và chốt artifact.

## Definition of Done

- Có sơ đồ vòng đời khóa từ PUF đến zeroize và threat model được review.
- Mọi đường đọc/ghi key có access policy rõ; release interface không đọc được
  secret.
- Zeroize PASS khi hoàn tất, reset, timeout, mismatch và lỗi giao thức.
- Tiêu chí chấp nhận PUF kiểm tra đúng same-root, không chỉ key-match nội bộ của
  một giao dịch KEM.
- Không commit helper/key thật; test dùng vector giả hoặc dữ liệu tạo lúc chạy.

## Lệnh kiểm tra hiện có

```sh
make axi
make system
./scripts/release_check.sh --internal
```
