# Lịch sử thay đổi

## 0.2.0-rc2-dev — chưa phát hành — cập nhật 2026-09-07

- Tạo candidate v4 cho crypto-accelerator zeroize: yêu cầu chung có handshake
  xóa PUF response, toàn bộ BCH FE pipeline/key, KDF/Keccak state, ML-KEM
  Client/Server/NTT/hash/codec/sponge và quét 2.048 địa chỉ RAM/FIFO/ciphertext.
- Zeroize có thể hủy giao dịch đang chạy; core ML-KEM được giữ reset khi scrub.
  AXI giữ `RDATA` ổn định nếu response đang stalled, chỉ báo done sau khi response
  được nhận và staging được xóa; seed/config write cạnh tranh bị chặn.
- Bổ sung reset thật cho hierarchy BCH từng phụ thuộc FPGA initial value. Hai
  backend Xilinx/ASIC-portable PASS 29/29, gồm abort giữa operation, không có
  done muộn và có thể restart.
- Full regression v4 PASS; FIPS 202 50/50, ML-KEM KeyGen/Encaps/Decaps và 175
  ca rejection tiếp tục bit-exact. Gate raw dài PASS 1.024/1.024, mismatch 0,
  recovered 0, max attempts 1. Full-system PASS ở 958.516 cycle.
- Firmware/UART lên protocol 1.3 và giữ capability `0x06`; bit 2 nay được gọi
  chính xác là crypto-accelerator zeroize. Thêm lỗi `0x09` cho zeroize timeout.
- Startup fail-closed: firmware bắt buộc hoàn tất accelerator zeroize sau banner
  và trước command dispatcher; timeout trả `FF 09` rồi không nhận lệnh.
- Boundary không bao gồm PicoRV32 register/pipeline, SoC RAM/stack, bus staging
  hay scan/DFT; firmware release và CPU/bus nội bộ vẫn thuộc trusted base.
- Candidate v4 mới chỉ PASS offline. Vivado implementation và board regression
  cho đúng source/image v4 còn PENDING; bitstream/report root vẫn thuộc RC1.

- Thêm top ASIC với external reset và synchronized release, filelist/manifest,
  constraint template cùng tài liệu clock/reset/CDC và memory inventory.
- Sửa bảy FIFO wrapper có multiple-driver/undriven alias; targeted Kyber KAT,
  AXI 32 giao dịch và ASIC structural lint PASS.
- Top ASIC khóa AXI seed/shared-secret readback và direct key mirror; test cùng
  wrapper ở chế độ diagnostic và locked-secret đều PASS 32 giao dịch, kiểm đủ
  mọi word d/z/m và hai shared-key bank; wrapper/SoC nay khóa mặc định.
- Khép kín filelist ASIC: thêm đủ chín translation unit Keccak và chín header,
  khóa checksum header, đồng thời so dependency record để chặn module/header
  bị Verilator auto-load ngoài manifest.
- Candidate v3 tại `1dcdad8` PASS lại Vivado 2020.1 trên `xc7z020clg400-2` ở
  50 MHz: 49.886 LUT, WNS `+4,732 ns`, WHS `+0,034 ns`, route đủ và 0 lỗi DRC.
  Audit giữ đúng 136 endpoint/128 route RO. Đúng bitstream v3 sau đó PASS
  INFO/enroll/reconstruct và stress 100/100, 1.000/1.000, 10.000/10.000 trên
  board; RC1 root giữ nguyên SHA-256 `183e0af367376ebd...` và đã được nạp lại.
- AI pre-review không nâng v3 thành freeze cuối: lệnh zeroize mới chỉ đóng
  seed/status/readback nhìn thấy, chưa scrub NTT/FIFO RAM, sponge state, khóa FE
  và seed KDF. Phần này được mở thành candidate kế tiếp thay vì waiver ngầm.
- Xuất physical lock full-SoC từ routed DCP ML-KEM RC1 đã chấp nhận: cố định
  128 LUT RO, 8 LUT mux đầu cuối và 128 route vật lý.
- Thêm fingerprint V2 gồm `INIT`, loại cell, LOC/BEL, pin-map, endpoint và
  route; build/release dừng nếu miền RO khác baseline.
- Hai build sạch `locked_a`/`locked_b` khớp chính xác fingerprint RC1; timing
  50 MHz PASS, fully routed, DRC 0 Error/Critical Warning.
