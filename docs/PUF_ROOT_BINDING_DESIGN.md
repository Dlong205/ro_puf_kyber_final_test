# Thiết kế ràng buộc root RO-PUF — KCV và helper record (bản 0.4)

Trạng thái: **Phase 1 offline regression PASS sau khi sửa toàn bộ lỗi security
review.** CHƯA hoàn tất: chưa synth bitstream mới, chưa đo mạch, chưa tích hợp
top ASIC riêng. Cùng đọc với `docs/PUF_QUALIFICATION_PLAN.md`,
`docs/PUF_MAPPING_WORKFLOW.md` và `docs/EDGE_CONTROL_CONTRACT.md`.

## 0. Trạng thái triển khai (bản 0.4 — đã sửa review)

Một nguồn chân lý duy nhất: `scripts/helper_record_spec.py` sinh ra
`rtl/top/helper_record_spec.vh` (RTL) và `firmware/helper_record_spec.h`
(firmware). Không có layout/constant thứ hai.

| Thành phần | Trạng thái sau review | Bằng chứng |
|---|---|---|
| KCV so đủ 224 bit + `kcv_out` đúng thứ tự | **ĐÃ SỬA** | `edge_root_binding.sv`; sweep 224 bit + golden `kcv_out` trong `tb_edge_root_binding.sv` |
| Enroll context từ header phát record | **ĐÃ SỬA** | transport `core_enroll_ctx`; loopback ENROLL→SESSION `tb_edge_enroll_loopback.sv` |
| CRC tuần tự (không cone 592 bước) | **ĐÃ SỬA** | `hrec_crc16_step` RX/TX; không còn `hrec_crc16` trong `rtl/` |
| SoC same-root KCV gate phần cứng | **ĐÃ THÊM** | `edge_root_binding` trong `Kyber_System_Top`; firmware chờ `kcv_pass`; `sim/system` wrong-KCV bị chặn |
| Tách firmware operational/diag | **ĐÃ SỬA** | `firmware.hex` + `firmware_diag.hex`; sim nạp diag |
| Test e2e FE thật + KCV thật | **ĐÃ THÊM** | `tb_edge_phase1_e2e.sv` (noise 0-8/>8, codeword-delta) |
| Record 76 byte + CRC + field binding | Đã có từ trước | `helper_record.sv`, `tb_helper_record.sv` |
| BCH popcount telemetry | Đã có từ trước | `FE_CHARACTERIZATION` 8880 check |

Giới hạn còn lại (không được che):

- Chưa synth/P&R bitstream mới trên FPGA; chưa đo mạch (Zynq 100 MHz, Arty OOC).
- Top ASIC riêng cho chuỗi PUF/FE→KCV→KDF→ML-KEM **chưa tạo**; baseline
  `Kyber_System_Asic_Top` chỉ tie-off port KCV (không có engine).
- Chưa có NVM monotonic counter → không chống rollback generation.
- Helper-record **v2** và generated mapping data đã có (record_version=0x02,
  `mapping_len_bytes=33`, `mapping_tag=0xd501`), nhưng scheduler/FE integration
  (Phase I3) **chưa làm**: operational top vẫn mapping-unbound cho tới I3;
  operational/release phải fail-closed khi còn unbound.


## 1. Vấn đề và threat model

Helper data là dữ liệu công khai nhưng phải ràng buộc với enrollment gốc.
Trên đường Edge hiện tại (`rtl/top/edge_puf_mlkem_core.sv`), reconstruct chỉ
cần `fe_success`. BCH là mã tuyến tính: một attacker (hoặc lỗi lưu trữ) có thể
XOR helper với một codeword delta hợp lệ; decoder vẫn trả codeword hợp lệ và
`fe_success=1`, nhưng root key phục hồi là root khác. Stress KEM nội bộ không
phát hiện vì cả hai phía loopback dùng cùng khóa vừa reconstruct.

Threat model của helper công khai:

| Kẻ thù / sự cố | Kênh | Hệ quả nếu không có gate |
|---|---|---|
| Helper sai board / sai lần enroll | Nhập nhầm file, lưu trữ trộn board | ML-KEM vẫn chạy, trả "thành công" với root khác |
| Helper bị sửa có chủ ý | Kênh public | BCH decode thành codeword khác, root đổi |
| Helper hỏng do lưu trữ (bit rotate) | Flash/NVM | `fe_success` có thể vẫn 1 |
| Replay helper generation cũ | Kênh public | Không phát hiện nếu không có generation binding |

KCV không bảo vệ trước attacker có quyền ghi helper và có nhiều (helper, KCV)
từ các enrollment khác nhau; KCV chỉ là **public verifier**, không phải MAC
bí mật. Nó chặn: nhập nhầm, hỏng lưu trữ, rollback giữa các generation đã biết
và một lớp fault-injection làm lệch codeword.

