# Chỉ mục tài liệu

Bằng chứng đến **2026-09-05**, tài liệu đồng bộ **2026-09-06** cho integration
`0.2.0-rc2-dev`. Artifact FPGA được
chấp nhận vẫn là ML-KEM-512 `0.2.0-rc1`; các tài liệu sau RC1 bổ sung
characterization và physical route-lock.

## Tài liệu trạng thái hiện hành

| Cần biết | Tài liệu chuẩn |
|---|---|
| Dự án đang ở bước nào | [`PROJECT_STATUS.md`](PROJECT_STATUS.md) |
| Lộ trình hoàn thiện toàn hệ thống đến ASIC và silicon | [`KE_HOACH_HOAN_THIEN_ASIC.md`](KE_HOACH_HOAN_THIEN_ASIC.md) |
| Có thể phát hành ở mức nào | [`RELEASE_READINESS.md`](RELEASE_READINESS.md) |
| Xác minh FIPS 202 | [`FIPS202_VERIFICATION_2026-09-03.md`](FIPS202_VERIFICATION_2026-09-03.md) |
| Xác minh ML-KEM/FIPS 203 | [`FIPS203_VERIFICATION_2026-09-04.md`](FIPS203_VERIFICATION_2026-09-04.md) |
| Crypto freeze candidate | [`CRYPTO_RTL_FREEZE_CANDIDATE_2026-09-04.md`](CRYPTO_RTL_FREEZE_CANDIDATE_2026-09-04.md) |
| Kết quả FPGA ML-KEM RC1 | [`HARDWARE_TEST_REPORT_MLKEM_CANDIDATE_2026-09-04.md`](HARDWARE_TEST_REPORT_MLKEM_CANDIDATE_2026-09-04.md) |
| Characterization RO-PUF | [`PUF_CHARACTERIZATION_2026-09-05.md`](PUF_CHARACTERIZATION_2026-09-05.md) |
| Kế hoạch qualification RO-PUF | [`PUF_QUALIFICATION_PLAN.md`](PUF_QUALIFICATION_PLAN.md) |
| Tái lập placement/routing RO | [`RO_PHYSICAL_REPRODUCIBILITY_2026-09-05.md`](RO_PHYSICAL_REPRODUCIBILITY_2026-09-05.md) |
| Ranh giới FPGA → ASIC | [`ASIC_PORTABILITY.md`](ASIC_PORTABILITY.md) |
| Nạp và test board | [`HARDWARE_BRINGUP.md`](HARDWARE_BRINGUP.md) |
| Giao thức UART revision 1.2 | [`UART_PROTOCOL_V1.md`](UART_PROTOCOL_V1.md) |
| Nguồn gốc và license | [`PROVENANCE.md`](PROVENANCE.md), [`../NOTICE.md`](../NOTICE.md) |

## Cách đọc trạng thái

- **PASS/DONE functional**: bài test trong phạm vi ghi rõ đã đạt; không đồng
  nghĩa chứng nhận FIPS hoặc production security.
- **CONDITIONAL**: bằng chứng chính đã có nhưng còn một gate bắt buộc.
- **NO-GO/CHƯA**: không được dùng để tuyên bố freeze/release ở mức đó.
- Báo cáo Markdown về board ghi lại campaign đã chạy nhưng chưa phải log CI
  machine-readable. Artifact/hash/fingerprint và vector test mới là phần có thể
  kiểm lại trực tiếp từ repo.

## Báo cáo lịch sử

Các file dưới đây được giữ nguyên để truy vết lỗi và tiến bộ; không dùng chúng
thay cho `PROJECT_STATUS.md`:

- [`HARDWARE_TEST_REPORT_2026-08-28.md`](HARDWARE_TEST_REPORT_2026-08-28.md)
- [`HARDWARE_TEST_REPORT_RC1_2026-08-30.md`](HARDWARE_TEST_REPORT_RC1_2026-08-30.md)
- [`HARDWARE_TEST_REPORT_RC2_2026-08-30.md`](HARDWARE_TEST_REPORT_RC2_2026-08-30.md)
- [`HARDWARE_TEST_REPORT_RC3_2026-08-30.md`](HARDWARE_TEST_REPORT_RC3_2026-08-30.md)
- [`HARDWARE_TEST_REPORT_RC4_2026-09-03.md`](HARDWARE_TEST_REPORT_RC4_2026-09-03.md)
- [`VERIFICATION_REPORT_2026-08-30.md`](VERIFICATION_REPORT_2026-08-30.md)

## Quy tắc cập nhật

1. Không sửa lại số liệu lịch sử để làm nó giống candidate mới.
2. Cập nhật `PROJECT_STATUS.md`, `RELEASE_READINESS.md`, README chính và
   `phan_cong_nhom/` khi một gate thay đổi.
3. Ghi rõ source commit, tag artifact và nhánh tích hợp; ba khái niệm này không
   được dùng thay thế nhau.
4. Khi thay RTL/constraint/firmware hoặc artifact, chạy lại đúng gate liên quan
   và cập nhật checksum/report trước khi đổi trạng thái.
