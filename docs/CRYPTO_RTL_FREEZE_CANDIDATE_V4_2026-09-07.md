# Crypto RTL freeze candidate v4 — secure zeroization

Ngày đánh giá ban đầu: **2026-09-07**; bằng chứng Vivado/board được chốt ngày
**2026-09-08**. Candidate v4 nằm trên nhánh
`codex/asic-frontend-mlkem512`, phát triển tiếp từ candidate v3 tại commit
`8ccebca`. Tại thời điểm lập hồ sơ, v4 chưa có commit/tag freeze và chưa thay
thế artifact FPGA `0.2.0-rc1` ở root.

## Kết luận ngắn

Candidate v4 đã **PASS các cổng functional offline đã chạy**, gồm full
regression và raw Kyber single-attempt 1.024/1.024. P0 scrub sâu được coi là đã
đóng ở mức RTL simulation cho **crypto accelerator**, nhưng chưa phải security
sign-off vật lý hay whole-SoC zeroization.

Candidate này **chưa được freeze/promote** vì còn thiếu review độc lập về FIPS
202/203, reset/zeroize và ranh giới tin cậy. Các cổng do tác giả tự chạy trên
đúng source/image v4 hiện đã hoàn tất: **offline PASS; Vivado 50 MHz PASS;
board PASS 10.000/10.000**. Kết quả RC1 và candidate v3 chỉ là bằng chứng lịch
sử; kết luận v4 dựa trên build cách ly `candidate_v4_final` và đúng bitstream
của build đó.

## Phạm vi zeroize đã triển khai

Firmware protocol 1.3 phát một yêu cầu `secure_zeroize` chung và đợi tín hiệu
hoàn tất. Ngay sau banner khởi động, firmware bắt buộc hoàn tất zeroize trước
khi vào command dispatcher; timeout trả `FF 09` rồi dừng nhận lệnh
(fail-closed). Yêu cầu cũng có thể hủy giao dịch đang chạy. Trong boundary
accelerator, v4 xử lý các nhóm trạng thái sau:

- RO-PUF: dừng controller/RO, reset counter, LFSR, synchronizer và response;
- fuzzy extractor: xóa raw response, reconstructed key, codeword/error staging,
  encoder, syndrome, BMA và Chien pipeline; `helper_out` được giữ lại có chủ ý
  vì helper là dữ liệu công khai cần trả sau enrollment;
- KDF: xóa input shift register, output seed, controller và Keccak state;
- ML-KEM: reset Client/Server, NTT/hash/codec/control state và sponge; quét tuần
  tự đủ 2.048 địa chỉ để ghi zero vào các RAM/FIFO/ciphertext replay liên quan;
- AXI wrapper: xóa d/z/m, key/status và read-data đã hoàn tất; chặn seed/config
  write cạnh tranh trong khi KEM hoặc scrub đang hoạt động.

Core ML-KEM được giữ reset trong toàn bộ cửa sổ scrub. Các pipeline không có
reset riêng được clock bằng zero trong cửa sổ này trước khi `zeroize_done` được
phát. Đây là hành vi được kiểm tra ở RTL; memory macro ASIC sau này vẫn phải giữ
đúng contract scrub/latency và được kiểm chứng lại.

Nếu một AXI read response đang bị backpressure, v4 giữ `RDATA` ổn định đúng giao
thức AXI và chưa phát `zeroize_done`. Sau khi master nhận response, staging được
xóa rồi handshake mới hoàn tất. Cơ chế này tránh tuyên bố hoàn tất trong khi
một secret response hợp lệ vẫn còn outstanding.

## Boundary không nằm trong tuyên bố

Tên capability và claim bắt buộc là **crypto-accelerator zeroize**, không phải
“system-wide secure erase”. Những phần sau nằm ngoài boundary hiện tại:

- register file, pipeline và trạng thái nội bộ PicoRV32;
- firmware stack và `soc_bram`/boot memory;
- các thanh ghi staging của interconnect/peripheral ở phía CPU ngoài
  accelerator;
- pad/debug/JTAG, scan chain, DFT, SRAM remanence và các bản sao sau synthesis;
- dữ liệu đã rời chip hoặc được phần mềm/host lưu trước khi zeroize.

