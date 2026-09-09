# Nhận xét và triển khai master plan FPGA → ASIC

Ngày: 2026-09-09. Đầu vào: `RO_PUF_MLKEM_FPGA_to_ASIC_Master_Plan.md`,
SHA-256 `83d638f0ac709d901013bb7d418991e3da78c6ef24eb1711ed65f4a4065efcd0`.
Source được đánh giá: `73988d6`; source tạo bitstream v4: `5943ceb`.
Nhánh thực hiện: `codex/fpga-v2-split`.

## Quyết định

**Chấp nhận hướng kiến trúc, triển khai theo các điều chỉnh dưới đây.** Đích mới
là Edge PUF + FE + KDF + ML-KEM KeyGen/Decaps trên Arty, Encaps trên Zynq;
ASIC V1 hướng tới Edge với controller RTL. Đây là bước phát triển tiếp theo
baseline v4, có thay đổi giao diện và kiến trúc; chưa phải chuyển nguyên v4
sang một part FPGA khác.

Hai Arty cùng loại là mục tiêu demonstration. Việc có đủ hai board chưa được
xác nhận trong đợt này; synthesis và simulation có thể tiến hành trước.
V4 đã PASS offline/Vivado/board, nhưng chưa sign-off mật mã độc lập hoặc
qualification PUF. Không tạo nhãn `golden` có nghĩa bảo mật/production từ các
test loopback; lưu snapshot functional bất biến để đối chiếu.

## Các điều chỉnh bắt buộc

| Mục trong kế hoạch | Điều chỉnh cho source hiện tại |
|---|---|
| Tên Client/Server | `Kyber_Server` nhận `d,z`, làm KeyGen/Decaps → **Edge Arty**. `Kyber_Client` nhận `m`, làm Encaps → **Zynq**. Tên vai trò network và module legacy khác nhau. |
| Shared iterative Keccak | Core hiện đã lặp 24 round bằng feedback. Tối ưu cần đo là datapath của một round, các bản sao state, logic absorb/squeeze và chia sẻ permutation; không mô tả baseline là 24-round unrolled. |
| Shared sponge | Có overlap absorb request kế tiếp với squeeze trước đó. Phải định nghĩa owner, backpressure, context/state, reset/abort và zeroize; mux đơn giản không đủ. Ưu tiên lịch tuần tự KDF hoàn tất rồi ML-KEM dùng engine. |
| Full Arty fit trước tách role | Đảo thứ tự: đo từng khối → contract/tách role + buffer → tối ưu → full Edge synthesis/P&R. Full loopback không phải full Edge. |
| LUT dưới 75/80% | Dùng làm ngân sách thiết kế, không phải bằng chứng route/timing. Với 20.800 LUT, mốc 75% là 15.600, 80% là 16.640. Cần xét slice packing/control sets/SRL/BRAM và congestion. |
| WNS/Fmax | Post-synth OOC chỉ là ước lượng nội bộ; không suy ra Fmax board hoặc ASIC. Board gate phải có clock thật, IO constraints, P&R và timing. |
| Tối ưu FE | Chỉ serialize nếu report cho thấy cần. Đánh đổi latency/energy phải đo. Firmware hiện reconstruct mỗi giao dịch; muốn chỉ reconstruct lúc boot phải thay contract lifecycle và test. |
| Direct secret path | Cần làm thật: firmware hiện đọc KDF seed và ghi seed KEM qua CPU/MMIO. Mask readback KEM hiện có chưa ngăn CPU thấy seed từ KDF. |
| `system_zeroize` | Chốt boundary Edge gồm mọi bản sao secret, không đặt tên toàn hệ thống nếu CPU/bus/scan vẫn còn residue. Giữ quét RAM tuần tự và scrub-before-START. |
| SRAM wrapper | Giữ số port, latency, byte enable, read-during-write, collision và scrub. Interface một port tối giản không thay trực tiếp được true-dual-port RAM hiện có. |
| Self-test mode | Giữ regression loopback trong simulation/target Zynq riêng. Không instantiate cả hai core vào Arty chỉ để giữ SELF_TEST. Arty có thể chạy KAT của role của nó. |
| ML-KEM-768 | Parameter hóa độ dài buffer được; profile thuật toán hiện chỉ xác minh k=2. Không suy rằng tăng buffer là có ML-KEM-768 đã kiểm chứng. |
| RO placement | Lock/fingerprint RC1 chỉ dành cho XC7Z020. Arty cần baseline placement/route riêng trên đúng chip/revision và enrollment mới. |
| Clock Arty | Xác minh board clock/part/pin thực tế trước bitgen. Clock ngoài 100 MHz không được khai báo 20 ns để giả đạt 50 MHz; cần clocking hoặc enable đúng thiết kế. |

## Những điểm bảo mật kế hoạch còn thiếu

1. **Entropy của seed.** NIST chấp nhận seed `(d,z)` làm dạng biểu diễn khóa và
   tái sinh expanded key. Điều đó không chứng minh seed từ PUF hiện đủ entropy.
   Với mô hình thứ tự tần số 32 RO đang dùng, giới hạn cấu trúc là
   `log2(32!) ≈ 117,663 bit` trước khi xét helper leakage. SHAKE xuất 512 bit
   không tạo thêm entropy. Giữ claim PUF-derived seed ở mức nghiên cứu cho đến
   khi có đánh giá phù hợp.
2. **Randomness Encaps.** Zynq cần nguồn `m` phù hợp threat model, DRBG/entropy
   và xử lý lỗi. Mixer cycle/counter hiện tại chỉ phục vụ demonstration.
   Các test deterministic vẫn dùng seed đã biết để đối chiếu bit-exact.
