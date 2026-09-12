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

Kết quả tham chiếu ngày 2026-09-12 cho `xc7a35ticsg324-1L`:

- 19.257 LUT logic (92,58%), 14 BRAM, 2 DSP;
- setup slack +0,072 ns, hold slack +0,058 ns tại chu kỳ 10,000 ns;
- 0 net unrouted và 0 net partially routed;
- toàn bộ FIPS 202, ML-KEM-512 ACVP và Edge valid/invalid regression PASS.

Nếu đã có checkpoint route âm nhẹ, có thể chạy riêng bước phục hồi bằng
`postroute_optimize.tcl`; flow chính đã tự động hóa cùng chuỗi lệnh cho các lần
chạy mới.
