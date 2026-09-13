# Thí nghiệm full Edge 100 MHz trên Arty A7-35T

Flow này độc lập với report OOC 50 MHz đã khóa. Nó synthesis timing-aware ở
10 ns, chạy place/route và tự gọi `phys_opt_design -directive AggressiveExplore`
nếu route đầu còn slack âm. Flow không có board pinout và không tạo bitstream.
Kết quả là timing closure của core OOC, không phải board timing sign-off.

```sh
VIVADO=/absolute/path/to/vivado \
  bash experiments/fpga_100mhz/run_edgefull.sh ten_luot_chay
```

Flow luôn dùng một worker, mặc định giới hạn 4 GiB RAM và không cho swap storm.

## Board top chẩn đoán

`run_edge_arty_diag.sh` tổng hợp full Edge cùng UART và pinout Arty A7-35T.
Với RTL hiện tại, đây là phép thử capacity có chủ đích và dừng NO-FIT tại
26.815/20.800 Slice LUT; nó không sinh bitstream release. UART riêng vẫn có
testbench bit-level PASS trong `sim/edge_uart`.

```sh
make -j1 -C sim/edge_uart clean check
VIVADO=/absolute/path/to/vivado \
  bash experiments/fpga_100mhz/run_edge_arty_diag.sh ten_luot_chay
```

Chi tiết và các phương án checkpoint đã loại được ghi tại
`docs/ARTY_A7_35T_BOARD_TOP_CAPACITY_2026-09-13.md`.

Kết quả tham chiếu ngày 2026-09-12 cho `xc7a35ticsg324-1L`:

- 19.257 LUT logic (92,58%), 14 BRAM, 2 DSP;
- setup slack +0,072 ns, hold slack +0,058 ns tại chu kỳ 10,000 ns;
- 0 net unrouted và 0 net partially routed;
- toàn bộ FIPS 202, ML-KEM-512 ACVP và Edge valid/invalid regression PASS.

Nếu đã có checkpoint route âm nhẹ, có thể chạy riêng bước phục hồi bằng
`postroute_optimize.tcl`; flow chính đã tự động hóa cùng chuỗi lệnh cho các lần
chạy mới.
