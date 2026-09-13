# Kiểm tra dung lượng board top Edge trên Arty A7-35T — 2026-09-13

## Kết luận

Full Edge gồm RO-PUF, fuzzy extractor, KDF, ML-KEM-512 KeyGen/Decaps và UART
chẩn đoán **không fit** trên `xc7a35ticsg324-1L` ở trạng thái RTL hiện tại.
Không có bitstream full Edge nào được tạo hoặc nạp lên board trong phép thử này.

Kết luận này không phủ định baseline OOC 100 MHz đã ký nhận. Baseline v08 vẫn
PASS với WNS `+0,053 ns`, WHS `+0,046 ns`, route sạch và fingerprint RO khớp.
OOC chứng minh datapath có thể place/route khi đứng một mình; nó không bao gồm
chi phí và ảnh hưởng tối ưu của board top/transport.

## Bằng chứng

| Phương án | Slice LUT sau synth/assembly | Giới hạn | Kết quả |
|---|---:|---:|---|
| Board top tích hợp RTL trực tiếp | 26.815 | 20.800 | NO-FIT |
| PUF checkpoint riêng + core RTL | 26.817 | 20.800 | NO-FIT |
| Nhập full Edge checkpoint sau route + UART | 23.080 | 20.800 | NO-FIT |
| Nhập full Edge checkpoint sau place + UART | 23.078 | 20.800 | NO-FIT |
| Reset UART đồng bộ + chặn nhân bản net fanout | 26.829 | 20.800 | NO-FIT |

PUF checkpoint riêng chỉ chiếm 197 LUT. Vì vậy mức tăng không đến từ bản thân
RO-PUF. Báo cáo hierarchy của board top cho thấy `edge_kem_scrub_controller`
tăng từ 159 LUT ở OOC lên khoảng 4.136 LUT, đồng thời hash/Server cũng tăng.
Vivado tái ánh xạ các mạng reset/scrub fanout lớn khi core nằm dưới POR/UART;
thuộc tính `KEEP/DONT_TOUCH/MAX_FANOUT` thử nghiệm không khắc phục được.

UART transport độc lập đã PASS mô phỏng bit-level. Nó dùng khoảng 598 LUT trong
lần synth đầu và không xuất raw PUF hay shared secret; tag 32-bit chỉ dành cho
chẩn đoán, không phải cơ chế xác nhận mật mã release-grade.

## Quyết định target

- Arty A7-35T tiếp tục là target hợp lệ cho PUF-only characterization và cho
  từng role nhỏ hơn, đặc biệt Client/Encaps có baseline OOC 13.687 LUT.
- Không tuyên bố full Edge board PASS trên A7-35T và không dùng bitstream giả.
- Full Edge tương tác cần một trong hai hướng: FPGA lớn hơn (ưu tiên A7-100T hoặc
  XC7Z020 hiện có), hoặc refactor reset/scrub/Keccak ở cấp kiến trúc rồi chạy lại
  toàn bộ regression, synthesis và P&R.
- Bước kế tiếp trên board 35T: tạo Client-only board top + transport, P&R 100 MHz,
  sau đó test liên thông với host/reference. Song song, giữ campaign PUF-only để
  đánh giá replug, nhiệt độ/điện áp và BCH margin.

## Tái lập

UART transport:

```bash
make -j1 -C sim/edge_uart clean check
```

Phép thử full Edge board top (được kỳ vọng dừng tại capacity gate với RTL hiện
tại, không dùng để tạo release bitstream):

```bash
FPGA_100MHZ_MEMORY_GIB=4 FPGA_100MHZ_TIMEOUT=30m \
  VIVADO=/absolute/path/to/vivado \
  experiments/fpga_100mhz/run_edge_arty_diag.sh <run-id>
```
