# ASIC front-end findings — 2026-09-06

## Đã xử lý trong đợt đầu

| ID | Finding | Xử lý/bằng chứng |
|---|---|---|
| FE-001 | Board top dùng power-up initialization thay external reset | Thêm `Kyber_System_Asic_Top`, module `reset_sync_n` với async assert/two-cycle sync release; reset smoke test PASS |
| FE-002 | Không có compile filelist ASIC chuẩn | Thêm filelist explicit, include list và legacy deny-list |
| FE-003 | Bảy FIFO wrapper vừa drive output trực tiếp vừa assign từ wire chưa drive | Nối FIFO vào wire nội bộ đúng cách; MULTIDRIVEN/BLKANDNBLK về 0; Kyber KAT và AXI 32 giao dịch PASS |
| FE-004 | ASIC boundary không được lộ seed/shared-secret | Top ASIC khóa readback/mirror; AXI mở/khóa secret kiểm đủ d/z/m và hai K bank, 32 giao dịch mỗi chế độ PASS |
| FE-013 | Filelist system/ML-KEM thiếu 9 translation unit Keccak và manifest bỏ sót header | Thêm source/header list tường minh, hash toàn closure và gate so dependency record; không còn auto-load ngoài danh sách khóa |

## Đang mở

| ID | Mức | Finding/điều kiện đóng |
|---|---|---|
| FE-005 | High | RO macro vẫn là black-box chỉ có `en/ro_clk`; cần implementation và views theo PDK. |
| FE-006 | High | 470.784 bit memory chưa map compiler; firmware còn `$readmemh`. |
| FE-007 | High | Randomness/zeroize/DFT findings còn lại trong `THREAT_MODEL.md` chưa đóng. |
| FE-008 | High | Chưa có PDK/library/pad/DFT/MMMC, nên chưa thể sign-off timing/area/power. |
| FE-009 | Medium | Verilator còn 1.501 warning không gating: 1.154 width, 94 unused, 71 generate unnamed, 52 open pin, 51 procedural assignment init và các nhóm nhỏ. Cần giảm/waive theo object trước freeze. |
| FE-010 | Medium | 5 `SYNCASYNCNET` cần CDC/RDC review; không được blanket-waive. |
| FE-011 | Tool | `verilator --lint-only` 5.050 gặp internal error ở BCH; gate dùng `--cc` elaboration và lưu log. |
| FE-012 | Tool | Yosys 0.9 đọc/hierarchy FIPS 202 được, nhưng `proc` vượt giới hạn 20 s và gần 1 GiB RAM; không dùng full synthesis trên máy/tool cũ này. |

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
