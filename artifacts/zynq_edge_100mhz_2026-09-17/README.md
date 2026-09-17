# Bitstream full Edge Zynq-7020 — 100 MHz

- Target: `XC7Z020-2CLG400I` (`xc7z020clg400-2`)
- Source commit: `2f7b60368486444553c3aecf4d955e183fb4cd94`
- Input clock: 50 MHz tại N18
- Core clock: 100 MHz qua `PLLE2_BASE`
- Bitstream SHA-256:
  `11423b477b8478f0f7265605b518fab45d0d85b9cd69b01211d7e82f556133bd`
- Timing: WNS `+0,562 ns`, WHS `+0,045 ns`
- Route: 0 routing error
- Board: PASS INFO, ENROLL, một SESSION đối chiếu đầy đủ và stress 100/100
  SESSION hợp lệ.

Đây là ảnh chẩn đoán CPU-free; result tag 32 bit không phải confirmation
protocol production. Báo cáo implementation nằm tại
`reports/fpga_100mhz_zynq7020_2026-09-17/`.

