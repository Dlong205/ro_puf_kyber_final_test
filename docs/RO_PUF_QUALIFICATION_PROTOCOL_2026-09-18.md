# Protocol đo và qualification RO-PUF — giai đoạn 2026-09-18

Phạm vi giai đoạn này: **một board Zynq-7020** (`XC7Z020CLG400-2`) làm target
chính. Hai Arty-35T được **hoãn** sang giai đoạn validation mở rộng. Mục tiêu
là chọn `mapping_tag` khác 0 cho demo Zynq sau khi mapping vượt holdout — không
tuyên bố generalization giữa nhiều thiết bị hay inter-device uniqueness.

## 1. Phương pháp đo đã chốt

- **Board duy nhất**: `board_id` cố định `ZYNQ-A01` (mã giả, không dùng serial
  thật). Gán nhãn vật lý trên board khớp `board_id`; sổ lab ghi serial/điều kiện
  **ngoài repository**.
- **Image đo**: `Puf_AllPairs_Characterization_Top`, giao thức **2.0**, cửa sổ
  đo **`REF_CYCLES = 255`** chu kỳ RO, clock **100 MHz** (`CLK100MHZ`), schedule
  496 cặp không thứ tự duy nhất `(a,b), 0 <= a < b < 32` — khác release LFSR nên
  **không còn 9 challenge lặp**.
- **Khóa vật lý**: image phải dùng cùng 128 LOC/BEL map RC1
  (`ro_placement_rc1_zynq7020.xdc`) **và** full lock mới gồm `FIXED_ROUTE` +
  `LOCK_PINS` + `DONT_TOUCH` xuất từ routed DCP đã chấp nhận
  (`ro_physical_lock_allpairs_zynq7020.xdc`) + fingerprint tsv. Rebuild phải cho
  fingerprint khớp và **bitstream có giá trị SHA-256 khóa lại** (xem
  `RO_PUF_QUALIFICATION_LOCK_2026-09-18.md` gắn kèm runbook build).
- **Power-cycle là đơn vị phân chia**: mỗi lần bật nguồn là **một boot session
  nguyên vẹn** (`boot_index`). Không bao giờ tách frame của cùng một lần bật
  nguồn sang cả train và holdout.

## 2. Nhận dạng và metadata mỗi campaign

Mỗi file report private phải có `campaign` đầy đủ:

| Trường | Nguồn | Bắt buộc |
|---|---|---|
| `board_id` | tham số CLI | có |
| `boot_index` | số lần bật nguồn tăng dần | có |
| `condition_id` | nhãn điều kiện (vd `room-coldboot-041`) | có |
| `local_bitstream_sha256` | SHA-256 file `.bit` tại máy đo | có |
| `build_commit` | `git rev-parse HEAD` tại thời điểm build | có |
| `build_datetime` | UTC lúc build | có |
| `placement_fingerprint_sha256` | SHA-256 file fingerprint tsv của image | có |
| `protocol`, `ref_cycles`, `target_part`, `top` | hằng số giao thức | có |
| nhiệt độ/điện áp | sổ lab riêng | ngoài Git |

Host từ chối campaign nếu thiếu `boot_index`, thiếu fingerprint hoặc
`local_bitstream_sha256` lệch image đang nạp. Frame hỏng (index sai, reserved
bit bật, winner/margin bug) bị loại theo kiểm tra hiện có trong
`host/puf_allpairs_characterize.py`.

## 3. Chia train/holdout theo power-cycle

- **Train**: các boot session độc lập đầu tiên, vd `boot_index` 1..N_tr, mỗi
  session một lần bật nguồn riêng, số frame đủ thống kê per-pair (xem mục 5).
- **Holdout**: các boot session **khác power-cycle/khác ngày đo**, sau khi
  danh sách train đã đóng: `boot_index` N_tr+1..N_tot và không dùng chung session.
- Tool `host/puf_mapping_train.py` ở chế độ `--session-split` **từ chối** nếu một
  `boot_index` xuất hiện ở cả hai tập; mọi campaign phải có `board_id` xác định
  và `boot_index` số. Bitstream SHA-256 phải đồng nhất mọi campaign.
- 264 cặp được chọn **chỉ từ train**. Holdout không tham gia chọn; holdout chỉ
  được phép làm mapping trượt gate.

## 4. Chọn 264 cặp từ pool 496

Tiêu chí (mặc định, có thể siết thêm):

- `margin p01 >= 4` trên mọi session train;
- `minority_rate_percent <= 1%`;
- `tie_count == 0`;
- mỗi RO dùng tối đa 17 lần trong 264 vị trí;
- ưu tiên margin thấp kém ổn định khi cự ly dùng RO cân bằng.

Vì schedule allpairs là cặp duy nhất nên không còn bài toán challenge trùng.
`mapping_tag` giữ nguyên `0` trong toàn bộ khảo sát; chỉ tạo
`mapping_tag`/version khác 0 sau khi mapping vượt holdout và được freeze cho
demo Zynq (`zymq7020_mapping_v1`, kèm hash manifest → `helper_record_spec`).

## 4bis. P2.5 — Đánh giá cấu trúc/entropy, cổng song song với holdout

496 response không phải 496 bit độc lập: mọi cặp chỉ so cùng 32 tần số RO, nên
một thiết bị ổn định sinh gần đúng **một thứ tự toàn phần của 32 RO**. Trần
entropy của bất kỳ mapping nào lấy từ pool này là `log2(32!) ≈ 117,7 bit`;
264 bit của FE là **độ dài từ mã, không phải entropy** — vẫn dưới mục tiêu
128 bit của ML-KEM-512 trước cả tổn thất do bias/selection. KDF không tạo ra
entropy thêm.

