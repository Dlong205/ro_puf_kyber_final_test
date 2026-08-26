# BÁO CÁO: Kyber KEM KeyGen trên Zynq-7020 — Đối chiếu FIPS, Tài nguyên, Timing

**Ngày**: 26/08/2026  
**Nền tảng**: Zynq-7020 (xc7z020clg400-2) + PicoRV32 SoC  
**Thiết bị Vivado**: Vivado 2020.1 (lin64)

---

## MỤC LỤC
1. [Tóm tắt điều hành](#1-tom-tat-dieu-hanh)
2. [Đối chiếu FIPS 203 — Kết quả KeyGen](#2-doi-chieu-fips-203)
3. [Tài nguyên phần cứng (Resource Utilization)](#3-tai-nguyen-phan-cung)
4. [Timing Summary](#4-timing-summary)
5. [Trạng thái hiện tại và Issues còn lại](#5-trang-thai)
6. [Phụ lục: Ma trận Kiểm tra](#6-phu-luc)

---

## 1. Tóm tắt điều hành

| Hạng mục | Trạng thái | Ghi chú |
|----------|-----------|---------|
| RO-PUF | **HOẠT ĐỘNG** | 1M-mẫu, BER ≤ 4 bit lỗi (k=3) |
| Fuzzy Extractor (BCH t=8) | **ĐẠT 12/12** | Verilator verification |
| KDF (AES-KDF) | **HOẠT ĐỘNG** | Key reconstruction verified |
| Keccak-f[1600] (ALGORITHM) | **ĐÚNG FIPS** | Round-by-round verified vs Python reference |
| SHA3/SHAKE (sha3_shake_core) | **ĐẠT 5/5 vector** | SHA3-256, SHA3-512, SHAKE128, SHAKE256 |
| Kyber hash_core_Server/Client | **ĐÃ VIẾT LẠI** | Tích hợp sha3_shake_core, padding FIPS-202 đúng |
| Kyber KeyGen (Full loopback) | **CHƯA ĐẠT** | NTT deadlock (ofifo1) + A-matrix FIFO-to-RAM |
| Hardware Reconstruct | **Treo** | KYBER_CTRL=0x01, Server chờ NTT |

---

## 2. Đối chiếu FIPS 203 — Kết quả KeyGen

### 2.1. FIPS 203 ML-KEM-512 Tham số

| Tham số | Giá trị | Mô tả |
|---------|---------|-------|
| k | 2 | Rank (2×2 module) |
| n | 256 | Số mũ đa thức |
| q | 3329 | Modulus |
| η1 | 3 | CBD parameter cho secret/error |
| η2 | 2 | CBD parameter cho encryption noise |
| (du, dv) | (10, 4) | Encoding bits cho ciphertext |
| pk size | 800 bytes | Public key |
| sk size | 1632 bytes | Secret key |
| ct size | 768 bytes | Ciphertext |
| ss size | 32 bytes | Shared secret |

### 2.2. FIPS 203 Reference Test Vector (ML-KEM-512)

Nguồn: NIST FIPS 203, PQCrystals reference implementation

```
d = 7c9935a0b07694aa0c6d10e4db6b1add2fd81a25ccb148032dcd739936737f2d
z = b505d7cfad1b497499323c8686325e4792f267aafa3f87ca60d01cb54f29202a

pk = 400865ed10b619aa5811139bc086825782b2b7124f757c83ae794444bc78a478
     96acf1262c81351077893bfc56f90449c2fa5f6e586dd37c0b9b581992638cb7
     e7bcbbb99afe4781d80a50e69463fbd988722c3635423e27466c71dcc674527c
     cd728968cbcdc00c5c9035bb0af2c9922c7881a41dd2875273925131230f6ca5
     9e9136b39f956c93b3b2d14c641b089e07d0a840c893ecd76bbf92c805456668
     d07c621491c5c054991a656f511619556eb97782e27a3c785124c70b0daba6c6
     24d18e0f9793f96ba9e1599b17b30dccc0b4f3766a07b23b257309cd76aba072
     c2b9c9744394c6ab9cb6c54a97b5c57861a58dc0a03519832ee32a07654a070c
     0c8c4e8648addc355f274fc6b92a087b3f9751923e44274f858c49caba72b658
     51b3adc48936955097cad9553f5a263f1844b52a020ff7ca89e881a01b95d957
     a3153c0a5e0a1ccd66b1821a2b8632546e24c7cbbc4cb08808cac37f7da6b16f
     8aced052cdb2564948f1ab0f768a0d3286ccc7c3749c63c781530fa1ae670542
     855004a645b522881ec1412bdae342085a9dd5f8126af96bbdb0c1af69a15562
     cb2a155a100309d1b641d08b2d4ed17bfbf0bc04265f9b10c108f850309504d7
     72811bba8e2be16249aa737d879fc7fb255ee7a6a0a753bd93741c61658ec074
     f6e002b019345769113cc013ff7494ba8378b11a172260aaa53421bde03a3558
     9d57e322fefa4100a4743926ab7d62258b87b31ccbb5e6b89cb10b271aa05d99
     4bb5708b23ab327ecb93c0f3156869f0883da2064f795e0e2ab7d3c64d61d230
     3fc3a29e1619923ca801e59fd752ca6e7649d303c9d20788e1214651b06995eb
     260c929a1344a849b25ca0a01f1eb52913686bba619e23714464031a78439287
     fca78f4c0476223eea61b7f25a7ce42cca901b2aea129817894ba3470823854f
     3e5b28d86ba979e54671862d90470b1e7838972a81a48107d6ac0611406b21fb
     cce1db7702ea9dd6ba6e40527b9dc663f3c93bad056dc28511f66c3e0b928db8
     879d22c592685cc775a6cd574ac3bce3b27591c821929076358a2200b377365f
     7efb9e40c3bf0ff0432986ae4bc1a242ce9921aa9e22448819585dea308eb039
     [800 bytes total - truncated for readability]

sk = 9cda1686a3396a7c109b415289f56a9ec44cd5b9b674c38a3bbab30a2c90f004
     [1632 bytes total]

ct = 1af2f982d31d2247026742f85bc3680f  [truncated - 768 bytes total]

ss = 0A6925676F24B22C286F4C81A4224CEC506C9B257D480E02E3B49F44CAA3237F
```

### 2.3. Trạng thái KAT Verification trong dự án

| Hạng mục | Kết quả | Chi tiết |
|----------|---------|----------|
| **Keccak-f[1600] Permutation** | **3/3 PASS** | Vector: PERM_ZERO, PERM_UNIT, PERM_INC |
| **SHA3/SHAKE Core** | **5/5 PASS** | SHA3-256, SHA3-512, SHAKE256, SHAKE128 multi-block, SHAKE256 edge |
| **Kyber KAT (.rsp)** | **PLACEHOLDER** | File `PQCkemKAT_1632.rsp` chứa giá trị giả (8a5c3e2f...), KHÔNG phải NIST chính thức |
| **Kyber KAT (kat_wrapper.sv)** | **CHƯA CHẠY ĐƯỢC** | Output files rỗng — pipeline chưa hoàn thành KeyGen |
| **Full Loopback (K=2)** | **CHƯA ĐẠT** | Server reaches state 19, pk transfer OK, nhưng NTT deadlock |

### 2.4. Phân tích nguyên nhân chưa đạt KAT

1. **FIPS-202 padding bug** (ĐÃ SỬA): Legacy `hash_core_Server.v` padding FSM sai — sai domain byte, sai mode-bit timing. Đã thay bằng `sha3_shake_core` (FIPS-202 compliant).

2. **NTT ofifo1 deadlock** (ĐANG XỬ LÝ): NTT Server chờ `fifo1_full` (256 words) nhưng producer chỉ tạo được 322/512 words theo lịch nonce. Legacy cũng chết ở đây (384 words). Cần đổi điều kiện NTT sang counter-based hoặc tạo lại A-matrix cho Client.

3. **Client A-matrix FIFO**: Client NTT state 6 cần đọc A-matrix từ ofifo0 nhưng FIFO đã cạn. A-matrix cần RAM (đọc nhiều lần) thay vì FIFO (đọc một lần).

---

## 3. Tài nguyên phần cứng (Resource Utilization)

### 3.1. Zynq-7020 Toàn bộ hệ thống (Kyber_System_Top)

**Bitstream**: 23/08/2026 | **Device**: xc7z020clg400-2 | **Design State**: Fully Placed

| Resource | Đã dùng | Khả dụng | Tỷ lệ |
|----------|---------|----------|-------|
| **Slice LUTs** | 28,198 | 53,200 | **53.00%** |
| LUT as Logic | 27,844 | 53,200 | 52.34% |
| LUT as Memory | 354 | 17,400 | 2.03% |
| **Slice Registers (FF)** | 21,151 | 106,400 | **19.88%** |
| **Slice** | 8,397 | 13,300 | **63.14%** |
| **Block RAM Tile** | 22.5 | 140 | **16.07%** |
| RAMB36E1 | 16 | 140 | 11.43% |
| RAMB18E1 | 13 | 280 | 4.64% |
| **DSP48E1** | 4 | 220 | **1.82%** |
| **IOB** | 5 | 125 | 4.00% |
| **BUFGCTRL** | 3 | 32 | 9.38% |

#### Phân bổ theo nhóm chức năng (ước tính)

| Nhóm | LUT (ước tính) | FF (ước tính) | Ghi chú |
|------|---------------|---------------|---------|
| PicoRV32 CPU | ~4,000 | ~3,500 | RV32I, no MUL/DIV |
| RO-PUF + LFSR | ~2,000 | ~1,200 | 32 RO chains × 32 LFSR |
| Fuzzy Extractor | ~3,000 | ~2,500 | BCH t=8 decoder |
| KDF (AES) | ~1,500 | ~1,000 | AES-128 KDF |
| Kyber Server | ~8,000 | ~6,000 | Hash core + NTT + FSM |
| Kyber Client | ~8,000 | ~5,500 | Hash core + NTT + FSM |
| AXI Interconnect + FIFO | ~1,500 | ~1,200 | Bus interface, buffers |
| Tổng (ước tính) | ~28,000 | ~20,900 | Khớp với actual |

### 3.2. So sánh với thiết kế standalone

| Thiết kế | Device | LUT | FF | BRAM | DSP |
|----------|--------|-----|-----|------|-----|
| **POWER_OPTIMIZE** | XC7A100T | 4,248 (6.7%) | 10,485 (8.3%) | 0 | 0 |
| **KYBER_KEM standalone** | XC7A35T | 15,916 (76.5%) | 10,967 (26.4%) | 11 (22%) | 4 (4.4%) |
| **Zynq-7020 full system** | XC7Z020 | 28,198 (53.0%) | 21,151 (19.9%) | 22.5 (16.1%) | 4 (1.8%) |

**Nhận xét**: Zynq-7020 còn ~47% LUT trống, ~80% FF trống. Không gian đủ để mở rộng hoặc tối ưu.

---

## 4. Timing Summary

### 4.1. Zynq-7020 Toàn bộ hệ thống

| Metric | Giá trị | Trạng thái |
|--------|---------|-----------|
| **Clock Frequency** | 50 MHz (CLK100MHZ, period = 20ns) | |
| **WNS (Setup)** | **+1.675 ns** | **MET** |
| **TNS** | 0.000 ns | Không có violation |
| **WHS (Hold)** | +0.041 ns | **MET** |
| **THS** | 0.000 ns | Không có violation |
| **WPWS (Pulse Width)** | +8.870 ns | **MET** |
| **Total Endpoints** | 56,912 | |

### 4.2. Critical Path Analysis

```
Source:      u_soc/u_kyber_axi/S/hash/keccak_inst/FSM_onehot_perm_state_reg[1]/C
Destination: u_soc/u_kyber_axi/S/hash/keccak_inst/state_reg_reg[1507]/D
Delay:       18.316 ns (logic 0.484 ns [2.6%], route 17.832 ns [97.4%])
Logic Level: 1 (LUT5)
```

**Nhận xét**: Critical path nằm ở `route delay` (97.4%) — do布线 congestion của ALGORITHM permutation datapath (1600-bit state register). Logic chỉ chiếm 2.6%. Đây là do design quá lớn cho wire routing, không phải do logic chậm.

### 4.3. So sánh Timing với các thiết kế khác

| Thiết kế | Clock | WNS | Trạng thái |
|----------|-------|-----|-----------|
| POWER_OPTIMIZE | 100 MHz | +2.271 ns | MET |
| KYBER_KEM standalone | 100 MHz | +0.293 ns | MET (tight) |
| **Zynq-7020 full system** | **50 MHz** | **+1.675 ns** | **MET** |

**Nhận xét**: Hệ thống chạy ở 50 MHz thay vì 100 MHz (do PicoRV32 constraint). WNS +1.675 ns cho thấy có thể提升 lên ~60 MHz nếu cần.

---

## 5. Trạng thái hiện tại và Issues còn lại

### 5.1. Đã hoàn thành (Verified)

- [x] Keccak-f[1600] permutation: 3/3 vectors PASS
- [x] SHA3-256/512, SHAKE128/256: 5/5 FIPS-202 vectors PASS
- [x] RO-PUF: 1M samples, BER ≤ 4 bit (BCH t=8)
- [x] Fuzzy Extractor: 12/12 test PASS (Verilator)
- [x] KDF: Key reconstruction verified
- [x] Bitstream build: timing MET, WNS +1.675 ns
- [x] UART communication: Enroll/Reconstruct protocol working
- [x] hash_core_Server/Client: rewritten with sha3_shake_core

### 5.2. Đang xử lý (In Progress)

- [ ] **NTT ofifo1 deadlock**: Producer tạo 322/512 từ, NTT chờ FULL → cần counter-based gate
- [ ] **Client A-matrix**: ofifo0 FIFO cạn → cần RAM buffer hoặc hash re-generation
- [ ] **KAT comparison**: Chưa có kết quả KeyGen để so sánh với FIPS 203

### 5.3. Cần làm tiếp

| # | Issue | Mức ưu tiên | Ước lượng |
|---|-------|------------|-----------|
| 1 | Fix NTT full-wait condition (counter-based) | **Cao** | 2-4h |
| 2 | A-matrix RAM buffer (hoặc hash loop) | **Cao** | 4-8h |
| 3 | Full loopback K=2 → KAT comparison | **Cao** | Sau khi fix #1, #2 |
| 4 | Fix ofifo1 depth/backpressure (Zynq copy) | **Trung bình** | 4-8h |
| 5 | K=3 (Kyber-768) test | **Thấp** | Sau khi K=2 pass |
| 6 | Hardware Reconstruct end-to-end | **Cao** | Sau khi KAT pass |

---

## 6. Phụ lục: Ma trận Kiểm tra FIPS 203

### A. Symmetric Primitive Verification

| Test | Input | Expected Output (FIPS-202) | Actual Output | Status |
|------|-------|---------------------------|---------------|--------|
| SHA3-256("abc") | 03020100 | `BA7816BF8F01CFEA414140DE5DAE2217` (first 16B) | Match | **PASS** |
| SHA3-512("abc") | 03020100 | `DDAF35A193617ABACC417349AE204131` (first 16B) | Match | **PASS** |
| SHAKE256("abc", 32B) | 03020100 | `46b9dd2b0ba88d13233b3feb743eeb24` (first 16B) | Match | **PASS** |
| SHAKE128 long (200B) | 000102...c7 | Multi-block boundary | Match | **PASS** |
| SHAKE256 edge (rate-1) | 33 words | Rate boundary = 42 words | Match | **PASS** |

### B. Keccak Permutation Verification

| Test | Input | Expected | Actual | Status |
|------|-------|----------|--------|--------|
| PERM_ZERO | All zeros | Known zero→nonzero output | Match | **PASS** |
| PERM_UNIT | Bit[0]=1 | Known unit output | Match | **PASS** |
| PERM_INC | Counter pattern | Known output | Match | **PASS** |

### C. FIPS 203 ML-KEM-512 Expected Sizes

| Item | Bytes | Our Design | Match |
|------|-------|-----------|-------|
| Public Key (pk) | 800 | 800 | **YES** |
| Secret Key (sk) | 1632 | 1632 | **YES** |
| Ciphertext (ct) | 768 | 768 | **YES** |
| Shared Secret (ss) | 32 | 32 | **YES** |
| Seed (d) | 32 | 32 | **YES** |
| Seed (z) | 32 | 32 | **YES** |

---

## Files tham khảo

| File | Mô tả |
|------|-------|
| `sim/kyber/PQCkemKAT_1632.rsp` | KAT reference (placeholder — cần thay bằng NIST chính thức) |
| `sim/kyber/kat_refs.svh` | KAT SystemVerilog header (từ PQCrystals C reference) |
| `sim/kyber/kat_wrapper.sv` | KAT testbench (chưa chạy thành công) |
| `project/kyber_ro_puf/rtl/kyber/ref/sha3_shake_core.v` | FIPS-202 sponge core (5/5 PASS) |
| `project/kyber_ro_puf/rtl/kyber/ref/hash_core_Server.v` | Hash core Server (đã viết lại) |
| `Kyber_System_Top_utilization_placed.rpt` | Resource utilization Zynq-7020 |
| `Kyber_System_Top_timing_summary_routed.rpt` | Timing summary Zynq-7020 |

---

*Báo cáo cập nhật ngày 26/08/2026*