- `locked_b` PASS board INFO/enroll/reconstruct và stress 100, 1.000,
  10.000/10.000; sau campaign đã nạp lại bitstream RC1 gốc.
- Bổ sung build cách ly một worker, nạp bitstream theo đường dẫn chính xác,
  hash-gate exporter và cổng so sánh hai implementation.
- Internal release gate và ASIC portability đều PASS; public release vẫn bị
  chặn bởi license, production vẫn chờ qualification PUF/same-root/PVT.
- Đồng bộ README, hồ sơ trạng thái, bring-up và phân công nhóm; tách rõ artifact
  RC1 đã tag với nhánh tích hợp sau RC1, sửa hướng dẫn nạp đúng bitstream root và
  ghi chính xác phạm vi của từng cổng kiểm thử.

## 0.2.0-rc1 — 2026-09-04

- Hoàn thiện đường thuật toán nội bộ ML-KEM-512 theo FIPS 203: KeyGen/Encaps/
  Decaps PASS 25/25 vector mỗi nhóm và implicit rejection PASS 175/175.
- Mở rộng FIPS 202 byte-oriented lên 50/50 test; KDF SHAKE256 fixed-profile
  24-byte → 64-byte PASS bit-exact ở cycle 148.
- Full-system PUF → fuzzy extractor → KDF → ML-KEM PASS ở 956.564 cycle;
  raw single-attempt gate PASS 1.024/1.024, mismatch/retry bằng 0.
- Tối ưu KDF để candidate fit XC7Z020: 49.909 LUT, 30.649 register, 25 BRAM,
  4 DSP; route đủ, DRC không lỗi và timing 50 MHz đạt WNS `+2,226 ns`.
- Nạp bitstream candidate volatile trên `xc7z020_1`; INFO, enroll, reconstruct
  PASS và stress 100/100, 1.000/1.000, 10.000/10.000 không lỗi.
- Run 10.000 đạt latency trung bình 29,608 ms/giao dịch và throughput
  33,775 giao dịch/s.
- Quảng bá bitstream đã test thành `Kyber_System_Top.bit`, SHA-256
  `183e0af367376ebd7ca6bc2f3747314fd0602306a630af2a2e51858ef1f20e8e`.
- Public release vẫn bị chặn bởi quyền phân phối RTL nền và top-level license;
  production còn thiếu review độc lập và qualification PUF.

## 0.1.0-rc4 — 2026-09-03

- Tách RO-PUF thành backend mô phỏng, LUT Xilinx và macro ASIC black-box; cô
  lập toàn bộ `LUT6_L` vào một file dành riêng cho FPGA.
- Cô lập `CARRY4` BCH vào backend Xilinx và thêm đường so sánh tổng hợp được
  bằng standard cell khi bật `KP_TARGET_ASIC`.
- Thay wrapper multiplier NTT mang tên Xilinx bằng phép nhân RTL trung lập;
  Vivado vẫn infer đúng 4 DSP48E1 mà không instantiate primitive DSP48.
- Bổ sung reset asynchronous-assert/synchronous-release và đồng bộ enable cho
  hai counter miền clock RO, cùng cổng `make asic-portability`.
- PASS full regression, ASIC-generic elaboration, 12/12 ca fuzzy extractor
  portable, 10.004 vector multiplier và audit netlist 128/128 feedback RO.
- Build lại XC7Z020 ở 50 MHz: WNS `+3,663 ns`, WHS `+0,056 ns`, 0 lỗi DRC,
  51.682/53.200 LUT, 30.554 register, 23,5 BRAM tile và 4 DSP.
- Nạp image mới và PASS INFO, enroll, reconstruct, stress 100/100,
  1.000/1.000 và 10.000/10.000; run dài đạt 29,119 ms/giao dịch và
  34,342 giao dịch/s.
- Bitstream RC4 SHA-256:
  `bd8153f8ab58f0a704b2f696c54ed1f57d1a31b951d273f547b33926d239f348`.
- Bổ sung thư mục `phan_cong_nhom/` để tách phạm vi Kyber KEM, lưu khóa, KDF
  và RO-PUF cho Đạt–Tùng, Minh, Việt Anh và Long.

## 0.1.0-rc3 — 2026-08-30

