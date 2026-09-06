# Kế hoạch hoàn thiện RO-PUF + ML-KEM-512 đến ASIC

Ngày lập: **2026-09-06**. Đây là kế hoạch đề xuất, không phải báo cáo các pha
đã thực hiện. Long thực hiện implementation và tích hợp; các thành viên khác
nghiên cứu, đối chiếu và hỗ trợ review theo khả năng thực tế.

## 1. Đích hoàn thành

| Mốc | Sản phẩm bàn giao | Ý nghĩa |
|---|---|---|
| M1 — Hệ thống RTL được chốt | Đặc tả, RTL/filelist/manifest, mô hình RO và memory, test, biên bản review | Logic và giao diện ổn định trong phạm vi đã chọn |
| M2 — Full-system ASIC layout | GDS, netlist, SDC, macro views, report timing/DRC/LVS/nguồn và script tái tạo | Hoàn thành thiết kế trước chế tạo theo PDK và phạm vi kiểm tra đã ghi |
| M3 — Chip hoạt động và được đánh giá | Silicon, board đo, firmware, kết quả functional/PUF/PVT/power-cycle | Xác nhận phần cứng chế tạo thực sự hoạt động và đạt chỉ tiêu đã chốt |

M2 là đích phù hợp nếu nội dung ASIC của cuộc thi yêu cầu layout/GDS và báo cáo
kiểm chứng. M3 cần thêm chế tạo, đóng gói, thiết bị đo và nhiều chip. GDS của riêng
khối ML-KEM là mốc trung gian; để gọi full-system phải có cả PUF, fuzzy extractor,
KDF, quản lý khóa, điều khiển/bộ nhớ và các giao diện thuộc phạm vi đã chọn.

Public redistribution và chứng nhận mật mã chính thức là các cổng riêng. Kết quả
functional nội bộ không tự trở thành chứng nhận FIPS hoặc FIPS 140-3.

## 2. Điểm xuất phát đã có bằng chứng

- Artifact FPGA được chấp nhận: `fpga-mlkem512-0.2.0-rc1`, 50 MHz trên XC7Z020.
- Baseline Kyber cũ: `fpga-rc4-baseline`, giữ để so sánh lịch sử.
- FIPS 202: 50/50 test byte-oriented cho bốn primitive cần cho ML-KEM.
- ML-KEM-512: KeyGen/Encaps 25 vector NIST mỗi nhóm; Decaps 25 vector oracle
  độc lập và 175 rejection; FPGA full-pipeline stress 10.000 giao dịch đã PASS.
- Crypto RTL: manifest 48 file đang khớp, trạng thái **candidate v2**.
- RO full-SoC: 136 cell đầu cuối/128 route tái lập qua hai build sạch.
- PUF-only: 10.000 mẫu một board/điều kiện phòng, HD max 1; chưa tương đương
  image full-SoC và chưa có qualification ASIC.
- ASIC: mới có kiểm tra elaboration và wrapper RO black-box; chưa có bộ đầu vào
  công nghệ hoặc báo cáo synthesis/P&R ASIC được chấp nhận.

Chi tiết bằng chứng tại [PROJECT_STATUS.md](PROJECT_STATUS.md),
[crypto freeze candidate](CRYPTO_RTL_FREEZE_CANDIDATE_2026-09-04.md) và
[báo cáo PUF](PUF_CHARACTERIZATION_2026-09-05.md).

## 3. Phụ thuộc và phần có thể làm song song

Sau khi chốt phạm vi và công nghệ, triển khai hai nhánh công việc:

- Digital: review mật mã → chuẩn hóa reset/memory/interface → synthesis thử →
  kiểm chứng tương đương → freeze RTL cho backend.
- PUF: chốt entropy/root-key policy → same-root/count-margin → thiết kế macro RO
  → mô phỏng PVT/mismatch và layout/PEX macro → chốt views và giao diện.

