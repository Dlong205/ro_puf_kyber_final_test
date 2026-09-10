# FPGA split — đo tài nguyên và full Edge OOC trên Arty-35T

Ngày 2026-09-09. Nhánh `codex/fpga-v2-split`, RTL mật mã giữ nguyên tại
`73988d6`; wrapper đo cố định `k=2` nằm trong `experiments/fpga_split/`.
Kết quả baseline ngày 09-09 được giữ để đối chiếu. Cập nhật 10-09 bổ sung
KDF compact và top tích hợp `edge_puf_mlkem_core` có RO-PUF, FE, KDF, scrub
và KeyGen/Decaps. Tất cả vẫn là **synthesis out-of-context**: chưa có
transport/confirmation, P&R, bitstream Arty hoặc kiểm thử board.

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
| `edgefull`: PUF + FE + KDF compact + scrub + KeyGen/Decaps | **19.566** | **19.403** | **14** | **2** | OOC PASS, **94,07% LUT** |
| `fe` | 4.090 | 3.568 | 0 | 0 | OOC PASS |
| `puf` | 197 | 382 | 0 | 0 | OOC PASS, đủ 128 LUT RO |
| `client`: Encaps | 13.687 | 10.249 | 12,5 | 2 | OOC PASS |

`edgecore` là kiến trúc cũ dùng KDF lớn và đã vượt số LUT vật lý. `edgefull`
là phép đo tích hợp thật của kiến trúc mới: `kp_puf_top` →
`fuzzy_extractor` → KDF SHAKE256 compact → `Kyber_Server`. Nó còn 1.234 LUT
(5,93%) trước transport, confirmation và board glue. Vì vậy kết luận chỉ là
**fit tài nguyên OOC có điều kiện**, chưa đủ cơ sở gọi là board fit.

Năm lượt baseline đã hoàn tất và kiểm source không đổi PASS. Report gốc, thông số
và checksum nằm trong
[`reports/fpga_split_2026-09-09/completed/summary.json`](../reports/fpga_split_2026-09-09/completed/summary.json).
Phép đo controller seed bổ sung nằm tại
[`reports/fpga_split_2026-09-09/seedctl_v01/summary.json`](../reports/fpga_split_2026-09-09/seedctl_v01/summary.json).
Phép đo `edgecore` nằm tại
[`reports/fpga_split_2026-09-10/edgecore_v02_clean/summary.json`](../reports/fpga_split_2026-09-10/edgecore_v02_clean/summary.json).
Phép đo full Edge compact được khóa tại
[`reports/fpga_split_2026-09-10/edgefull_compact_v02/summary.json`](../reports/fpga_split_2026-09-10/edgefull_compact_v02/summary.json).
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

Phép đo `edgecore` cũ dùng **25.540 LUT (122,79%)**, cao hơn phép cộng
`server + seedctl` 5.062 LUT. KDF compact serial hóa theta theo cột và chi
theo hàng, giữ hai bank lane 1600-bit; KAT SHAKE256 24-byte → 64-byte khớp
bit-exact ở 411 chu kỳ. Sau thay đổi này, `edgecore` compact trung gian còn
15.282 LUT và phép đo quan trọng hơn là full `edgefull` đạt **19.566 LUT
(94,07%)**. Một thử nghiệm in-place Rho/Pi dùng 20.113 LUT (96,70%) nên bị
loại và source được trả về bản hai bank đã kiểm KAT.

Kết luận cho A7-35T chuyển từ NO-GO tuyệt đối sang **CONDITIONAL trước P&R**.
Thiết kế đã nằm dưới capacity nhưng headroom quá nhỏ để thêm giao tiếp một
cách tùy ý. Không được tuyên bố fit board cho đến khi có board top tối giản,
constraint đúng part/pin/clock, placement/route, timing closure và test thật.

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
- Full `edgefull` có đúng 128 LUT RO. 32 `Synth 8-295` timing-loop critical
  warning là các loop vật lý dự kiến của 32 RO, không phải lỗi bị bỏ qua;
  chúng vẫn cần placement/route constraint riêng cho Arty và audit netlist.
- PUF OOC chỉ đo logic, không chứng minh tần số/entropy/reliability.
- PUF `check_timing` ghi 360 pin thiếu clock, 206 endpoint nội bộ chưa
  constraint và 32 loop. Đây là miền RO chưa constraint vật lý cho Arty;
  OOC synthesis PASS không phải timing/CDC sign-off của PUF.
- Crypto baseline v4 không bị sửa; KDF compact và wrapper nằm ở nhánh Edge.
  Không nạp board và không promote v4 trong đợt này.

## Cổng đã kiểm nhẹ

- `crypto-freeze-check` và `verification-inputs-check`: PASS, xác nhận source
  và harness/vector không đổi; không phải chạy lại full regression.
- Snapshot functional v4: 18 file, kiểm đóng gói và kiểm độc lập PASS.
- Unit test verifier/parser: 10/10 PASS, gồm corrupt/missing/symlink/forged
  manifest/path traversal/no-overwrite và parsing BRAM phân số.
- KDF compact KAT/zeroize, controller, valid/invalid Edge và scrub: PASS.
- Manifest report full Edge kiểm exhaustive source và đúng 19.566 LUT, không
  có synthesis error, đúng 32 warning loop RO: PASS.

Hướng dẫn snapshot: [FPGA_V4_BASELINE_GUIDE.md](FPGA_V4_BASELINE_GUIDE.md).
Kế hoạch sau hiệu chỉnh: [MASTER_PLAN_REVIEW_2026-09-09.md](MASTER_PLAN_REVIEW_2026-09-09.md).

## Đợt tiếp theo, theo thứ tự

1. Thêm test functional end-to-end cho wrapper PUF → FE → Edge, gồm enroll,
   reconstruct, helper lỗi, abort/reset và zeroize theo lifecycle.
2. Chốt transport/framing tối thiểu và lập ngân sách trước khi viết RTL.
   Không đưa K/seed ra pin; `shared_secret` hiện chỉ là boundary kiểm thử.
3. Tạo board top/constraint đúng Arty A7-35T rồi full synthesis/P&R/timing.
   Nếu LUT hoặc congestion không đóng, ưu tiên giảm thêm xuống khoảng
   80–85%; chia sẻ Keccak với ML-KEM là phương án lớn nhưng phải làm trên
   prototype riêng và chạy lại toàn bộ FIPS/ML-KEM/zeroize regression.
4. Khi P&R đạt, khóa placement/route RO riêng cho Arty, enroll lại trên đúng
   image, rồi board bring-up, same-root, power-cycle và PVT.
5. Chuẩn bị PDK/memory/RO macro contract có thể bắt đầu, nhưng chưa tuyên bố
   ASIC layout/sign-off hoàn tất từ các báo cáo FPGA này.
