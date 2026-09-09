# Contract điều khiển Edge không CPU — bản 0.1

Trạng thái: **đang triển khai**, chưa phải interface freeze. Phạm vi hiện có
là đường `FE key → KDF → d,z → scrub → Kyber_Server`; FE/PUF vật lý, framed
stream/SPI và confirmation chưa được kết nối.

## Chuỗi giao dịch

```text
IDLE
  -> nhận start + FE key 192 bit
  -> KDF SHAKE256 tạo 512 bit
  -> chốt d = word 0..7, z = word 8..15
  -> scrub key/output/state KDF
  -> pulse kem_start với d,z ổn định
  -> KeyGen/Decaps sử dụng d,z
  -> kem_done: scrub d,z
  -> done một chu kỳ
```

`edge_seed_controller` thực thi đường seed. `edge_kem_scrub_controller` quét
RAM/FIFO trước launch và khi zeroize; `edge_control_plane` ghép hai khối theo
thứ tự KDF scrub → KEM scrub → KEM start. `start` được nhận một lần; tín
hiệu giữ cao không tự chạy lại và sau abort phải hạ xuống trước khi re-arm.
`zeroize` có ưu tiên cao nhất, hủy giao dịch và không cho `kem_start` muộn.

## Phân loại dữ liệu

| Dữ liệu | Loại | Quy tắc |
|---|---|---|
| PUF response, FE key | Bí mật | Không ra pin/MMIO; scrub theo lifecycle |
| KDF output, `d`, `z` | Bí mật | Chỉ dây/register nội bộ; KDF scrub trước KEM |
| Shared secret `K` | Bí mật | Chỉ đi vào confirmation engine; không truyền để so sánh |
| Helper | Public nhưng cần integrity/binding | Registry tin cậy, version/device/build binding |
| EK, ciphertext | Public | Stream/buffer có length và backpressure rõ ràng |
| `busy`, `done`, lỗi frame | Không bí mật | Không được lộ validity ciphertext nội bộ |

Wrapper resource OOC cố ý đưa seed ra biên để synthesis không xóa logic;
đó không phải board interface. Board top cuối không có port `seed_d`,
`seed_z`, FE key hoặc `K`.

## Ownership và zeroize còn phải triển khai

1. Controller Edge chỉ phát launch request sau khi KDF đã scrub; control plane
   chỉ phát `core_start` sau khi quét đủ địa chỉ `0..2047`.
2. `Kyber_Server` tự chốt `d/z` ở state đầu; seed controller giữ seed đến
   `kem_done` rồi xóa.
3. Scrub sequencer hiện quét đủ dải địa chỉ `0..2047` và reset core trong lúc
   quét. Việc xác nhận mọi RAM/FIFO của board top đều thuộc dải này vẫn là
   điều kiện trước khi gọi full Edge zeroize.
4. Khi `zeroize`/reset/timeout xảy ra: chặn start/stream, reset core, quét RAM,
   rồi mới báo `scrub_done`. Không cho nhận phiên mới trong cửa sổ scrub.
5. Test mode/scan ASIC chỉ được mở sau `scrub_done`, fail-closed nếu clock
   scrub hoặc bộ đếm không hoàn tất.

## Giao diện public dự kiến

- EK out và ciphertext in dùng `valid/ready/data/last`, độ dài profile
  ML-KEM-512 lần lượt 800 và 768 byte.
- Lỗi frame/CRC/length được báo trước khi gọi Decaps. Ciphertext đủ length
  nhưng sai nội dung vẫn đi hết implicit rejection, không có cờ `equal` ra
  protocol.
- Confirmation dùng MAC trên transcript/nonce/session/device/hash(EK)/CT;
  không gửi `K`. Thiết kế MAC và trust anchor server vẫn là hạng mục mở.

## Gate trước khi freeze interface

- Test seed controller với KDF thật: mapping, busy start, held start,
  mid-operation abort, no-late-start, scrub state — PASS.
- Test scrub sequencer/control plane: thứ tự KDF scrub, quét đủ dải KEM,
  one-cycle start/done, abort và idle-zeroize — PASS ở controller-level.
- `edge_mlkem_core` nối control plane vào `Kyber_Server`: valid loopback khớp
  khóa, ciphertext sửa bị reject, hai đường cùng 21.585 chu kỳ, zeroize xóa K
  và đưa Server idle — PASS. Ca invalid integration kiểm hành vi/mismatch;
  oracle `J(z||c)` bit-exact độc lập vẫn dựa trên gate v4 hiện có.
- Một ca valid và một ca ciphertext sửa đều đạt `secret_valid` ở 19.535 chu
  kỳ; tổng gồm scrub cuối là 21.585 chu kỳ. Đây chưa phải chứng minh
  constant-time tổng quát. Cần thêm: framed stream backpressure/reset,
  KAT KeyGen/Decaps qua API Edge, confirmation và CDC.
- Mọi thay đổi chia sẻ Keccak phải giữ test KDF/FIPS 202/ML-KEM/zeroize và
  so sánh với baseline v4 đã khóa.

Chạy gate controller-level hiện tại:

```bash
bash scripts/check_edge_control.sh
bash scripts/check_edge_mlkem.sh
```

Hai manifest `edge_control_v01.sha256` và `edge_mlkem_integration_v01.sha256`
khóa controller và lớp tích hợp. Đây là manifest phát triển riêng, không thay
thế manifest crypto candidate v4 hoặc tạo freeze/tag mới.
