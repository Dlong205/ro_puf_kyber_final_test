# Phân công và tiến độ nhóm

Bằng chứng cập nhật đến **2026-09-06**; phân công đồng bộ cho nhánh tích hợp
`codex/asic-frontend-mlkem512`, tách từ `codex/fips202-mlkem`. Source RTL
chính thức chỉ nằm trong `rtl/`; không copy RTL vào thư mục cá nhân. Đạt, Tùng,
Minh và Việt Anh thực hiện nghiên cứu/đối chiếu/review; Long là người thực hiện
thay đổi RTL, tích hợp, chạy gate và chốt artifact.

## Các mốc không được nhầm lẫn

| Mốc | Ý nghĩa | Trạng thái |
|---|---|---|
| `fpga-rc4-baseline` tại `6f734fc` | Baseline Kyber/FPGA cũ để so sánh | Bất biến, không dùng làm base mặc định cho thay đổi mới |
| `fpga-mlkem512-0.2.0-rc1` tại `7abbd79` | Bitstream ML-KEM-512 đã test board | Artifact FPGA nội bộ hiện được chấp nhận |
| `crypto-rtl-freeze-candidate-2-2026-09-04` tại `c323408` | Manifest crypto candidate v2 | Chưa phải freeze cuối; còn review độc lập |
| Nhánh tích hợp sau RC1 | Characterization và physical route-lock RO | 10.000 mẫu ngắn hạn + hai build route-lock đã có bằng chứng |
| Candidate v3 trên `codex/asic-frontend-mlkem512` | Sửa FIFO wrapper, khóa secret ở ASIC top và thêm front-end gate | Full gate/Vivado/board 10.000 PASS; P0 secure-zeroize chặn freeze cuối |

## Trạng thái chung

| Nội dung | Trạng thái hiện tại |
|---|---|
| FIPS 202 phục vụ ML-KEM | DONE functional: 50/50 test byte-oriented |
| ML-KEM-512/FIPS 203 | DONE functional nội bộ: 25 KeyGen, 25 Encaps, 25 Decaps và 175 rejection |
| FPGA XC7Z020 50 MHz | PASS implementation/timing/DRC và board stress 10.000/10.000 |
| RO physical reproducibility | PASS full-SoC: 136 endpoint, 128 fixed route, hai build sạch khớp fingerprint |
| RO-PUF ngắn hạn | PASS sơ bộ trên một board/image PUF-only: 10.000 mẫu, HD max 1 |
| Crypto RTL freeze cuối | BLOCKED: phải sửa scrub NTT/FIFO/sponge/FE/KDF rồi review độc lập |
| Freeze RO-PUF | NO-GO: thiếu same-root full-SoC, count-margin, PVT, power-cycle và nhiều board |
| ASIC | Portability/elaboration PASS; backend/sign-off chưa bắt đầu |
| Public release | BỊ CHẶN bởi license và các gate production còn mở |

## Phân chia nội dung

| Thành viên | Nội dung review/nghiên cứu | Kết quả đã có | Đầu ra tiếp theo |
|---|---|---|---|
| Đạt | Mapping FIPS 203, ACVP/oracle, serialization, implicit rejection và provenance | KAT/oracle functional PASS | Biên bản review độc lập và danh sách sai khác/claim được phép dùng |
| Tùng | Vi kiến trúc Kyber/ML-KEM: Client/Server, NTT, codec, FIFO/BRAM/AXI, liveness và single-attempt | Regression 1.024 raw + board 10.000 PASS | Review assertion/invariant, latency/resource và không starvation/underflow |
| Minh | Threat model, lưu khóa, helper, access policy, provisioning và zeroization | Release UART không xuất secret; AXI clear phần nhìn thấy đã qua regression | Rà thiết kế scrub/handshake và vòng đời khóa cho reset/lỗi/timeout/tamper/storage |
| Việt Anh | KDF, Keccak, FIPS 202, domain separation và byte ordering | 50/50 FIPS 202 + KDF fixed-profile PASS | Review độc lập mapping H/G/J/PRF/XOF và ranh giới serialization |
| Long | Toàn bộ implementation/tích hợp/release, fuzzy extractor, firmware/UART/host, RO-PUF, FPGA và ASIC portability | ML-KEM RC1 + v3 board 10.000 + route-lock + campaign PUF ban đầu | Tạo v4 secure-zeroize, rồi same-root/count-margin/PVT/nhiều board và PDK/macro ASIC |

Chi tiết từng phần:

- [`01_kyber_kem_dat_tung/`](01_kyber_kem_dat_tung/README.md)
- [`02_luu_khoa_minh/`](02_luu_khoa_minh/README.md)
- [`03_kdf_viet_anh/`](03_kdf_viet_anh/README.md)
- [`04_ro_puf_long/`](04_ro_puf_long/README.md)

## Quy tắc làm việc chung

1. Thay đổi mới bắt đầu từ tag ML-KEM RC1 hoặc commit tích hợp mới nhất. RC4 chỉ
   dùng để đối chiếu lịch sử; không backport ngầm thay đổi mới vào tag cũ.
2. Mỗi review ghi rõ file/phạm vi, vector hoặc điều khoản đặc tả đã đối chiếu,
   kết luận, điểm còn nghi ngờ và người review. Không dùng retry để che
   mismatch/timeout.
3. Long tiếp nhận review rồi thực hiện mọi thay đổi RTL. Nếu manifest crypto bị
   thay đổi, phải tạo candidate/hash mới và chạy lại toàn bộ gate.
4. Không commit shared secret, helper gắn với board, raw PUF định danh thiết bị,
   waveform lớn, build cache hoặc file Vivado tạm.
5. Nếu thay RTL tổng hợp: chạy lại regression, Vivado implementation, audit
   physical fingerprint và board smoke/stress; không tái sử dụng report của
   netlist trước.

## Cổng trước candidate tiếp theo

Chạy tuần tự để bảo vệ RAM máy phát triển:

```sh
make -j1 crypto-freeze-gate
sha256sum -c ARTIFACTS.sha256
git diff --check
```

Khi thực sự đóng gói internal RC, chạy thêm
`./scripts/release_check.sh --internal`. Script này cố ý chạy lại regression và
gate Kyber dài trước khi kiểm tra artifact/report; nó không thay thế portability
và freeze manifest trong `crypto-freeze-gate`, cũng không tự chạy Vivado/board.

Nếu thay miền RO hoặc constraint vật lý, bổ sung một build cách ly mới, so sánh
fingerprint với RC1 và board regression theo
[`docs/RO_PHYSICAL_REPRODUCIBILITY_2026-09-05.md`](../docs/RO_PHYSICAL_REPRODUCIBILITY_2026-09-05.md).

## Thứ tự ưu tiên chung

1. Sửa P0 secure-zeroize, thêm handshake và test trực tiếp mọi vùng secret.
2. Review độc lập crypto và chốt freeze manifest cuối.
3. Same-root full-SoC, count-margin, warm/cold boot, PVT và nhiều board cho PUF.
4. Chốt contract macro RO, memory mapping, SDC/CDC/DFT và PDK.
5. Chỉ sau các cổng trên mới gọi full ASIC backend và sign-off.

Waveform trình bày và video demo đang hoãn theo quyết định của nhóm.
