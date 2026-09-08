# Crypto RTL freeze candidate v4 — secure zeroization

Ngày đánh giá: **2026-09-07**. Candidate v4 nằm trên nhánh
`codex/asic-frontend-mlkem512`, phát triển tiếp từ candidate v3 tại commit
`8ccebca`. Tại thời điểm lập hồ sơ, v4 chưa có commit/tag freeze và chưa thay
thế artifact FPGA `0.2.0-rc1` ở root.

## Kết luận ngắn

Candidate v4 đã **PASS các cổng functional offline đã chạy**, gồm full
regression và raw Kyber single-attempt 1.024/1.024. P0 scrub sâu được coi là đã
đóng ở mức RTL simulation cho **crypto accelerator**, nhưng chưa phải security
sign-off vật lý hay whole-SoC zeroization.

Candidate này **chưa được freeze/promote** vì còn phải:

1. có review độc lập về FIPS 202/203, reset/zeroize và ranh giới tin cậy;
2. chạy Vivado synthesis/place-route/timing/DRC cho đúng source v4;
3. nạp đúng bitstream v4 và chạy board smoke/stress khi có board.

Vì vậy trạng thái đúng là: **offline v4 PASS; Vivado v4 PENDING; board v4
PENDING**. Kết quả Vivado/board của RC1 và candidate v3 chỉ là bằng chứng lịch
sử, không được dùng để xác nhận netlist v4.

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

## Bằng chứng offline ngày 2026-09-07

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
  manifest `ed583bdf80f069f171f4f10e9831dc894bbb0aa18b664e1385fc9ac1f1d59288`;
- verification inputs: `manifests/verification_inputs_candidate_v4.sha256`,
  SHA-256 của manifest
  `73d24de630ae5fef85b9e5ac40bb51412a34790e213c93405748964596ed1892`;
- ASIC source closure: `asic/manifests/system_asic_v4.sha256`, SHA-256 của
  manifest `4e3a76540d9e2a11625f7d1c01aabe2265c7752fabf0a4012d198df8fe620da6`.

Các vector NIST ACVP/CAVP trong repo được dùng làm known-answer/oracle cho kiểm
tra functional bit-exact. Kết quả trên **không phải** NIST validation,
CMVP/FIPS 140-3 certification, formal proof, constant-time sign-off hay
side-channel/fault-injection sign-off.

Decoder BCH bảo đảm mục tiêu sửa lỗi trong bán kính thiết kế, không phải phát
hiện mọi input ngoài bán kính. Characterization có ca delta codeword weight 41
cho `success=1` nhưng `wrong_root=1`; kết quả này được giữ như một giới hạn
expected và là lý do qualification PUF phải đối chiếu same-root trực tiếp.

## Những điều cố ý chưa thay đổi

- `Kyber_System_Top.bit` và các report post-route ở root vẫn thuộc ML-KEM RC1.
- SHA-256 bitstream RC1 vẫn là
  `183e0af367376ebd7ca6bc2f3747314fd0602306a630af2a2e51858ef1f20e8e`.
- `ARTIFACTS.sha256` là manifest artifact RC1; không cập nhật nó bằng firmware
  v4 khi chưa có bitstream/report v4 tương ứng.
- Các báo cáo RC1/RC2/RC3/RC4 và candidate v3 được giữ nguyên để truy vết.

## Gate còn lại và lệnh tái kiểm trước khi freeze/promote

```sh
make -j1 crypto-freeze-gate
make -j1 impl
git diff --check
```

`crypto-freeze-gate` đã PASS trong đợt offline này; phải chạy lại nếu source,
test/oracle hoặc manifest đổi trước tag. `impl` và board campaign vẫn chưa chạy.

Sau Vivado v4 phải lưu report tài nguyên, timing, route, DRC và audit physical
fingerprint RO. Khi có board, phải nạp đúng bitstream v4, xác nhận INFO
`4B 50 01 03 06`, enroll/reconstruct và stress 100/1.000/10.000. Chỉ sau đó mới
được cân nhắc tag/promote candidate; RC1 root không được ghi đè trong lúc thử.

Ngay cả khi các gate trên PASS, public/production release vẫn bị chặn bởi
license, review mật mã/bảo mật độc lập, qualification PUF nhiều board/PVT và
các hạng mục ASIC PDK/memory/DFT/sign-off.