## 2. Phân loại phép kiểm tra

| Phép kiểm | Chứng minh | Cơ chế |
|---|---|---|
| BCH decode success | Kết quả là codeword hợp lệ | `fe_success` hiện có |
| Helper transport integrity | Record đến nguyên vẹn | CRC-8 record (phát hiện lỗi truyền, không phải xác thực) |
| Same-root | Khóa phục hồi == khóa enrollment gốc | KCV SoK từ root key (mục 4) |
| Helper authenticity | Helper + KCV do enrollment đáng tin cậy tạo | Không có trong Phase 1; cần trust anchor/threat model riêng |
| PUF reliability | Root ổn định qua boot/PVT | Phase 2+, theo qualification plan |
| Production security | Cả entropy, leakage, fault review | NO-GO hiện tại |

`fe_success=1` **không** ngụ ý same-root. Chỉ tổ hợp `record valid` +
`CRC ok` + `KCV match` mới cho phép chuyển sang KDF/ML-KEM.

## 3. Helper record có version (thay 33 byte trần)

Record 76 byte, byte stream theo thứ tự gửi qua UART (trường đầu tiên gửi
trước). Tất cả trường đa byte dùng **little-endian** khớp quy ước protocol
hiện có.

```text
offset  size  field
0       4     magic = 0x55464B52          ("RKPU", byte thấp gửi trước)
4       1     record_version = 0x02            (v1 bị operational path từ chối)
5       1     protocol_version = 0x01     (Edge helper protocol)
6       1     profile_id                  (bit7: platform class, bit6..0: profile)
7       1     fe_param_id                 (FE/BCH T=8, N=264, DATA=192 hiện tại = 0x01)
8       1     mapping_len_bytes           (= 33 cho 264-bit response; KHÔNG phải pair count;
                                           0 chỉ còn ở diagnostic/unbound)
9       2     mapping_tag (little-endian) = 0xd501, 16 bit rút gọn từ full SHA3-256 digest
11      1     generation                  (0..255, tăng khi re-enroll; wrap phải re-enroll lại)
12      1     reserved                    (phải = 0)
13      33    helper[264]                 (bản helper cũ, LSB-first như hiện tại)
46      28    kcv                         (28 byte, mục 4)
74      2     crc16 (little-endian, CCITT-FALSE, tính từ offset 0..73)
```

Tổng 76 byte. Quy tắc:

- Deserialize nghiêm ngặt: sai magic/version/length/reserved/CRC/mapping_tag
  phải bị từ chối **trước** BCH/KDF, trả lỗi riêng.
- CRC chỉ là kiểm tra truyền/khối lượng lỗi lưu trữ; không phải chống attacker.
- Legacy helper 33 byte trần: **không được chấp nhận trong release mode**.
  Diagnostic build có thể bật bằng compile-time flag, mặc định tắt.
- `generation` là số 8 bit do enrollment gán; thiết bị không có NVM monotonic
  counter nên **không tuyên bố chống rollback**; host đáng tin cậy lưu generation
  hiện hành và từ chối generation thấp hơn.

## 4. KCV: SoK từ root key, domain separation

KCV là verifikator công khai tạo từ root key phục hồi, dùng primitive FIPS 202
đã có:

```text
KCV = SHAKE256("RO-PUF-KCV-v1" || domain_sep || root_key[192] || kcv_context, 28)
```

Trong đó:

- Chuỗi nhãn ASCII `"RO-PUF-KCV-v1"` cố định, luôn là 12 byte đầu.
- `domain_sep = 0x01` phân biệt với các mục đích SHAKE256 khác của dự án.
- `root_key[192]` là 24 byte khóa FE phục hồi, byte thứ tự giống đường KDF
  hiện tại (MSB của `key_reg` trước).
- `kcv_context` gồm: `record_version` (1B), `protocol_version` (1B),
  `profile_id` (1B), `fe_id` (1B), `mapping_tag` (2B LE), `generation` (1B).

Như vậy KCV gắn cứng root với đúng record/mapping/version. Không tái sử dụng
output KDF hiện tại. Độ dài KCV là **28 byte**: đủ để so khớp đáng tin cậy,
tránh rút gọn xuống mức dễ dính collision thăm dò, và vẫn nhỏ hơn digest 32
byte để record gọn hơn một chút trên UART. Nếu sau này threat model yêu cầu
tính chất verifier khác, độ dài phải được đánh giá lại trong bản đặc tả mới.
So sánh KCV là so sánh thời gian hằng (XOR tích lũy, không early-exit).

Nhận định security:

- KCV không phải MAC; nó không xác thực nguồn record.
- Nếu entropy root thực tế thấp hơn 224 bit (mà hiện chưa được chứng minh),
  KCV có thể hỗ trợ offline guessing; đây là giới hạn ghi rõ, thúc đẩy việc đo
  entropy trước production.
- So sánh KCV dùng XOR tích lũy, không early-exit.

## 5. Enrollment và re-enrollment policy

- Transport Edge hiện chấp nhận `CMD_ENROLL` bất kỳ lúc nào. Phase 1 thêm
  lifecycle input compile-time cho board top:
  `EDGE_LIFECYCLE_PROVISION` (mặc định cho diagnostic/bring-up) cho phép enroll;
  release operational build đặt `EDGE_LIFECYCLE_OPERATIONAL` và lệnh enroll
  bị từ chối bằng STATUS_FAIL, không chạy PUF/FE.
- Re-enroll bắt buộc tăng `generation`; helper/KCV generation cũ bị host từ chối.
- Không thêm NVM secret để "giải quyết nhanh"; NVM lifecycle là hạng mục riêng.
- Enroll command trong operational mode là negative test bắt buộc.

## 6. Fail-closed gate trên Edge RTL

Vị trí: trong `edge_puf_mlkem_core`, giữa `ST_FE_WAIT` và `ST_EDGE_START`
thêm trạng thái `ST_KCV_CHECK`. Chỉ khi tổ hợp sau pass mới chuyển sang
`ST_EDGE_START`:

1. record header hợp lệ (magic/version/profile/fe/mapping/generation);
2. CRC16 ok;
3. KCV computed từ `fe_key` khớp `kcv_stored` (28 byte, so sánh XOR tích lũy).

Tham chiếu KCV/header không hard-code trong RTL; nó là input từ bên tin cậy
(host provision/characterization) qua port `kcv_ref_*`, `ctx_ref_*`. Testbench
cung cấp giá trị; release board lấy từ flow provisioning.

Hành vi fail-closed:

- Mismatch bất kỳ → không phát `edge_start`, `protocol_start`, `secret_valid`;
  `result_success <= 0`; scrub PUF/FE/KDF tạm; trả `done` với cờ lỗi.
- Reset/zeroize giữa KCV → rơi về IDLE, mọi state KCV/root đã xóa.
- Latency KCV cố định theo design (SHAKE256 absorb cố định 56 byte
  input, một lần permute với rate 136); đường fail và pass có cùng số chu kỳ
  sponge; so sánh cuối là một chu kỳ.
- Không xuất root/KCV-derived secret ra bất kỳ port nào trong release.

## 7. Telemetry

Thêm cổng diagnostic (chỉ bật trong characterization build, không board release):

- `bch_err_count[6:0]`: population count thật của `err_reg` đã áp dụng
  (đếm số vị trí bit correction thực sự, không phải nội bộ synthesis);
- `kcv_pass`, `record_fail`, `crc_fail`, `mapping_fail`, `version_fail`;
- `zeroize_done` đã có.

Release protocol chỉ trả mã lỗi tổng quát, không lộ chi tiết các cờ này.

## 8. Ranh giới zeroize

- `root_key` (FE key), `kcv_computed`, sponge state, header buffer: trong
  boundary zeroize Edge hiện có (FE `zeroize`, KDF scrub, KEM scrub).
- KCV reference từ provision là public verifier; không cần scrub nhưng vẫn
  xóa cùng chu kỳ khi zeroize để tránh trộn trạng thái.
- Không mở rộng claim zeroize sang PicoRV32/SoC RAM/scan.

## 9. Claims KHÔNG được phép sau khi gate PASS

- Không tuyên bố RO-PUF freeze, entropy 192/256 bit, production-ready.
- Không tuyên bố helper authenticity — KCV là public verifier.
- Không tuyên bố chống rollback khi chưa có NVM monotonic counter.
- Không tuyên bố multi-device qualification — vẫn là một-board data.
- Mapping provisional một board vẫn không được đưa vào release RTL.

## 10. Tests bắt buộc

Xem mục 6 trong yêu cầu Phase 1: 18 negative tests, tất cả phải tự động,
chạy trong `sim/edge_wrapper` và `sim/edge_mlkem` tuỳ thuộc level. Test
wrong-root (case 4) phải chứng minh trực tiếp: `fe_success=1` nhưng KCV từ chối,
không có `edge_start` pulse, không `secret_valid`, khóa tạm được scrub.

## 11. Thuật ngữ kiểm tra record

- `record_fail`: sai magic/length/reserved.
- `version_fail`: sai record_version/protocol_version.
- `mapping_fail`: sai mapping_tag.
- `crc_fail`: sai CRC16.
- `kcv_fail`: sai KCV sau khi mọi cái trên đã pass.
- `same_root_pass`: tất cả pass — mới được chạy KDF/ML-KEM.