3. **Helper/registry.** Chốt enrollment tin cậy, version/build/device binding,
   integrity, re-enroll và rollback. CRC32 phát hiện hỏng truyền; không xác
   thực helper, public key hay thiết bị trước attacker chủ động.
4. **Key confirmation.** Không gửi K để so sánh hai board. Dùng MAC được đặc
   tả trên transcript với nonce mới, device ID, hash(ek), ciphertext, version
   và sequence/session. Server phải đối chiếu ek đã đăng ký để kiểm same-root.
   MAC dùng K xác nhận possession với Edge đã đăng ký; nó chưa xác thực server
   với Edge, vì ai có ek cũng có thể Encaps. Mutual authentication cần thêm
   trust anchor cho server.
5. **Implicit rejection.** Phân biệt lỗi frame/length/CRC với ciphertext đủ
   768 byte nhưng không hợp lệ. Ca sau phải giữ đường `J(z || c)`, không trả
   cờ re-encryption mismatch hoặc bỏ sớm làm lộ validity. Chỉ testbench được
   quan sát equal; protocol dùng kết quả confirmation chung.
6. **Replay/reset.** Sequence có thể lặp sau boot; phải có freshness/session
   binding. Test reset, timeout, CS bị nhả giữa frame, backpressure, buffer
   overflow và mất clock giữa scrub. SPI CDC phải có thiết kế và test riêng.
7. **Scope ASIC.** Bỏ PicoRV32 là lựa chọn tốt cho Edge nhỏ, nhưng phải thay
   toàn bộ control đang ở firmware và test đúng top đó trên FPGA. Flow SoC
   có CPU hiện tại vẫn cần boot ROM/SRAM loader; Edge không CPU giải quyết
   một kiến trúc khác, không làm finding boot của SoC cũ tự biến mất.
8. **DFT.** Test-mode request phải chặn scan/secret access ngay, đợi scrub
   hoàn tất rồi mới cho scan; cần clock vẫn chạy trong scrub và fail-closed.
   Chỉ gán `test_mode → zeroize` không đủ chống đọc trong cửa sổ xóa.

## Trình tự thực hiện đã điều chỉnh

| Đợt | Công việc | Điều kiện kết thúc |
|---|---|---|
| A — baseline và số liệu | Snapshot v4 gồm commit/firmware/XDC/bit/DCP/report; đo OOC từng role/KDF/FE/PUF trên 35T | Hash và report có provenance; không nhầm OOC là board PASS |
| B — contract Edge | Chốt KeyGen/Decaps, EK/CT memory/stream, direct seed, control FSM và confirmation/registry | Test độc lập backpressure/reset/abort/invalid input; legacy regression còn PASS |
| C — diện tích | Tối ưu datapath/state Keccak theo số liệu, chia sẻ KDF/ML-KEM có lịch; FE chỉ khi cần | FIPS 202/ML-KEM KAT/rejection/zeroize PASS, report A/B và full Edge P&R đạt |
| D — liên board | SPI 5 MHz ban đầu, frame parser, host/reference, một Arty rồi hai Arty | Interoperability, same-root và 10.000 session/device; negative/reset tests |
| E — FPGA freeze | PUF dataset theo môi trường/power-cycle, independent review, gói artifact nhất quán | Tag FPGA sau khi các gate đúng phạm vi đã đóng |
| F — ASIC Edge | PDK/macro SRAM/RO/pad, CDC/RDC/DFT, synthesis/equivalence, P&R/STA/DRC/LVS/IR/EM | GDS + reports đúng PDK; qualification silicon thực hiện sau chế tạo |

Có thể chuẩn bị PDK, macro RO, memory/DFT contract song song với B–D. Không
cần đợi mua đủ board mới khảo sát ASIC, nhưng phải ổn định top/giao diện/macro
trước full-chip floorplan cuối. Việc đặt tag hay freeze không tự thay thế
review độc lập, chứng nhận NIST hoặc quyền phân phối code/PDK.

## Đợt triển khai đầu

- Đã tạo nhánh `codex/fpga-v2-split` từ `73988d6`.
- Khóa riêng snapshot functional v4; giữ lịch sử RC1 và manifests crypto v4.
- Thêm tooling resource OOC tại `experiments/fpga_split/`, một worker và giới
  hạn tài nguyên. Mỗi report ghi top/part/source input, không tạo bitstream.
- Số liệu thực chạy và trạng thái từng phép đo nằm trong báo cáo resource đi
  kèm. Full Edge/SPI/shared Keccak là đợt tiếp theo, chưa được đánh dấu PASS.

## Nguồn đối chiếu

- [NIST FAQ: seed là định dạng khóa thay thế](https://csrc.nist.gov/Projects/Post-Quantum-Cryptography/faqs)
  (FAQ cập nhật 2026-06-16, truy cập 2026-09-09).
- [FIPS 203 và ghi chú errata](https://csrc.nist.gov/pubs/fips/203/final).
- [AMD UG474: XC7A35T có 20.800 LUT, 41.600 FF, 5.200 slice](https://docs.amd.com/r/en-US/ug474_7Series_CLB/7-Series-FPGA-CLB-Resources).
- [Digilent Arty A7: part 35T, BRAM/DSP](https://digilent.com/shop/arty-a7-100t-artix-7-fpga-development-board/).
- Source: `rtl/kyber/ref/Kyber_Server.v`, `Kyber_Client.v`, `sha3_shake_core.v`,
  `rtl/top/kdf_keccak.sv`, `firmware/main.c`, `asic/docs/THREAT_MODEL.md`.

Đây là nhận xét kỹ thuật có hỗ trợ AI; không phải biên bản sign-off độc lập
của Đạt, Tùng, Minh, Việt Anh hoặc chuyên gia mật mã.