Firmware release và CPU/bus master nội bộ đang thuộc trusted computing base.
Nếu sản phẩm yêu cầu whole-SoC erase hoặc chống attacker có quyền đọc CPU/bus,
phải bổ sung kiến trúc reset/scrub CPU-RAM/interconnect và policy debug/scan,
sau đó chạy lại verification ở RTL, netlist và backend.

FPGA research top vẫn cho phép AXI diagnostic readback nội bộ bằng cấu hình
explicit; ASIC top dùng `EXPOSE_KYBER_SECRETS=0`. Firmware release không xuất
shared secret qua UART. Cấu hình diagnostic không được coi là production top.

## Bằng chứng offline ngày 2026-09-07/08

Tất cả lệnh được chạy tuần tự (`-j1`) để tránh vượt RAM máy phát triển.

| Cổng | Kết quả |
|---|---|
| `make -j1 crypto-freeze-gate` | **PASS**, exit 0 trên tree v4 cuối; bao gồm toàn bộ các cổng dưới đây |
| Verification-input manifest | PASS, 57 testbench/harness/vector/oracle/filelist/gate input |
| `make -j1 regression` | PASS |
| RO-PUF reset/restart/zeroize | PASS |
| Fuzzy extractor Xilinx path | PASS 29/29, gồm mid-operation abort/no-late-done/restart |
| Fuzzy extractor ASIC-portable path | PASS 29/29 |
| FE characterization | PASS 7.728 check trong bán kính `t=8`; ghi nhận giới hạn over-noise expected |
| FIPS 202 | PASS 50/50 |
| SHAKE256 KDF KAT + zeroize | PASS |
| ML-KEM-512 KeyGen | PASS 25/25 NIST ACVP sample, bit-exact |
| ML-KEM-512 Encaps | PASS 25/25 NIST ACVP sample, bit-exact |
| ML-KEM-512 Decaps/rejection | PASS 25/25 valid + 175/175 invalid, K/J exact và timing bằng nhau trong test |
| Legacy Kyber/invalid ciphertext/codec | PASS; codec 32 x 256 coefficient |
| AXI diagnostic và locked-secret | PASS 32 giao dịch mỗi cấu hình |
| AXI scrub sâu | PASS kiểm trực tiếp RAM/FIFO/sponge/core, live abort, stalled RDATA và competing write |
| Full-system firmware/UART | PASS ở 958.516 cycle, protocol 1.3/capability `0x06`; startup zeroize trước command |
| `make -j1 kyber-long` | **PASS 1.024/1.024**, raw mismatch 0, recovered 0, max attempts 1 |
| ASIC portability/full-top elaboration/filelist closure | PASS |
| Crypto RTL/ASIC source manifest | PASS, lần lượt 49 và 79 file |

Ba manifest versioned v4 khớp byte-for-byte với canonical tương ứng tại thời
điểm chạy gate:

- crypto RTL: `manifests/crypto_rtl_freeze_candidate_v4.sha256`, SHA-256 của
  manifest `7444ff3f5506754d78dc30cc77b5c5bf0f2c1aac05e8d9be450ae47603f73e5d`;
- verification inputs: `manifests/verification_inputs_candidate_v4.sha256`,
  SHA-256 của manifest
  `73d24de630ae5fef85b9e5ac40bb51412a34790e213c93405748964596ed1892`;
- ASIC source closure: `asic/manifests/system_asic_v4.sha256`, SHA-256 của
  manifest `c68dbb53dd52014f01afc2beb97479032933a11f14c581dbc8e0cb89c8213841`.

Các vector NIST ACVP/CAVP trong repo được dùng làm known-answer/oracle cho kiểm
tra functional bit-exact. Kết quả trên **không phải** NIST validation,
CMVP/FIPS 140-3 certification, formal proof, constant-time sign-off hay
side-channel/fault-injection sign-off.

Decoder BCH bảo đảm mục tiêu sửa lỗi trong bán kính thiết kế, không phải phát
hiện mọi input ngoài bán kính. Characterization có ca delta codeword weight 41
cho `success=1` nhưng `wrong_root=1`; kết quả này được giữ như một giới hạn
expected và là lý do qualification PUF phải đối chiếu same-root trực tiếp.

