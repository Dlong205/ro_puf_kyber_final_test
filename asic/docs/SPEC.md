# Đặc tả ASIC front-end — bản nháp có kiểm soát

Trạng thái: **DRAFT/P0**, cập nhật 2026-09-07. Những mục ghi `OPEN` là điều kiện
phải chốt trước freeze RTL cuối, không phải chức năng đã cam kết.

## 1. Phạm vi baseline

Baseline hiện tại là SoC demo khép kín:

1. đo RO-PUF 264 bit;
2. fuzzy extractor BCH tạo key 192 bit;
3. SHAKE256 KDF tạo seed 512 bit;
4. PicoRV32 điều khiển ML-KEM-512 server/client loopback;
5. UART thực hiện enroll/reconstruct và trả trạng thái không bí mật.

ML-KEM profile được cố định ở `k=2`. FIPS 202/203 functional evidence hiện có
được giữ làm oracle, nhưng chưa đồng nghĩa với chứng nhận FIPS/FIPS 140-3.

`OPEN-SCOPE-01`: quyết định sản phẩm cuối chỉ là demonstrator loopback hay phải
có API public-key/ciphertext để interoperability với đối tác phần mềm bên ngoài.
Nếu cần API ngoài, giao diện và test phải hoàn tất trước freeze.

## 2. Boundary và giao diện

Top front-end: `Kyber_System_Asic_Top`.

| Port | Hướng | Ý nghĩa |
|---|---|---|
| `clk_i` | input | clock digital hệ thống |
| `rst_ni` | input | reset mức thấp, assert bất đồng bộ |
| `uart_rx_i` | input | UART nhận |
| `uart_tx_o` | output | UART phát |
| `status_o[0]` | output | UART TX đang hoạt động |
| `status_o[1]` | output | giao dịch ML-KEM hoàn tất |

Không có PUF key, KDF seed hay shared secret ở output top. Top đặt
`EXPOSE_KYBER_SECRETS=0`, nên các địa chỉ AXI seed/key trả zero và direct key
mirror bị buộc zero; status/control vẫn hoạt động. Pad, ESD, PLL/clock
source, power-on-reset analog, power domain và package nằm ngoài top hiện tại và
phải được thêm trong P4 nếu mục tiêu là chip độc lập.

Candidate v4 có crypto-accelerator zeroize gồm PUF/FE/KDF/ML-KEM và handshake
hoàn tất sau scrub. CPU PicoRV32, SoC BRAM/stack, bus staging và scan/DFT nằm
ngoài boundary này và hiện thuộc trusted base. `OPEN-SCOPE-02`: quyết định có
yêu cầu whole-SoC secure erase hay không trước khi chốt DFT/backend.

## 3. Clock và reset

- Baseline: 50 MHz (`20 ns`); 100 MHz chỉ là exploration riêng.
- `rst_ni` phải được giữ thấp đến khi nguồn và `clk_i` ổn định theo library.
- Top đồng bộ release qua hai flip-flop; logic hệ thống dùng `rst_sys_n`.
- Hai clock RO có thể dừng và không đồng bộ với `clk_i`; không được giả định là
  clock STA thông thường.

## 4. Boot và memory

Firmware hiện được nạp bằng `$readmemh` vào `soc_bram`. Đây là mô hình
FPGA/simulation, chưa phải boot contract ASIC. `OPEN-MEM-01`: chọn boot ROM/SRAM
hoặc ROM mask, quy định reset vector, preload, latency và byte-write; sau đó tạo
adapter và boot test trên model memory đích.

Tổng macro-memory candidate hiện tại là 470.784 bit (không tính register/small
shift arrays); xem `MEMORY_INVENTORY.md`.

## 5. Yêu cầu functional trước freeze

- FIPS 202 KAT và ML-KEM-512 KeyGen/Encaps/Decaps/rejection phải PASS.
- Reset giữa mọi phase, timeout, invalid command/config và accelerator-zeroize
  phải PASS; startup fail-closed nếu zeroize timeout.
- FIFO/memory adapter phải giữ đúng latency/read-during-write của RTL baseline.
- Nếu thêm API ngoài: interoperability với implementation độc lập phải PASS.
- ASIC filelist/manifest phải khớp; không có primitive FPGA hoặc file legacy.
- RTL/netlist equivalence và gate-level smoke/KAT phải PASS sau synthesis.

## 6. Mục tiêu vật lý tạm thời

- 50 MHz là mục tiêu P0; area/power chưa đặt số tuyệt đối khi chưa có PDK.
- Kết quả generic synthesis không được dùng làm con số tapeout.
- PVT corners, voltage, temperature, lifetime, IR/EM và DFT coverage là `OPEN`
  đến khi nhận bộ công nghệ và yêu cầu cuộc thi/foundry.
