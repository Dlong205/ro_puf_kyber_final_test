# Trạng thái chuyển RTL sang ASIC

Tài liệu này mô tả ranh giới giữa RTL dùng chung và phần bắt buộc phải thay
theo công nghệ. Cổng kiểm tra hiện tại chứng minh thiết kế có thể **elaborate ở
chế độ ASIC-generic**; nó chưa phải kết quả synthesis, place-and-route hay
sign-off ASIC.

## Những phần đã xử lý

### RO-PUF

`kp_ro_cell` là wrapper trung lập với ba backend:

- mặc định: `kp_ro_cell_xilinx`, vòng RO dựng bằng `LUT6_L` cho Zynq-7020;
- `KP_RO_BEHAVIORAL`: `kp_ro_cell_model`, mô hình số xác định cho testbench;
- `KP_TARGET_ASIC`: `kp_ro_cell_asic`, nối tới black-box
  `kp_asic_ro_macro`.

Macro ASIC thật phải có các view Liberty, LEF, GDS và netlist phù hợp PDK, đồng
thời bảo đảm `ro_clk=0` khi `en=0`. Không synthesize vòng dao động từ phép đảo
logic RTL thông thường. Sau khi chọn PDK, cần bổ sung placement, keep-out,
shielding, nguồn cấp, generated-clock/false-path và phương pháp characterize RO.

Counter RO dùng reset kiểu asynchronous-assert/synchronous-release và đồng bộ
`count_en` vào miền clock RO. Challenge/mux chỉ đổi khi toàn bộ RO đang tắt để
tránh runt pulse trên clock đã chọn.

### BCH fuzzy extractor

Primitive `CARRY4` chỉ còn trong `compare_cla_xilinx.v`. Chế độ
`KP_TARGET_ASIC` dùng phép so sánh chuẩn tổng hợp được bằng standard cell. Cả
hai backend đã chạy cùng 12 ca enroll/reconstruct, gồm 0, 1, 8 và 12 lỗi bit.

### NTT multiplier

`ntt_mult_12x12` dùng phép nhân unsigned có một tầng register. RTL không chứa
primitive `DSP48`; bốn DSP trong report FPGA là kết quả inference của Vivado.
ASIC synthesis có thể map `a*b` sang standard cells hoặc macro multiplier mà
không đổi giao thức/latency. Unit test kiểm tra 10.004 vector, enable-hold và
reset của khối multiplier dùng chung.

## Cổng kiểm tra hiện có

Chạy tuần tự:

```sh
make -j1 asic-portability
```

Cổng này thực hiện:

1. regression RO-PUF với mô hình số;
2. 12/12 test fuzzy extractor không dùng `CARRY4`;
3. unit test multiplier;
4. lint wrapper/backend RO Xilinx bằng khai báo primitive mô phỏng;
5. audit vị trí primitive vendor;
6. elaborate toàn bộ `Kyber_System_Top` với `KP_TARGET_ASIC` và macro RO
   black-box.

## Việc còn lại trước ASIC backend/sign-off

- chọn PDK, standard-cell library, corner PVT và tool flow;
- thay black-box bằng macro RO vật lý đã characterize;
- lập chiến lược SRAM/ROM: infer hiện tại cần map sang memory compiler hoặc
  standard-cell memory, đồng thời xác minh nội dung firmware/ROM;
- thêm pad ring, power/ground, reset/clock tree và synchronizer constraints;
- viết SDC hoàn chỉnh, xử lý clock RO bất đồng bộ và chạy CDC/RDC chuyên dụng;
- chốt floorplan, nguồn/IR-drop, CTS, routing và antenna/EM;
- bổ sung scan/DFT và quyết định cách bypass/cô lập RO trong test mode;
- chạy synthesis, STA đa corner, formal equivalence, DRC, LVS và xuất GDSII.

## Xác nhận lại backend FPGA

Nhánh portability đã được xác nhận lại thành artifact RC4 thay vì chỉ dừng ở
elaboration:

- full regression và `make -j1 asic-portability`: PASS;
- Vivado 2020.1 synthesize/place/route/bitstream: PASS, không có `.xci`;
- post-route 50 MHz: WNS `+3,663 ns`, WHS `+0,056 ns`, TNS/THS `0`;
- DRC: 0 lỗi; route: 0 failed/unrouted/partial net;
- netlist RO: 128 LUT, 128 feedback net và 128/128 net có constraint loop;
- Vivado infer 4 DSP48E1 từ phép nhân RTL trung lập;
- board XC7Z020: INFO/enroll/reconstruct và stress 100, 1.000, 10.000 đều PASS.

Report methodology vẫn có 72 `TIMING-17` vì hai counter nhận clock từ RO vật
lý có tần số bất định. `report_cdc` chỉ phân tích đường có clock được khai báo ở
cả hai phía, vì vậy dòng “All paths are Safely Timed” không phải bằng chứng
CDC/RDC sign-off cho miền RO. Điều này phải được xử lý bằng clock/macro contract
và CDC/RDC chuyên dụng khi đã chọn PDK.

Kết quả trên chứng minh việc tách backend không làm hỏng FPGA baseline. Nó chưa
thay thế macro RO, memory compiler, SDC, synthesis/STA hay physical sign-off ASIC.