## Đóng lỗi suy luận BRAM và bằng chứng vật lý ngày 2026-09-08

Implementation v4 đầu tiên bị chặn vì Vivado chuyển các RAM có nhiều nhánh ghi
trong một process thành thanh ghi phân tán: 242.665/53.200 LUT và lỗi
`UTLZ-1`. Commit `5943ceb` gom scrub/normal thành một địa chỉ, dữ liệu và enable
ghi cho mỗi cổng trong `generic_bram.sv`/`generic_fifo.sv`; scrub vẫn tuần tự
nhưng BRAM inference được giữ. Script capacity audit mới dừng build sớm nếu
Slice LUT sau synthesis vượt sức chứa part.

Build cách ly `candidate_v4_final` trên `xc7z020clg400-2`, Vivado 2020.1 đã
PASS synthesis/place/route/bitgen:

- 50.902/53.200 Slice LUT (`95,68%`), 30.958 FF, 30,5 BRAM tile, 4 DSP;
- 13.283/13.300 slice (`99,87%`), vì vậy chỉ còn 17 slice và không còn biên
  an toàn để thêm logic tùy tiện;
- WNS `+3,268 ns`, WHS `+0,037 ns`, TNS/THS `0`; 72.468/72.468 net route đủ;
- DRC 0 Error/Critical Warning; các warning RO/DSP/pure-PL đã được phân loại,
  nhưng methodology/CDC warning không phải sign-off;
- fingerprint RO khớp chính xác RC1: 136 endpoint, 128 fixed route, SHA-256
  `1fbad9f1d1ec3a04560d506979778991311a00e84d3b31c7e8e56596db464c23`.

SHA-256 bitstream v4 là
`bc3a8ab8cac94c00ad3f02f5c3165ff9f8bbacf13db7ba0952003bb90946260a`;
routed DCP là
`9cd81b827a0414e746eae699beebf68076e8e967d300f6b30b97712869f68ff4`.
Đúng image này đã PASS INFO protocol 1.3/capability `0x06`, enroll,
reconstruct và stress 100/100, 1.000/1.000, 10.000/10.000; fail bằng 0. Run
10.000 đạt trung bình 29,694 ms/giao dịch và 33,677 giao dịch/s. Xem
[`VIVADO_IMPACT_REPORT_CRYPTO_CANDIDATE_V4_2026-09-08.md`](VIVADO_IMPACT_REPORT_CRYPTO_CANDIDATE_V4_2026-09-08.md)
và
[`HARDWARE_TEST_REPORT_CRYPTO_CANDIDATE_V4_2026-09-08.md`](HARDWARE_TEST_REPORT_CRYPTO_CANDIDATE_V4_2026-09-08.md).

## Những điều cố ý chưa thay đổi

- `Kyber_System_Top.bit` và các report post-route ở root vẫn thuộc ML-KEM RC1.
- SHA-256 bitstream RC1 vẫn là
  `183e0af367376ebd7ca6bc2f3747314fd0602306a630af2a2e51858ef1f20e8e`.
- `ARTIFACTS.sha256` là manifest artifact RC1; không cập nhật nó bằng firmware
  hay bitstream v4 khi candidate chưa được review, freeze và promote.
- Các báo cáo RC1/RC2/RC3/RC4 và candidate v3 được giữ nguyên để truy vết.

## Gate còn lại và lệnh tái kiểm trước khi freeze/promote

```sh
make -j1 crypto-freeze-gate
make -j1 impl
git diff --check
```

`crypto-freeze-gate`, implementation và đúng-image board campaign đều đã PASS;
phải chạy lại gate bị ảnh hưởng nếu source, test/oracle, manifest, constraint
hoặc firmware đổi trước tag. RC1 root vẫn không bị ghi đè. Gate kỹ thuật còn
lại trước khi cân nhắc freeze/promote là review độc lập và xử lý finding của
review; không tự ký xác nhận bằng chính các lần chạy của tác giả.

Ngay cả khi các gate trên PASS, public/production release vẫn bị chặn bởi
license, review mật mã/bảo mật độc lập, qualification PUF nhiều board/PVT và
các hạng mục ASIC PDK/memory/DFT/sign-off.
