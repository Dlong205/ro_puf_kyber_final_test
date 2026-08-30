# Báo cáo test phần cứng — 2026-08-28

## Thiết bị và bản build

- Thiết bị: XC7Z020-2CLG400I
- Vivado: 2020.1
- Kiến trúc: chỉ PL, pure RTL, không Xilinx IP sinh tự động
- Clock: clock PL ngoài 50 MHz tại N18
- JTAG: Digilent FT232H, serial `260515110006`
- UART: CH340 tại `/dev/ttyUSB0`, 115200 8N1
- SHA-256 bitstream:
  `a34ce0e820185140f0d0bc89222a3039fd22f46abf6f57ac906199d1a55bda39`

## Xác nhận implementation

| Kiểm tra | Kết quả |
|---|---:|
| Synthesis | PASS |
| Place và route | PASS |
| Net chưa route/route một phần | 0/0 |
| Lỗi DRC | 0 |
| Setup timing | WNS +2.586 ns, TNS 0 ns |
| Hold timing | WHS +0.058 ns, THS 0 ns |
| Tài nguyên LUT | 51.778/53.200 (97,33%) |

## Kết quả trên board

| Bài test | Kết quả |
|---|---:|
| Nạp JTAG volatile và DONE=HIGH | PASS |
| PUF enroll và thu 33 byte helper | PASS |
| Nạp lại FPGA, reconstruct bằng helper đã lưu | PASS |
| BCH fuzzy extractor | PASS |
| SHAKE256 KDF hoàn thành | PASS |
| Shared secret server/client Kyber-512 khớp | PASS |
| 100 vòng hoàn chỉnh liên tiếp | 100/100 PASS |
| 10.000 vòng hoàn chỉnh liên tiếp | 10.000/10.000 PASS |

`hardware_helper.bin` là helper 33 byte công khai lấy từ board test. Nó gắn với
board/lần enroll và không phải secret key được tái tạo.

## Vấn đề bring-up đã phát hiện và sửa

Lần reconstruct đầu dùng helper capture chứa ba byte UART cũ phát ra quanh lúc
FPGA startup. BCH đã từ chối đúng helper bị hỏng sau marker `ABC`. Host utility
được sửa để đợi 100 ms, xả byte USB-UART đến muộn trước khi gửi command và nhận
biết sớm `STATUS_FAIL` đúng giai đoạn. Enroll, nạp lại/reconstruct, 100 vòng và
10.000 vòng đều PASS sau sửa đổi phía host.

## Qualification còn thiếu

Run này chứng minh hoạt động chức năng trên một board trong một điều kiện nguồn
và nhiệt độ liên tục. Nó chưa chứng minh độ tin cậy RO-PUF cho production.

1. Reconstruct từ helper đã lưu sau nhiều lần tắt/bật nguồn vật lý.
2. Đo failure rate tại điện áp nguồn minimum/nominal/maximum dự kiến.
3. Đo hoạt động lạnh, môi trường và nóng trong dải nhiệt độ dự kiến.
4. Test nhiều board để đo uniqueness và Hamming distance giữa thiết bị.
5. Reset giữa các thao tác PUF, BCH, KDF và Kyber trên hardware.
6. Review hoặc loại bỏ 28 warning reset-bất-đồng-bộ tới BRAM trước sign-off production.
