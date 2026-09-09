# FPGA split — đo tài nguyên Arty-35T

Ngày 2026-09-09. Nhánh `codex/fpga-v2-split`, RTL mật mã giữ nguyên tại
`73988d6`; wrapper đo cố định `k=2` nằm trong `experiments/fpga_split/`.
Đây là **synthesis out-of-context**, không phải kết quả full Edge có
FE/PUF/transport, P&R, bitstream Arty hoặc kiểm thử board.

## Phương pháp

- Vivado 2020.1, part `xc7a35ticsg324-1L`, clock tham chiếu 20 ns.
- Một block mỗi lượt, `general.maxThreads=1`, cgroup 4 GiB RAM, không swap,
  CPUQuota 100%, timeout 20 phút. Không chạy full-system implementation.
- Cổng seed/K/stream/scrub được giữ quan sát và input động; chỉ `k` cố định
  bằng 2. Không tie-off secret để làm nhỏ giả tạo số liệu.
- Không dùng XDC pin, placement hoặc route-lock của Zynq cho thí nghiệm Arty.
- SHA-256 toàn bộ source/header/tool được kiểm trước và sau synthesis.
- Timing IO chưa có constraint đầy đủ: không lấy WNS OOC làm Fmax board.

## Kết quả

| Profile | LUT / 20.800 | Register | BRAM36 tương đương | DSP / 90 | Trạng thái |
|---|---:|---:|---:|---:|---|
| `server`: KeyGen/Decaps | 11.100 | 10.841 | 14 | 2 | OOC PASS |
| `kdf` | 9.129 | 3.999 | 0 | 0 | OOC PASS |
| `seedctl`: KDF + direct-seed FSM | 9.378 | 4.517 | 0 | 0 | OOC PASS |
| `edgecore`: KDF + scrub + KeyGen/Decaps | 25.540 | 15.436 | 14 | 2 | OOC PASS, **122,79% LUT** |
| `fe` | 4.090 | 3.568 | 0 | 0 | OOC PASS |
| `puf` | 197 | 382 | 0 | 0 | OOC PASS, đủ 128 LUT RO |
| `client`: Encaps | 13.687 | 10.249 | 12,5 | 2 | OOC PASS |

`edgecore` là phép đo tích hợp controller với core mật mã thật, nhưng chưa có
FE, PUF, framing/SPI hoặc board top. Nó đã vượt số LUT vật lý của A7-35T nên
cấu trúc hiện tại chắc chắn không thể đi tiếp P&R trên board này.

Năm lượt baseline đã hoàn tất và kiểm source không đổi PASS. Report gốc, thông số
và checksum nằm trong
[`reports/fpga_split_2026-09-09/completed/summary.json`](../reports/fpga_split_2026-09-09/completed/summary.json).
Phép đo controller seed bổ sung nằm tại
[`reports/fpga_split_2026-09-09/seedctl_v01/summary.json`](../reports/fpga_split_2026-09-09/seedctl_v01/summary.json).
Phép đo `edgecore` nằm tại
[`reports/fpga_split_2026-09-10/edgecore_v02_clean/summary.json`](../reports/fpga_split_2026-09-10/edgecore_v02_clean/summary.json).
DCP/log đầy đủ nằm dưới `build/fpga_split/` (không theo dõi trên Git). Source
commit ghi trong report là baseline RTL; tooling/wrapper
mới được định danh riêng bằng các hash trong `source_manifest.sha256`.

## Nhận xét ban đầu

Encaps riêng chiếm 65,80% LUT: triển vọng đưa **riêng role này** lên Arty
tốt hơn ước lượng cũ từ netlist Zynq, nhưng vẫn chưa có board-top/P&R.
Kế hoạch hai role hiện chọn Encaps trên Zynq và KeyGen/Decaps trên Edge;
không cần đổi vai trò chỉ vì kết quả phép đo này.

KeyGen/Decaps độc lập chiếm 53,37% LUT. Tuy nhiên thêm KDF độc lập đã thành
20.229 LUT (97,25%), chưa FE/PUF/control/buffer/giao tiếp. Phép cộng chỉ dùng
lập ngân sách: tối ưu xuyên hierarchy khi tích hợp có thể thay đổi số liệu.
Nó cho thấy cần giải quyết diện tích KDF/Keccak trước khi kết luận full Edge
vừa Arty-35T.

Thêm FE và PUF thành **24.516 LUT (117,87%)**, chưa control/SPI. Nếu loại
bỏ hoàn toàn chi phí KDF độc lập thì tổng còn **15.387 LUT (73,98%)**; đây
là giả định lập ngân sách, không phải kết quả engine chia sẻ đã triển khai.
So với mốc 80% (16.640 LUT), chỉ còn 1.253 LUT cho mọi logic bổ sung trong
giả định này. Vì vậy phải đo full Edge sau tích hợp, không hứa chắc fit.

