# Threat model và vòng đời khóa — bản nháp P0/P1

Trạng thái: **DRAFT**, cập nhật 2026-09-07; chưa phải security sign-off.

## Tài sản cần bảo vệ

- raw PUF response, fuzzy-extractor key và KDF seed;
- ML-KEM seeds `d`, `z`, `m`, secret key nội bộ và shared secret;
- helper data về tính toàn vẹn, version và quyền enroll/re-enroll;
- firmware/boot image và các bit điều khiển debug/test/scan.

Helper data không cần bí mật tuyệt đối, nhưng không được tự động coi là tin cậy
hoặc không rò thông tin. Entropy budget phải trừ leakage theo construction thực.

## Boundary tin cậy tạm thời

- Firmware release và bus master nội bộ hiện được giả định tin cậy để duy trì
  chức năng baseline. Giả định này chưa phù hợp nếu có DMA/debug master khác.
- UART host được coi là không tin cậy: input sai/timeout không được làm lộ key,
  treo vĩnh viễn hoặc bỏ qua zeroize.
- Kẻ tấn công vật lý mạnh, probing, laser/EM fault và power analysis chưa được
  xử lý đầy đủ. PUF làm root không tự bảo vệ các đường key sau khi tái tạo.
- Foundry/library/tool và quy trình nạp firmware tạm thời thuộc trusted supply
  chain; quyết định secure boot/anti-rollback còn `OPEN`.

## Findings và trạng thái

| ID | Mức | Finding/điều kiện đóng |
|---|---|---|
| SEC-01 | Mitigated cho ASIC top | Wrapper/SoC mặc định khóa secret; `EXPOSE_KYBER_SECRETS=0` chặn readback d/z/m, hai shared secret và direct key mirror; test AXI locked 32 giao dịch PASS. FPGA research top phải opt-in diagnostic rõ ràng và không được dùng làm production top. |
| SEC-02 | P0 trước production/FIPS system claim | `m` được trộn từ KDF/cycle/counter qua mixer 32-bit, chưa phải entropy source + DRBG đã characterize; cần kiến trúc RBG và xử lý health-test failure. |
| SEC-03 | High | Scan/debug/DFT chưa có policy; cần test-mode authentication/lock, partition secret và coverage report. |
| SEC-04 | High | Chưa có entropy budget định lượng cho PUF sau tương quan/helper leakage. |
| SEC-05 | Medium | Helper chưa có version/integrity/anti-reenroll policy hoàn chỉnh. |
| SEC-06 | Mitigated một phần ở RTL | Candidate v4 PASS scrub PUF/FE/KDF/ML-KEM accelerator, gồm RAM/FIFO/sponge/live-abort/backpressure. PicoRV32, SoC RAM/stack, bus staging, scan/DFT và netlist remanence nằm ngoài boundary và vẫn OPEN. |
| SEC-07 | Medium | Secure boot, firmware authenticity và rollback chưa được định nghĩa. |
| SEC-08 | Open scope | Fault/side-channel target và mức countermeasure chưa được chốt. |
| SEC-09 | P1 với boundary hiện tại | `bridge_wdata`, peripheral read staging, PicoRV32 state và SoC RAM có thể giữ bản sao secret. Đây là P0 nếu mở claim sang whole-SoC erase; clear staging chỉ là defense-in-depth và không thay thế policy CPU/RAM/scan. |

## Tiêu chí tối thiểu trước crypto/system freeze

1. Tách rõ PUF root và KEM randomness; không gọi counter/cycle là TRNG.
2. Chỉ block tin cậy được phép đưa seed và nhận shared secret; mọi readback ngoài
   policy trả lỗi/zero và có test.
3. Reset, timeout, invalid helper và transaction failure đều dẫn tới trạng thái
   xác định; secret được zeroize không phụ thuộc firmware tiếp tục chạy.
4. DFT/debug policy được review trước scan insertion.
5. Review độc lập ghi tên/ngày/phạm vi; tài liệu AI không thay thế sign-off.

## Contract accelerator-zeroize của candidate v4

Firmware protocol 1.3 phát yêu cầu chung, đợi `zeroize_done` sau quét 2.048 địa
chỉ ML-KEM và dùng lỗi `0x09` nếu timeout. Startup bắt buộc chạy handshake này
sau banner nhưng trước command dispatcher; timeout dừng nhận lệnh. Helper FE
công khai được giữ lại có chủ ý sau enrollment.

Contract không được gọi là system-wide secure erase. Để mở rộng threat model
ra CPU/bus hoặc sau scan insertion, cần kiến trúc scrub/reset riêng cho
PicoRV32, firmware data memory/interconnect và policy scan/debug; sau đó chạy
lại verification trên netlist dùng macro memory thật.
