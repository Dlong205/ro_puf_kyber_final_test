# Memory inventory cho ASIC

Kiểm kê ngày 2026-09-06 từ hierarchy `Kyber_System_Asic_Top`, profile k=2.
Số bit dưới đây là capacity logic, chưa gồm parity/ECC, banking, spare row,
decoder hay overhead macro.

## Macro-memory candidate

| Nhóm | Cấu hình/instance | Số bit |
|---|---|---:|
| ML-KEM FIFOs — Server | outer 32x128, 34x512, 24x512, 10x128; hash 36x256, 24x2048, 25x256, 40x1024 | 140.800 |
| ML-KEM FIFOs — Client | outer 32x128, 32x512, 24x512; hash như Server | 138.496 |
| NTT RAM — Server | 2x(24x256), 2x(24x64), 1x(48x128) | 21.504 |
| NTT RAM — Client | như Server | 21.504 |
| NTT ROM — Server | 3x(12x128) | 4.608 |
| NTT ROM — Client | 3x(12x128) | 4.608 |
| Ciphertext replay | 32x256 | 8.192 |
| Firmware memory | 32x4096 | 131.072 |
| **Tổng** |  | **470.784 bit (~57,47 KiB)** |

Cross-check theo loại: FIFO 279.296 bit + NTT RAM 43.008 bit + NTT ROM 9.216
bit + ciphertext 8.192 bit + firmware 131.072 bit = 470.784 bit.

## Small arrays/register files chưa tính vào tổng macro

- UART RX FIFO 16x8, helper registers 9x32.
- AXI seed registers 3x8x32.
- PicoRV32 register file và các shift-register/pipeline nhỏ.
- Wide Keccak/ML-KEM/FE state registers.

Các mục này vẫn phải có area/zeroize/scan review; “không phải macro candidate”
không có nghĩa là không chứa secret.

## Contract hành vi cần giữ

- `generic_fifo_sync`: single-clock, registered read data; pointer reset không
  xóa array; write/read bị chặn khi full/empty.
- `generic_bram`: hai port dùng cùng clock trong wrapper hiện tại, synchronous
  read; nonblocking semantics cho giá trị cũ khi read/write cùng địa chỉ.
- NTT ROM: synchronous registered output, 128x12, nội dung case tường minh.
- `soc_bram`: single-port, synchronous read, byte-write enable, 4096 word;
  preload bằng `$readmemh` hiện chưa phải cơ chế boot ASIC.
- Ciphertext replay: port A write/port B read cùng clock, read latency một cycle.

## Việc phải làm khi có PDK/compiler

1. Gom các depth/width thành danh sách macro khả dụng và lượng banking/mux cần.
2. Viết wrapper riêng cho behavioral/FPGA/ASIC macro, giữ latency/collision.
3. Chạy test độc lập cho mỗi adapter, sau đó ML-KEM KAT/rejection/full-system.
4. Chốt memory BIST, repair, scan boundary và policy zeroize. Pointer reset đơn
   thuần không xóa secret còn nằm trong SRAM.
5. Chọn boot ROM/mask ROM/SRAM preload và chứng minh reset vector chạy thật.