Có thể chạy synthesis và thử floorplan khối digital trong lúc nghiên cứu PUF.
Trước khi chốt floorplan toàn chip cần biết số/kích thước macro, pin, nguồn,
keep-out, memory và test mode. Các phép đo nhiều chip ASIC chỉ có sau chế tạo;
không đặt chúng làm điều kiện trước lần layout đầu tiên.

## 4. Các pha thực hiện

### P0 — Chốt phạm vi, baseline và bộ công nghệ

Việc thực hiện:

- Review/commit riêng đợt tài liệu đang sửa; tạo nhánh ASIC từ commit tích hợp
  mới nhất đã kiểm tra, giữ nguyên các tag/artifact FPGA cũ.
- Viết đặc tả ngắn: chức năng cuối, top, giao diện, reset/boot, trạng thái khóa,
  phạm vi API ML-KEM, mục tiêu clock/area/power và điều kiện hoạt động.
- Chốt hệ thống chỉ phục vụ demo loopback nội bộ hay phải trao đổi KEM với một
  đối tác ngoài. Khuyến nghị có ít nhất một bài interoperability với phần mềm
  tham chiếu độc lập; nếu cần giao diện public-key/ciphertext ngoài thì thiết kế
  và kiểm tra nó trước freeze. Không bắt buộc nhập private key ngoài.
- Chọn PDK thật được phép dùng, standard-cell library, memory/pad library,
  corner, rule deck, công cụ và giới hạn RAM/CPU. Ghi version/checksum.
- Chốt threat model: tin cậy firmware/bus master tới đâu, có debug/scan không,
  cần chống sửa helper, đọc RAM, fault hoặc side-channel ở mức nào.

Đầu ra đề xuất: `SPEC.md`, `THREAT_MODEL.md`, bảng công nghệ và source commit.

