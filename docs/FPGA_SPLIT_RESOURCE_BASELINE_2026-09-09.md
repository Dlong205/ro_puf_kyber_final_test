# FPGA split — đo tài nguyên Arty-35T

Ngày 2026-09-09. Nhánh `codex/fpga-v2-split`, RTL mật mã giữ nguyên tại
`73988d6`; wrapper đo cố định `k=2` nằm trong `experiments/fpga_split/`.
Đây là **synthesis out-of-context**, không phải kết quả full Edge, P&R,
bitstream Arty hoặc kiểm thử board.

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
| `fe` | 4.090 | 3.568 | 0 | 0 | OOC PASS |
| `puf` | 197 | 382 | 0 | 0 | OOC PASS, đủ 128 LUT RO |
| `client`: Encaps | 13.687 | 10.249 | 12,5 | 2 | OOC PASS |

Full Edge/controller/SPI chưa được triển khai trong đợt đo này. Không dùng
bảng trên để tuyên bố hệ thống Arty đã vừa chip hoặc đạt timing.

Cả 5 lượt đã hoàn tất và kiểm source không đổi PASS. Report gốc, thông số
và checksum nằm trong
[`reports/fpga_split_2026-09-09/completed/summary.json`](../reports/fpga_split_2026-09-09/completed/summary.json).
DCP/log đầy đủ ở `build/fpga_split/arty35t_probe_20260909/` (không theo dõi
trên Git). Source commit ghi trong report là baseline RTL; tooling/wrapper
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

Trong hierarchy của `server`, `hash` dùng 8.166 LUT, riêng sponge dùng
7.736 LUT. Cần đo chi phí state/permutation/control và chốt lịch ownership
trước khi chia sẻ engine; core hiện đã iterative, không phải 24 round unroll.

## Warning và giới hạn

- `server` và `client` có Critical Warning `Synth 8-2490`: module legacy `LUT1` trong
  `rtl/kyber/ref/LUT.v` trùng tên định nghĩa của thư viện. Không có instance
  `LUT1` trong RTL Kyber hiện tại; OOC không có blackbox. Đây vẫn là mục cần
  làm sạch filelist/namespace ở đợt sau, không gọi kết quả zero-warning.
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

1. Chốt contract Edge không CPU: seed nội bộ, KeyGen → chuyển EK → nhận CT →
   Decaps → confirmation, reset/abort/zeroize và ownership bộ nhớ. Không đưa
   K/seed ra pin vì wrapper đo hiện có các output này.
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