Controller direct-seed thêm 249 LUT và 518 register so với KDF độc lập.
Nếu thay KDF độc lập bằng `seedctl`, tổng sơ bộ Edge thành **24.765 LUT
(119,06%)**. Nếu tương lai chia sẻ hoàn toàn phần 9.129 LUT của KDF nhưng
giữ overhead controller hiện đo, tổng lập ngân sách là **15.636 LUT
(75,17%)**; chỉ còn 1.004 LUT đến mốc 80%, chưa tính arbiter/shared-state,
scrub controller, SPI và buffer.

Phép đo tích hợp thật `edgecore` dùng **25.540 LUT (122,79%)**, cao hơn phép
cộng `server + seedctl` 5.062 LUT. Chênh lệch này xác nhận không được dùng
phép cộng OOC riêng lẻ để cam kết fit. Kết luận cho A7-35T hiện tại là
**NO-GO trước P&R**; cần chia sẻ/thiết kế lại Keccak hoặc chuyển sang FPGA lớn
hơn. Thêm FE/PUF/transport chỉ làm áp lực diện tích tăng thêm.

Trong hierarchy của `server`, `hash` dùng 8.166 LUT, riêng sponge dùng
7.736 LUT. Cần đo chi phí state/permutation/control và chốt lịch ownership
trước khi chia sẻ engine; core hiện đã iterative, không phải 24 round unroll.

## Warning và giới hạn

- Các lượt cũ `server`/`client` có `Synth 8-2490` do file legacy `LUT.v` chứa
  module không được dùng tên `LUT1`, trùng primitive Xilinx. File này đã được
  loại khỏi filelist OOC mới; không sửa RTL baseline.
- `server` có 561 input và 293 output chưa đặt IO delay, đúng với boundary
  resource-only. Không có register thiếu clock/internal endpoint unconstrained
  theo `check_timing`, nhưng không thay thế full-top STA/CDC.
- PUF OOC chỉ đo logic, không chứng minh tần số/entropy/reliability.
- PUF `check_timing` ghi 360 pin thiếu clock, 206 endpoint nội bộ chưa
  constraint và 32 loop. Đây là miền RO chưa constraint vật lý cho Arty;
  OOC synthesis PASS không phải timing/CDC sign-off của PUF.
- Không sửa RTL baseline, không nạp board và không promote v4 trong đợt này.

## Cổng đã kiểm nhẹ

- `crypto-freeze-check` và `verification-inputs-check`: PASS, xác nhận source
  và harness/vector không đổi; không phải chạy lại full regression.
- Snapshot functional v4: 18 file, kiểm đóng gói và kiểm độc lập PASS.
- Unit test verifier/parser: 10/10 PASS, gồm corrupt/missing/symlink/forged
  manifest/path traversal/no-overwrite và parsing BRAM phân số.

Hướng dẫn snapshot: [FPGA_V4_BASELINE_GUIDE.md](FPGA_V4_BASELINE_GUIDE.md).
Kế hoạch sau hiệu chỉnh: [MASTER_PLAN_REVIEW_2026-09-09.md](MASTER_PLAN_REVIEW_2026-09-09.md).

## Đợt tiếp theo, theo thứ tự

1. Bổ sung framed stream/backpressure/reset và confirmation. Không đưa K/seed
   ra pin; cổng `shared_secret` hiện chỉ là boundary kiểm thử nội bộ.
2. Thiết kế lịch chia sẻ permutation/state giữa KDF và ML-KEM, ưu tiên KDF
   hoàn tất trước khi core KEM bắt đầu. Giữ baseline riêng để so sánh; không
   multiplex tùy ý hai controller đang đồng thời absorb/squeeze.
3. Thử nghiệm giảm diện tích KDF/Keccak, chạy lại KDF KAT, FIPS 202, ML-KEM
   KAT/implicit rejection/equal timing và zeroize. Sau mỗi thay đổi đo lại
   OOC bằng cùng part/constraint, rồi full Edge synth/P&R.
4. Chỉ serialize FE nếu vẫn vượt ngân sách hoặc cần thêm margin. Sau đó mới
   triển khai SPI/buffer/framing, board bring-up, same-root và PVT.
5. Chuẩn bị PDK/memory/RO macro contract có thể bắt đầu, nhưng chưa tuyên bố
   ASIC layout/sign-off hoàn tất từ các báo cáo FPGA này.