Điều kiện chuyển bước: phạm vi và giả định được Long chốt. Nếu chưa có PDK thì
vẫn làm audit/generic synthesis, nhưng không coi area/timing đó là kết quả ASIC
đích. Nếu có flow của trường/BTC thì ưu tiên flow đó. Một lựa chọn mở để khảo sát
là Yosys/OpenROAD/KLayout; bộ công cụ và các bước được mô tả trong
[hướng dẫn OpenROAD](https://openroad-flow-scripts.readthedocs.io/en/latest/user/UserGuide.html).

### P1 — Chốt yêu cầu mật mã, nguồn randomness và vòng đời khóa

Việc thực hiện:

- Review FIPS 202/203, serialization, padding/domain separation, compare/mux
  implicit rejection và mọi đường reset/lỗi/timeout.
- Ghi phiên bản đặc tả và kiểm tra tác động của errata hiện hành. Trang chính
  thức [FIPS 203](https://csrc.nist.gov/pubs/fips/203/final) có mục errata cần được
  đối chiếu trước khi chốt claim.
- Phân biệt root PUF ổn định với randomness cho KEM. Chốt nguồn d/z/m, nhu cầu
  khóa lâu dài/khóa mỗi phiên, DRBG, reseed, startup/health-test và xử lý lỗi nguồn.
  Cơ chế diversify bằng counter hiện tại chưa đóng yêu cầu này.
- Chốt cách dùng root: trực tiếp dẫn xuất hay bảo vệ một khóa được sinh độc lập.
  Cả hai cần phân tích entropy và khả năng dò khóa; wrapped-key không tự khắc
  phục một root có entropy thấp.
- Review quyền đọc seed/shared secret qua AXI, debug và firmware. Định nghĩa
  vùng khóa, valid bit, policy truy cập và zeroize cả register lẫn memory chứa
  secret, kể cả FE/KDF/seed/các bản sao tạm.
- Chốt policy helper: version, integrity, quyền enroll lại, hành vi sau reset và
  khi restore sai helper/board/phiên bản. Thêm kiểm tra same-root trong môi
  trường qualification; đánh giá thông tin lộ qua bất kỳ tag xác thực nào.

Các thiết kế RBG có thể đối chiếu SP 800-90A/B/C theo phạm vi cần tuyên bố;
[NIST SP 800-90C](https://csrc.nist.gov/News/2025/nist-publishes-sp-800-90c) kết
hợp cơ chế DRBG với entropy source. Việc dùng cấu trúc tham chiếu không tự tạo
chứng nhận cho hệ thống.

Đầu ra: review findings, đặc tả key lifecycle/RBG/helper và danh sách test mới.

Điều kiện chuyển bước: mỗi finding có xử lý hoặc quyết định phạm vi rõ ràng;
người review độc lập thực sự ghi nhận kết quả. Hỗ trợ đọc của các bạn hoặc một
bản rà soát AI không tự được ghi là biên bản đã ký. Chưa gọi crypto freeze cuối
trước khi đóng các mục này và P2/P5 liên quan.

### P2 — Chuẩn hóa RTL cho ASIC

Việc thực hiện:

- Tạo filelist synthesis tường minh với top, defines, parameters và include
  path. Tạo manifest của đúng các file tham gia build, đồng thời giữ manifest
  lịch sử. Không dùng glob toàn `rtl/` hoặc coi manifest 48 file là filelist.
- Phân loại các file legacy không compile; ví dụ `generic_blk_mem.v` có module
  trùng và assignment lỗi, trong khi build hiện dùng wrapper `.sv` khác.
- Thêm top ASIC có `clk_i/rst_ni`, hợp đồng reset/boot rõ; thay phụ thuộc vào
  FPGA power-up initialization trong POR. Review initialization của UART/BCH
  và memory theo chức năng, không xóa máy móc mọi `initial` hoặc reset toàn RAM.
- Kiểm kê memory theo từng instance: width/depth/port/latency/byte enable,
  read-during-write/collision, initialization và cách xóa secret.
- Chọn ROM/bootloader/SRAM cho firmware; chứng minh CPU khởi động từ trạng thái
  reset thật. Tạo adapter memory giữ đúng handshake/latency hoặc cập nhật test.
- Chạy lint nghiêm; giải quyết multiple-driver, implicit net, width, latch,
  loop ngoài ý muốn và reset/X-propagation. Waiver phải theo từng đường/object.
- Lập bảng clock/reset/CDC/RDC. Miền RO dùng clock có thể dừng cần handshake,
  reset release và thời gian giữ dữ liệu rõ; không cắt tất cả timing để đạt PASS.

Đầu ra: top/filelist ASIC, memory map/adapters, lint và clock/reset/CDC reports.

Điều kiện chuyển bước: không có lỗi cấu trúc chưa xử lý hoặc primitive vendor
ngoài whitelist; startup và mọi memory interface có test. Các wrapper/macro
standard cell, SRAM, pad/ESD là phần công nghệ ASIC cần có, kể cả khi logic của
hệ thống được viết bằng RTL và không dùng IP Xilinx sinh tự động.

### P3 — Hoàn thiện kiến trúc và qualification RO-PUF

Việc thực hiện:

- Chốt mức entropy cần có sau helper leakage và tiêu chí root-key failure.
  Với 32 RO hiện tại, mô hình tần số vô hướng cho upper bound
  `log2(32!) ≈ 117,663 bit`; đây không phải min-entropy đo được. 264 bit response
  có challenge lặp và không phải 264 nguồn độc lập.
- Nếu mục tiêu không đạt với kiến trúc này: tăng/thay đổi nguồn vật lý hoặc cơ
  chế trích xuất phù hợp, đánh giá lại tương quan và BCH/helper. Không lấy độ
  dài key FE 192-bit hoặc KDF 512-bit làm entropy được bảo đảm.
- Bổ sung count0/count1, count-margin, tie/zero/stuck detection; kiểm tra
  same-root với reference enroll cố định trên image tích hợp được định danh.
- Nếu instrumentation làm đổi loading/route thì lập baseline qualification mới
  và nêu phạm vi tương đương; không gộp số liệu PUF-only với full-SoC cũ.
- Kiểm thử lỗi có tương quan và theo vị trí, helper corruption, reset giữa
  reconstruct; không yêu cầu BCH phát hiện mọi mẫu lỗi vượt khả năng sửa t=8.
- Theo kế hoạch lab: 10.000 sample/điều kiện phòng, 100 warm reset và 100 cold
  power-cycle; nhiều điểm PVT an toàn, nhiều board, aging. Tối thiểu 5 board,
  ưu tiên 10+ là quy mô thăm dò, không phải ngưỡng chứng nhận.

Đầu ra: quyết định kiến trúc PUF, dữ liệu/metric định danh image và điều kiện,
failure-rate cùng giới hạn thống kê; dữ liệu raw/key/helper thật được giữ theo
chính sách lab. Repo chia sẻ giữ báo cáo đã loại dữ liệu nhận dạng bí mật.

Điều kiện chuyển bước: có kiến trúc/entropy budget và kế hoạch đo được review.
Kết quả FPGA chỉ xác nhận phần FPGA; qualification PUF ASIC tiếp tục ở P4/P8.
Không coi 0 lỗi trong một chuỗi đo là chứng minh xác suất lỗi bằng 0.

### P4 — Macro RO, memory, clock/power và DFT theo PDK

Việc thực hiện:

- Chọn topology/cell/stage/số RO, tải đo và chế độ enable/disable; định nghĩa
  test/bypass và cách điều khiển clock dừng. Contract phải gồm nguồn và pin.
- Mô phỏng SPICE startup/stop, PVT và local mismatch/Monte Carlo khi PDK cung
  cấp model; layout macro, trích parasitic và chạy lại các phép đo sau layout.
- Chốt placement matching, routing/loading, keep-out, nguồn và giảm ảnh hưởng
  hoạt động digital lên RO. Matching không bảo đảm entropy hoặc reliability.
- Cung cấp netlist/SPICE, LEF/GDS và timing/power/behavioral views phù hợp;
  oscillator có semantics riêng, không sign-off tần số RO chỉ bằng STA digital.
- Hoàn thiện memory/pad/power/reset views. Nếu phạm vi là chip độc lập, phải có
  pad ring/ESD và hợp đồng package/pin; nếu là block tích hợp, ghi rõ boundary.
- Chốt DFT trước scan insertion: coverage target, test clock/reset, RO bypass,
  memory test và cách bảo vệ secret qua scan/debug/test mode. Loại secret FF
  khỏi scan một mình chưa chứng minh toàn hệ thống an toàn; đo ảnh hưởng coverage.

Đầu ra: macro package, memory/pad views, DFT plan và kích thước/pin/nguồn cho
floorplan. Nếu thiếu mismatch model, ghi rõ khoảng trống trước silicon.

Điều kiện chuyển bước: không còn black-box thiếu implementation trong phạm vi
layout cuối; RO/memory DRC/LVS và đặc trưng cần thiết có kết quả hoặc waiver
được phép bởi bộ công nghệ. Có thể dùng abstract để thử floorplan trước đó.

### P5 — Synthesis, tương đương và freeze đầu vào backend

Việc thực hiện:

- Synthesis từng khối rồi toàn hệ thống bằng filelist/libs đã pin; kiểm tra cell,
  RAM/ROM mapping, black-box whitelist, latch, fanout, area và timing.
- Viết SDC và cấu hình nhiều mode/corner: functional/test, IO delay, uncertainty,
  reset và miền RO. Mốc 50 MHz là mục tiêu ban đầu; 100 MHz là phép khảo sát có
  kết quả riêng. Không chuyển kết luận Fmax FPGA trực tiếp sang ASIC.
- Chạy equivalence RTL ↔ netlist với giả định reset/memory/macro có tài liệu;
  bổ sung gate-level KAT và smoke test boot/reset/UART. Mô phỏng netlist không
  thay thế toàn bộ equivalence, và equivalence digital không chứng minh RO analog.
- Kiểm tra netlist sau DFT/ECO; full-system test bao phủ valid, invalid,
  backpressure, timeout, reset và policy zeroize đã chốt.
- Chạy lại crypto/full-system regression trên tree sạch, lập biên bản review và
  tạo tag/manifest mới cho RTL chức năng cùng handoff công nghệ.

Đầu ra: netlist, SDC, synthesis/STA/equivalence/test reports và freeze tag.

Điều kiện chuyển bước: không có finding ảnh hưởng chức năng/bảo mật chưa đóng;
macro/memory/interface phù hợp đặc tả, không timing endpoint bị bỏ quên. Nếu
chỉ thay adapter ASIC thì kiểm tra nền ASIC tương ứng; build lại FPGA khi source
dùng chung hoặc baseline FPGA bị ảnh hưởng.

### P6 — Physical design toàn hệ thống

Việc thực hiện:

- Floorplan theo kích thước RO/memory/pad đã chốt; dự trù routing, nguồn và test.
- Power grid, placement, clock-tree synthesis, tối ưu setup/hold và route.
- Giữ boundary RO và quy tắc pin/loading đã được characterize; không để CTS
  hoặc tối ưu logic thường sửa topology vòng RO ngoài contract.
- Theo dõi congestion, clock skew, transition/capacitance/fanout, timing và
  nguồn qua từng checkpoint. Đối chiếu netlist/equivalence sau ECO.

Đầu ra: checkpoint/DEF, netlist sau route, parasitics và report từng bước.

Điều kiện chuyển bước: route hoàn tất, nguồn kết nối đúng, timing đạt mục tiêu
ở các mode/corner đã chọn; các thay đổi tác động RO được characterize lại.

### P7 — Sign-off trước chế tạo và gói bàn giao M2

Việc thực hiện:

- STA sau extraction cho setup/hold, recovery/removal và mode/corner cần thiết;
  review mọi exception và clock không được STA thông thường xử lý.
- DRC/LVS bằng deck đúng PDK, ERC/connectivity, antenna và density/fill; chạy lại
  phép kiểm tra chịu ảnh hưởng sau fill/ECO. Ghi rõ phạm vi/tool của sign-off.
- Đánh giá power/IR-drop/EM theo activity và góc hoạt động đã định; nguồn RO có
  biên riêng. Báo cáo switching model, tránh coi estimate là power đã đo.
- Chốt netlist/RTL equivalence và gate-level regression; đóng review
  CDC/RDC/reset, DFT coverage và security findings thuộc phạm vi.
- Đóng gói GDS, netlist, SDC/MMMC, macro views, SPEF và report, source manifest,
  tool/PDK version, firmware, hướng dẫn tái tạo và known limitations.
- Kiểm tra quyền chia sẻ theo từng artifact. PDK/library hạn chế phân phối
  không đưa vào Git chỉ vì script cần đọc chúng.

Điều kiện đạt M2: mọi kiểm tra bắt buộc của PDK/phạm vi PASS hoặc có waiver
chính thức được chấp nhận; full-system không chứa RO/memory placeholder chưa
triển khai. Một file GDS tạo được chưa đủ điều kiện này.

### P8 — Chế tạo, bring-up và qualification silicon M3

Việc thực hiện:

- Chốt tapeout/package/test board, lịch chế tạo và số chip mẫu; đây là phần
  phụ thuộc bên ngoài cần ngân sách và dịch vụ phù hợp.
- Bring-up nguồn/reset/clock/boot/test mode, UART/control, memory và từng khối.
- Chạy KAT/negative/interoperability/full-system trên chip; đo performance và
  power thực tế so với dự đoán.
- Enroll từng chip và đo same-root/FE failure ở nhiều chip, warm/cold boot,
  temperature/voltage và thời gian; ước lượng uniqueness, entropy và helper
  leakage theo mô hình đã chốt.
- Kiểm tra debug/scan lock, zeroize, fault/side-channel theo threat model.
  Nếu kết quả buộc đổi kiến trúc, ghi revision và kế hoạch respin.

Điều kiện đạt M3: có chip và dữ liệu chứng minh các chỉ tiêu đã cam kết; công bố
đúng số chip, điều kiện đo, độ tin cậy và giới hạn còn lại.

## 5. Việc ưu tiên trong đợt triển khai đầu

1. Lưu baseline tài liệu và chốt M2 là đích trước mắt, M3 là bước sau chế tạo.
2. Xác nhận PDK/tool/library được cấp và phần cứng máy chạy; chốt scope/API.
3. Tạo filelist ASIC, audit các file thật sự compile, reset và memory inventory.
4. Review entropy/RBG/key lifecycle, chọn phương án trước khi sửa crypto RTL.
5. Tạo top/reset và lint gate đúng nghĩa; synthesis thử khối crypto khi đầu vào
   công nghệ sẵn sàng, đồng thời thiết kế phép đo same-root/RO macro.

Đầu ra đợt đầu là danh sách finding có thể tái hiện, dự toán area/timing ban đầu
và các quyết định kiến trúc cần chốt. Sau đó mới ước lượng lịch P&R toàn chip.

## 6. Quản lý tiến độ và tài nguyên

- Long điều phối và thực hiện. Đạt/Tùng/Minh/Việt Anh hỗ trợ đúng phần đã phân;
  không đặt tên họ vào biên bản review đã hoàn tất khi họ chưa review thực tế.
- Chạy một job nặng tại một thời điểm, đo RAM/runtime của từng khối trước khi
  mở full-chip. Lưu checkpoint để tiếp tục khi máy hoặc công cụ bị gián đoạn.
- Mỗi pha ghi input commit/config/hash, lệnh, kết quả, findings, người kiểm tra
  và điều kiện chuyển bước. Dữ liệu kỳ vọng không được sửa để ép test PASS.
- Sau freeze, thay đổi RTL do bug/security/ASIC blocker phải có lý do, regression
  liên quan và tag mới; baseline FPGA và tag freeze cũ giữ bất biến.
- Chưa chốt ngày hoàn thành trước khi có PDK, macro/memory và synthesis thử.
  PUF physical, dữ liệu nhiều chip và lịch chế tạo là các rủi ro thời gian lớn.
- Waveform trình bày/video demo tiếp tục được hoãn trong lịch kỹ thuật; đưa
  trở lại khi chuẩn bị hồ sơ nộp thi, tách khỏi các bằng chứng sign-off.

## 7. Các trường hợp phải mở lại kế hoạch

| Phát hiện | Hành động |
|---|---|
| Entropy/root stability không đạt | Quay lại P1/P3, sửa kiến trúc/claim và cập nhật macro/FE |
| Synthesis không fit hoặc không timing | Phân tích memory/critical path trước, đề xuất đổi RTL có kiểm soát |
| API đối tác ngoài khác API nội bộ | Mở lại đặc tả, thêm validation/interoperability tests trước freeze |
| Macro thay pin/kích thước/nguồn/loading | Mở lại floorplan và characterization chịu ảnh hưởng |
| Lỗi sau DFT hoặc ECO | Review mapping/equivalence, chạy lại các gate bị ảnh hưởng |
| PDK thiếu model/deck bắt buộc | Ghi mức kết quả nghiên cứu và đầu vào thiếu, chưa ghi sign-off chế tạo |
| Silicon khác mô phỏng | Đo nguyên nhân, cập nhật model/kiến trúc và lập revision/respin |