- Loại bỏ retry Kyber khỏi firmware/giao thức; protocol lên v1.2, capability
  release `0x06`, mỗi giao dịch chỉ chạy đúng một attempt.
- Sửa liveness NTT Client/Server: counter chỉ tiến khi FIFO có dữ liệu và state
  kết thúc sau khi nhận đủ coefficient thay vì dựa vào cửa sổ cycle cố định.
- Sửa cửa sổ SHAKE matrix generation ở Client state `0x18` và Server state
  `0x2f`; giữ pattern ở matrix mode đến khi `fifo_GENA_ctr` đủ 128 word.
- Bổ sung codec round-trip test, chẩn đoán starvation và cổng release raw
  single-attempt 1.024 vector.
- PASS toàn bộ regression, full-system 952.496 cycle, raw gate 1.024/1.024,
  mismatch 0, recovered 0, max attempts 1.
- Build lại XC7Z020 ở 50 MHz: WNS `+4,371 ns`, WHS `+0,056 ns`, 0 lỗi DRC,
  51.738/53.200 LUT, 30.546 register, 23,5 BRAM tile và 4 DSP.
- Nạp lại board và PASS 100/100, 1.000/1.000, 10.000/10.000 giao dịch;
  run 10.000 đạt 28,914 ms/giao dịch và 34,585 giao dịch/s.
- Bitstream RC3 SHA-256:
  `c78724fd9007d21791caf654b8fe8f08a44653bfa028e6a15af80d7425f04d89`.

## 0.1.0-rc2 — 2026-08-30

- Bổ sung capability `0x08` của giao thức 1.1 cho cơ chế Kyber retry nội bộ có giới hạn.
- Retry cả raw key mismatch giữa server/client và raw Kyber watchdog stall bằng
  `m` mới đã được diversify, tối đa 16 lần.
- Giảm giới hạn watchdog riêng của Kyber và chỉ kéo dài cửa sổ phản hồi phía host sau marker `F`.
- Cho host stress dừng ngay tại giao dịch lỗi đầu tiên để giữ đồng bộ giao thức
  và tránh thống kê cascade gây hiểu nhầm.
- PASS mô phỏng full-system tại 952.479 cycle và stress board 1.000/1.000, sau đó
  10.000/10.000 giao dịch logic.
- Tạo lại implementation: WNS +4.108 ns, WHS +0.048 ns, 0 lỗi DRC,
  51.774/53.200 Slice LUT và SHA-256 bitstream
  `e85e3f2bd0206485aa636b56b9256aae9a38255ab29179f6fb20e37d6b4abdfb`.
- Ghi rõ retry chỉ là biện pháp kỹ thuật tăng availability; nó không loại bỏ lỗi
  raw của core cũ và không chứng minh tuân thủ FIPS 203 ML-KEM-512.

## 0.1.0-rc1 — 2026-08-28

- Bổ sung bản build pure RTL độc lập cho XC7Z020-2CLG400I ở 50 MHz.
- Sửa căn chỉnh luồng/capture Kyber SHAKE và reset khi chạy lặp.
- Bổ sung AXI zeroize, trạng thái sticky key-match và cố định tham số Kyber-512.
- Bổ sung giao thức UART release v1 với device info, timeout có giới hạn và mã lỗi theo giai đoạn.
- Tắt xuất shared secret và LED phụ thuộc secret trong bản mặc định.
- Bổ sung diversify input theo session và zeroize rõ ràng sau mỗi thao tác.
- Bổ sung regression RO-PUF, BCH, FIPS 202 SHAKE256, Kyber loopback, AXI và full-system.
- Sửa source mô phỏng BCH sinh cũ và harness RO-PUF không có clock.
- Chuyển reset trạng thái SHA3/Kyber nối BRAM sang reset đồng bộ.
- Bổ sung công cụ build độc lập, nạp board, host stress và release audit.
- Tạo lại implementation RC1 ngày 2026-08-30: WNS sau route +4.580 ns,
  WHS +0.055 ns, 0 lỗi DRC và SHA-256 bitstream
  `b2a8c1b3b3d112e26b2ccf6bd78370ca8645a105a6d226c47c1fd92f0f6e68cd`.

Phân phối công khai vẫn bị chặn bởi các mục license trong `NOTICE.md`.