Trước khi freeze `mapping_tag`, mọi campaign thu được phải đi kèm đánh giá
cấu trúc (`assess_order_structure`, nhúng trong `puf_allpairs_characterize.py`):

1. **Ma trận tương quan**: phép đo phi trên mẫu cặp response (winner bit) qua
   các frame; nhận diện cặp liên kết chặt (gần 1) và trục ổn định cấu trúc.
2. **Tính bắc cầu/cycle**: trên mỗi frame, tỷ lệ 3-cycle trên
   `C(32,3) = 4960` bộ ba; frame 0-cycle ⇒ đúng một thứ tự toàn phần
   (mô hình 32! state) ⇒ số bit độc lập thực tế ≤ `log2(32!)`.
3. **Bias từng challenge**: tỷ lệ minority (gần 50% = kém phân biệt) và gate
   chọn hiện tại (minority_rate ≤ 1%) siết chặt bias này.
4. **Chọn theo nhiều chiều**: không chỉ margin — cân nhắc reliability, tính
   cân bằng RO và tương quan khi chọn 264 từ train.
5. **Entropy có điều kiện**: ước lượng entropy còn lại sau khi helper data và
   mapping là công khai — cần phân tích riêng với tập thiết bị và mô hình
   helper; đánh giá phase này chỉ là **sàng lọc cấu trúc**, không phải bộ ước
   lượng entropy hoàn chỉnh.

Hướng mở rộng nếu cần đạt trần ≥ 128 bit:

- **Trung thực trong báo cáo** (ngắn hạn): giữ 32 RO nhưng công bố rõ
  `264 = FE length`, trần ≈ 117,7 bit, tính chất device này dựa trên thứ tự
  toàn phần;
- tăng số RO (≥ ~35 nếu chỉ dựa thứ tự);
- dùng challenge thay đổi đường dao động thực sự thay vì thêm cặp so sánh
  cùng 32 RO;
- kết hợp các nhóm RO độc lập.

**Freeze `mapping_tag` chỉ sau khi CẢ reliability (holdout BER) LẪN entropy
đều có kết luận**: manifest chỉ set `entropy_screened = true` khi mọi campaign
train+holdout mang block `assessment`; nếu chưa đủ, manifest ghi rõ phần còn
thiếu thay vì tự nhận đạt.

## 5. Quy mô đo tối thiểu và phân bổ

Sizing phụ thuộc tài nguyên thời gian trên lab; khung bắt buộc:

| Tập | Tối thiểu | Gợi ý |
|---|---:|---:|
| Train — số boot session | 15 | 30 boot độc lập |
| Train — frame/session | 200 | 500 |
| Holdout — số boot session | 8 trên ≥ 2 ngày | 15 trên ≥ 3 ngày |
| Holdout — frame/session | 200 | 500 |

Mỗi frame 496 record × 16 B @115200 ≈ 0,7 s; 500 frame ≈ 6–7 phút/session.
Nếu per-pair `p01` cần độ tin cậy cao hơn, ưu tiên tăng session train thay vì
frame/session để cover thay đổi theo power-cycle.

## 6. Metric và cổng đánh giá

Từ holdout (sau khi mapping cố định):

- margin `p01` per selected pair trên holdout;
- BER per bít và per vector 264 bít;
- số lỗi trên mỗi vector; phân vị và max;
- **tỷ lệ vector có `errors > 8`** → so với BCH `t=8`;
- hamming distance intra-device (reference enroll cùng đối tượng);
- **chưa** tính inter-device HD vì giai đoạn này chỉ có 1 Zynq — ghi rõ trong
  báo cáo.

Cổng demo Zynq: 100% vector holdout có `errors <= 8`; tỷ lệ sai vượt khả năng
BCH bằng 0 trong tập thử mục tiêu; biên 9 lỗi được test và đo false-reject.
Bổ sung: cổng freeze chỉ đóng khi **holdout BER đạt VÀ entropy đã sàng lọc**
(mọi campaign có `assessment`; manifest `entropy_screened = true`) — xem
section 4bis.

## 7. Storage và quyền

- Raw report đầy đủ per-pair, response, helper và fingerprint device:
  `reports/puf_allpairs_characterization/private_<BOARD>_<boot>_<cond>.json`,
  đã nằm trong `.gitignore`; **không commit**.
- Manifest mapping công khai (chỉ lịch cặp + metadata, không fingerprint device)
  tại `reports/puf_mapping/zymq7020_mapping_v1.json`.
- Sổ lab (nhiệt độ/điện áp/serial) nằm **ngoài repository**.
- Báo cáo công khai chỉ giữ số aggregate không đủ tái tạo fingerprint.

## 8. Báo cáo cần viết ở cuối giai đoạn

1. Bitstream lock + fingerprint + reproducibility (2 build sạch).
2. Train/holdout split (số session/ngày, disjoint power-cycle).
3. Margin/BER/errors-per-vector trên holdout; đối chiếu BCH `t=8`.
4. Kết quả P2.5: tỷ lệ cycle/bắc cầu, phi-correlation, bias, trần
   `log2(32!) ≈ 117,7 bit`; khẳng định rõ **264 = FE length không phải entropy
   và entropy có điều kiện sau helper công khai cần phân tích riêng**.
5. Manifest mapping + `mapping_tag` + ghi chú "**chưa đánh giá inter-device
   uniqueness và generalization thiết bị khác vì chỉ dùng một Zynq**".
6. End-to-end board: `RO-PUF → FE → KCV → KDF → ML-KEM-512` trên từng trường
   hợp (enroll→reconstruct cùng board, power-cycle rồi reconstruct, helper sai
   board/bị sửa, reset giữa chừng, noise >8) và thống kê nhiều phiên.