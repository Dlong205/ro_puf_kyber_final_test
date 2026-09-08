# ASIC front-end findings — cập nhật 2026-09-07

## Đã xử lý trong đợt đầu

| ID | Finding | Xử lý/bằng chứng |
|---|---|---|
| FE-001 | Board top dùng power-up initialization thay external reset | Thêm `Kyber_System_Asic_Top`, module `reset_sync_n` với async assert/two-cycle sync release; reset smoke test PASS |
| FE-002 | Không có compile filelist ASIC chuẩn | Thêm filelist explicit, include list và legacy deny-list |
| FE-003 | Bảy FIFO wrapper vừa drive output trực tiếp vừa assign từ wire chưa drive | Nối FIFO vào wire nội bộ đúng cách; MULTIDRIVEN/BLKANDNBLK về 0; Kyber KAT và AXI 32 giao dịch PASS |
| FE-004 | ASIC boundary không được lộ seed/shared-secret | Top ASIC khóa readback/mirror; AXI mở/khóa secret kiểm đủ d/z/m và hai K bank, 32 giao dịch mỗi chế độ PASS |
| FE-013 | Filelist system/ML-KEM thiếu 9 translation unit Keccak và manifest bỏ sót header | Thêm source/header list tường minh, hash toàn closure và gate so dependency record; không còn auto-load ngoài danh sách khóa |
| FE-014 | BCH pipeline phụ thuộc FPGA initial value và không được xóa sâu | Truyền synchronous reset/zeroize qua encoder, syndrome, BMA và Chien; Xilinx/ASIC-portable PASS 29/29, gồm mid-operation abort/no-late-done/restart |
| FE-015 | Accelerator giữ secret trong RAM/FIFO/sponge sau reset pointer | Candidate v4 quét 2.048 địa chỉ, giữ core reset, xóa PUF/FE/KDF/ML-KEM state; AXI deep assertions và full regression offline PASS |

## Đang mở

| ID | Mức | Finding/điều kiện đóng |
|---|---|---|
| FE-005 | High | RO macro vẫn là black-box chỉ có `en/ro_clk`; cần implementation và views theo PDK. |
| FE-006 | High | 470.784 bit memory chưa map compiler; firmware còn `$readmemh`. |
| FE-007 | High | Accelerator zeroize đã mitigated ở RTL, nhưng randomness, CPU/SoC/bus residue, scan/DFT và netlist/memory remanence trong `THREAT_MODEL.md` chưa đóng. |
| FE-008 | High | Chưa có PDK/library/pad/DFT/MMMC, nên chưa thể sign-off timing/area/power. |
| FE-009 | Medium | Verilator còn 1.497 warning không gating: 1.156 width, 94 unused, 69 generate unnamed, 53 open pin, 51 procedural assignment init và các nhóm nhỏ. Cần giảm/waive theo object trước freeze. |
| FE-010 | Medium | 5 `SYNCASYNCNET` cần CDC/RDC review; không được blanket-waive. |
| FE-011 | Tool | `verilator --lint-only` 5.050 gặp internal error ở BCH; gate dùng `--cc` elaboration và lưu log. |
| FE-012 | Tool | Yosys 0.9 đọc/hierarchy FIPS 202 được, nhưng `proc` vượt giới hạn 20 s và gần 1 GiB RAM; không dùng full synthesis trên máy/tool cũ này. |
| FE-016 | P0 full-SoC/tapeout | `soc_bram` còn dựa vào `$readmemh`; phải chọn mask-ROM/boot-ROM/SRAM loader, giữ đúng latency và chạy gate-level boot test. Nếu firmware không boot thì startup scrub cũng không chạy. |
| FE-017 | P0 production claim | `m` hiện được diversify từ KDF/cycle/counter qua mixer 32-bit, không phải RBG/DRBG đã review. Cần entropy source, DRBG và health-test fail-closed trước claim production/FIPS system. |
| FE-018 | P1 IP contract | ML-KEM wrapper độc lập có thể nhận START trước lần scrub đầu, trong khi SRAM ASIC power-up không xác định. Tích hợp SoC v4 đã scrub ở boot; reusable-IP phải gate START hoặc bắt buộc integration contract scrub-first + random-init test. |
| FE-019 | P1 AXI/backend | Write bị từ chối lúc busy/scrub hiện vẫn nhận AXI `OKAY`; cần SLVERR/retry hoặc rejected-write status cho master tổng quát. Scrub cũng cần 2.048 cạnh clock liên tục và macro SRAM giữ đúng write-zero sweep. |

## Tool inventory trên máy hiện tại

| Tool | Trạng thái |
|---|---|
| Verilator | 5.050, dùng được cho front-end elaboration |
| Yosys | 0.9, quá cũ/nặng cho design hiện tại; chỉ parse thử |
| OpenROAD/OpenSTA/KLayout/Magic/Netgen | không tìm thấy trong PATH |
| Genus/Innovus/Tempus/Calibre | không tìm thấy trong PATH |
| PDK/library env và `.lib/.lef/.gds/.spef` | không có trong repo/môi trường đã kiểm tra; chỉ có SDC template chưa sign-off |

Không cài tool/PDK hoặc chạy job tổng hợp nặng tự động trong đợt này. Backend
chỉ bắt đầu sau khi nhận bộ công nghệ hợp lệ và pin version/checksum.
