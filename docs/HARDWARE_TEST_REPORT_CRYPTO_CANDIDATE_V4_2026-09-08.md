# Báo cáo board regression crypto candidate v4 — 2026-09-08

## Kết luận

Đúng bitstream candidate v4 tại source
`5943cebd79738c12e21dbe79210ff821d1776d78` đã **PASS JTAG, INFO, enroll,
reconstruct và stress 10.000/10.000** trên board XC7Z020. Firmware release giữ
shared secret bên trong và chạy crypto-accelerator zeroize. Không có timeout,
retry hay giao dịch lỗi trong các campaign đã chạy.

## Định danh

- JTAG: một target Digilent `260515110006`, device `xc7z020_1`.
- UART: CH340 `/dev/serial/by-id/usb-1a86_USB_Serial-if00-port0`, 115.200 8N1.
- Bitstream:
  `build/soc_repro/candidate_v4_final/kyber_ro_puf_candidate_v4_final.runs/impl_1/Kyber_System_Top.bit`.
- SHA-256 bitstream:
  `bc3a8ab8cac94c00ad3f02f5c3165ff9f8bbacf13db7ba0952003bb90946260a`.
- Nạp volatile PL qua JTAG; không ghi QSPI.
- Protocol/capability: 1.3 / `0x06`.

Helper được giữ ở `/tmp` và không commit. Báo cáo không lưu helper, raw PUF
response hay shared secret gắn với board.

## Kết quả

| Bước | Kết quả |
|---|---|
| Nhận đúng một XC7Z020 và nạp bitstream | PASS, DONE HIGH |
| INFO | PASS, protocol 1.3/capability `0x06` |
| Shared-secret export | Disabled (release) |
| Session diversification | Enabled |
| Crypto-accelerator zeroize | Enabled |
| Legacy retry | Disabled |
| Enroll | PASS, helper 33 byte |
| Reconstruct ban đầu | PASS, marker `ABCDEFG`, Server/Client match |
| Stress 100 | 100/100, fail 0, 29,688 ms/giao dịch |
| Stress 1.000 | 1.000/1.000, fail 0, 29,721 ms/giao dịch |
| Stress 10.000 | 10.000/10.000, fail 0, 296,942 s |
| Latency/throughput run dài | 29,694 ms; 33,677 giao dịch/s |

Mỗi lệnh stress thực hiện enroll mới trước chuỗi reconstruct. Khi kết thúc,
board vẫn đang chạy candidate v4 volatile; power-cycle sẽ làm mất cấu hình PL.
Artifact RC1 ở root không bị sửa.

## Phạm vi chứng minh

Campaign chứng minh đúng image v4 hoạt động end-to-end tại điều kiện phòng của
một board trong một phiên: RO-PUF → fuzzy extractor → KDF → ML-KEM-512, giao
thức release và accelerator-zeroize. Nó không chứng minh same-root trực tiếp,
entropy, uniqueness, cold/warm power-cycle, điện áp/nhiệt độ, aging, nhiều
board, side-channel/fault-injection hoặc zeroize toàn SoC.

## Quyết định

Đúng-image board gate của crypto candidate v4 là **PASS**. Candidate đủ bằng
chứng kỹ thuật do implementation owner thực hiện để chuyển sang review độc lập
và cân nhắc freeze nội bộ. Production/public release vẫn NO-GO cho đến khi đóng
license, review bảo mật/mật mã và qualification PUF.
