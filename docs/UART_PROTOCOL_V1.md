# Giao thức UART v1.3

> **Phase 1 (v1.4): helper record 76 byte.** Bản v1.4 thay helper 33 byte trần
> bằng record có version. Định dạng là một nguồn chân lý duy nhất do
> `scripts/helper_record_spec.py` sinh ra (`rtl/top/helper_record_spec.vh` và
> `firmware/helper_record_spec.h`). Bố cục: magic(4) + record_version(1) +
> protocol_version(1) + profile_id(1) + fe_param_id(1) + mapping_len_bytes(1) +
> mapping_tag(2, LE) + generation(1) + reserved(1) + helper(33) + kcv(28) +
> crc16(2, LE, CCITT-FALSE trên byte 0..73) = 76 byte. Với helper-record v2: record_version=0x02, `mapping_len_bytes=33` (264-bit response), `mapping_tag=0xd501`.
>
> - `01 ENROLL` release trả `AA` + 76 byte record (thay vì 33 byte). Trên đường
>   SoC, trường KCV là 0 vì chưa có hardware KCV generator; trên Edge RTL, KCV
>   được tính từ root key phục hồi và gate fail-closed.
> - `02 RECONSTRUCT` host gửi 76 byte record + 4 byte nonce. Record được validate
>   (magic/version/profile/FE/mapping/reserved/CRC) **trước** PUF/BCH/KDF/Kyber.
> - Mã lỗi mới: `0A` record helper không hợp lệ; `0B` enrollment bị từ chối
>   trong operational mode. Mã lỗi record-level (1..9) khớp RTL `helper_record_parse`.
> - Capability bit 3 = versioned helper record. INFO v1.4 release/SoC:
>   `4B 50 01 04 0E`.
> - Firmware operational (`EDGE_ALLOW_ENROLL=0`, mặc định) từ chối `01`; chỉ
>   build manufacturing/bring-up (`EDGE_ALLOW_ENROLL=1`) mới cho enroll.
>
> Chi tiết threat model/fail-closed: `docs/PUF_ROOT_BINDING_DESIGN.md`.

UART dùng 115200 baud, 8 bit dữ liệu, không parity, một stop bit. Các word helper
nhiều byte và word key chẩn đoán dùng little-endian. Sau reset, thiết bị gửi
banner ASCII `START` đúng một lần, hoàn tất startup accelerator-zeroize rồi mới
nhận command một byte.

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
| `09` | Timeout crypto-accelerator zeroize |

## `00` — INFO

Response: `4B 50 <major> <minor> <capabilities>` (`KP`, phiên bản, cờ tính năng).

Capability bit 0 là xuất key chẩn đoán, bit 1 là diversify theo session và bit 2
là crypto-accelerator zeroize. Bit 3 từng biểu thị retry trong v1.1 nhưng đã bỏ
ở v1.2 sau khi sửa lỗi raw NTT. Response release candidate v4/v1.3 là
`4B 50 01 03 06`.

Bit 2 không tuyên bố whole-SoC erase. Boundary được xác nhận gồm PUF, fuzzy
extractor, KDF và ML-KEM accelerator. PicoRV32, SoC RAM/stack, bus staging và
scan/DFT nằm ngoài boundary này. Artifact FPGA RC1 ở root vẫn chạy protocol
1.2 và trả `4B 50 01 02 06`; không nhầm response đó với candidate v4.

## `01` — ENROLL

Khi thành công, accelerator zeroize hoàn tất trước khi response `AA` theo sau
đúng 33 byte helper data công khai. Helper được giữ lại có chủ ý; raw PUF
response và FE key bị xóa. Khi thất bại, response là `FF <code>` và không có
helper data theo sau.

## `02` — RECONSTRUCT/KEM

1. Thiết bị gửi `X`.
2. Host gửi tám helper word, mỗi word 4 byte. Thiết bị ACK từng word bằng ASCII
   từ `0` đến `7`.
3. Host gửi byte helper cuối. Thiết bị ACK bằng ASCII `8`.
4. Thiết bị gửi marker tiến độ `ABCDEFG` khi các giai đoạn PUF, BCH, KDF và
   Kyber tiến triển. Kyber chỉ chạy đúng một attempt. Khi timeout hoặc key
   mismatch sau khi đã tạo secret, firmware đợi accelerator zeroize rồi trả
   `FF <code>`; nếu chính zeroize timeout thì code cuối là `09`.
5. Thành công chỉ được trả sau khi accelerator zeroize hoàn tất. Firmware
   release trả `AA 00` và không có key. Firmware chẩn đoán sao chép key vào bộ
   đệm phần mềm, hoàn tất accelerator zeroize rồi mới trả `AA 01` và 32 byte
   key; chế độ này nằm ngoài policy release.

Sau banner `START`, firmware v1.3 bắt buộc hoàn tất accelerator zeroize trước
khi nhận command đầu tiên. Nếu timeout, thiết bị trả `FF 09` và dừng thay vì
tiếp tục dispatcher. Sau enrollment, reconstruction thành công hoặc mọi lỗi sau
khi có dữ liệu bí mật, firmware cũng đợi cùng handshake. Ứng dụng host nên dùng
`host/uart_host.py` thay vì tự triển khai byte handshake này.

Việc bỏ retry làm mọi lỗi raw trở thành lỗi giao dịch nhìn thấy được. Các KAT
FIPS 202/ML-KEM bit-exact là xác minh functional nội bộ, không phải NIST
validation, FIPS 140-3 certification hay chứng nhận zeroization vật lý.
