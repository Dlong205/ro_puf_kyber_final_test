# Quy trình chọn mapping reliability-aware cho RO-PUF

Trạng thái **2026-09-17**: tooling và unit test đã hoàn thành; mapping dùng cho
release **chưa được chọn** vì mới có dữ liệu từ một board. Quy trình này chọn
264 cặp từ pool `C(32,2)=496` bằng tập training và chỉ đánh giá sau đó trên các
board holdout độc lập.

## Mục tiêu và ranh giới

Mapping nhằm loại các cặp RO có margin thấp, tie hoặc dao động và cân bằng số
lần sử dụng 32 RO. Nó không tự tạo ra 264 bit entropy độc lập. Tất cả phép so
sánh vẫn bắt nguồn từ 32 tần số RO; kiểm tra correlation, ước lượng entropy,
helper/KCV binding và phép đo tích hợp PUF→BCH là các cổng riêng.

Một manifest đạt cổng trong tài liệu này chỉ có trạng thái
`reliability-qualified-candidate`. Trường `puf_freeze_eligible` luôn là
`false`; không được dùng riêng manifest để tuyên bố freeze hay production
security.

## Chia dữ liệu bắt buộc

- Tối thiểu 3 board training và 2 board holdout; các board phải khác nhau.
- Nên dùng 10 board trở lên khi có điều kiện và giữ cố định phép chia trước khi
  xem kết quả holdout.
- Mọi campaign trong một lần chọn mapping phải dùng cùng bitstream
  characterization, được nhận diện bằng SHA-256.
- `board_id` là mã giả ổn định, ví dụ `ZYNQ-A03`; không dùng serial thật hoặc
  thông tin nhận dạng cá nhân.
- `condition_id` mô tả điều kiện, ví dụ `room-coldboot-001`. Ghi nhiệt độ và
  điện áp trong sổ lab riêng khi có thiết bị đo.
- Không dùng cùng một board ở cả training và holdout. Tool sẽ từ chối trường
  hợp này, kể cả khi file hoặc điều kiện khác nhau.

Raw report, count theo cặp, response, helper và private audit là fingerprint
thiết bị. Chúng phải nằm trong đường dẫn `private_*.json` đã bị `.gitignore` và
không được commit lên repository công khai.

## Thu thập campaign

Sau khi nạp đúng image all-pairs protocol 2.0, chạy riêng cho từng boot/điều
kiện:

```sh
make -j1 puf-allpairs-characterize \
  PUF_SAMPLES=1000 \
  PUF_BOARD_ID=ZYNQ-A01 \
  PUF_CONDITION_ID=room-coldboot-001 \
  PUF_ALLPAIRS_REPORT=reports/puf_allpairs_characterization/private_ZYNQ-A01_room-coldboot-001.json
```

Không trộn báo cáo tạo bởi hai bitstream khác nhau. Giữ file `.bit` và SHA-256
tương ứng trong hồ sơ lab, rồi nạp lại image release sau khi đo xong.

## Chọn và kiểm tra holdout

Ví dụ tạo manifest ứng viên:

```sh
make -j1 puf-mapping-train \
  PUF_MAPPING_TRAINING="reports/puf_allpairs_characterization/private_A01.json reports/puf_allpairs_characterization/private_A02.json reports/puf_allpairs_characterization/private_A03.json" \
  PUF_MAPPING_HOLDOUT="reports/puf_allpairs_characterization/private_H01.json reports/puf_allpairs_characterization/private_H02.json" \
  PUF_MAPPING_VERSION=zynq-map-v1 \
  PUF_MAPPING_MANIFEST=reports/puf_mapping/zynq-map-v1.json
```

Mặc định, một cặp chỉ đủ điều kiện training khi:

- `margin p01 >= 4` trên mọi campaign training;
- minority rate không quá 1%;
- không có tie;
- mỗi RO được dùng tối đa 17 lần trong 264 vị trí.

Thuật toán chỉ dùng training để chọn cặp. Holdout không thay đổi danh sách đã
chọn; nó chỉ có quyền làm ứng viên thất bại. Tool cũng từ chối báo cáo thiếu
ID, hai tập dùng chung board, file lặp hoặc SHA-256 bitstream không đồng nhất.

Để pipeline tự thất bại nếu chưa đạt tối thiểu 3+2 board hoặc có lỗi holdout,
chạy trực tiếp:

```sh
python3 host/puf_mapping_train.py \
  --training TRAINING_REPORTS... \
  --holdout HOLDOUT_REPORTS... \
  --version zynq-map-v1 \
  --manifest reports/puf_mapping/zynq-map-v1.json \
  --private-audit reports/puf_mapping/private_zynq-map-v1_audit.json \
  --require-reliability-qualified
```

Manifest công khai chứa lịch cặp, version, tiêu chí, hash bitstream, hash các
input report và `manifest_sha256`. Private audit chứa board ID và chi tiết lỗi
holdout, do đó không được commit.

## Kết quả hiện có

Campaign 100 mẫu ngày 2026-09-16 trên một Zynq chọn được 264/264 cặp với degree
16–17, nhưng khi đưa qua đúng workflow mới chỉ nhận trạng thái `provisional`:

- training board: 1;
- holdout board: 0;
- `reliability_qualified=false`;
- `puf_freeze_eligible=false`.

Kết quả này chứng minh tool không tự nâng một-board preview thành mapping
release. Không có manifest provisional từ fingerprint board được commit.

## Cổng sau mapping

Sau khi một mapping vượt holdout, vẫn phải hoàn thành theo thứ tự:

1. review correlation trên chuỗi response per-sample và bit-alias nhiều board;
2. tích hợp mapping cố định, version/hash vào RTL và helper metadata;
3. từ chối helper sai mapping/version và bổ sung KCV hoặc cơ chế same-root;
4. đo raw error và số lỗi BCH sửa với helper cố định qua warm/cold boot và PVT;
5. đánh giá entropy/helper leakage và review CDC/RDC;
6. chỉ freeze RO-PUF khi toàn bộ gate trong `PUF_QUALIFICATION_PLAN.md` đạt.
