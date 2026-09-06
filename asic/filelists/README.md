# Filelist ASIC chuẩn

Các file `.f` dùng đường dẫn tương đối từ thư mục gốc repository, mỗi dòng là
một source RTL và thứ tự dòng là thứ tự đọc source. Không dùng glob để tránh
vô tình đưa file legacy hoặc primitive FPGA vào synthesis.

| Filelist | Top/khối đích | Define bắt buộc |
|---|---|---|
| `system_asic.f` | `Kyber_System_Asic_Top` | `KP_TARGET_ASIC` |
| `mlkem_accelerator.f` | `kyber_axi_wrapper` | không có |
| `fips202_core.f` | `fips202_sponge` | không có |

`include_dirs.txt` liệt kê include path; `include_files.txt` khóa tường minh mọi
header `.vh/.svh` được source full-system include. Gate so dependency record của
Verilator với hai danh sách này để phát hiện module/header bị auto-load ngầm.
`legacy_exclusions.txt` là deny-list:
những file này được giữ để truy vết lịch sử/FPGA nhưng không được đọc trong
build ASIC. Đặc biệt, `rtl/common/generic_blk_mem.v` có module trùng, tự drive
input và tham chiếu tín hiệu không khai báo; manifest crypto cũ chứa file đó để
khóa lịch sử nhưng nó không phải compile filelist.

Kiểm tra filelist bằng:

```sh
make -j1 asic-filelist-check
```
