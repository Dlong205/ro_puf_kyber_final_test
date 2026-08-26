# Kyber PUF FPGA — RTL Delivery

Hệ thống mã hóa hậu lượng tử **Kyber KEM** kết hợp **RO-PUF** trên FPGA Zynq-7020.

---

## Cấu trúc thư mục

```
kyber_puf_fpga_delivery/
├── rtl/
│   ├── top/                  # Top-level system
│   │   ├── Kyber_System_Top.sv          # Pipeline: PUF→FE→KDF→Kyber
│   │   ├── kyber_axi_wrapper.v          # AXI4-Lite slave (PS-PL interface)
│   │   ├── system_uart_ctrl.v           # UART command FSM (Enroll/Reconstruct)
│   │   └── kdf_keccak.sv               # KDF using SHAKE256
│   │
│   ├── puf/                  # Ring Oscillator PUF
│   │   ├── kp_puf_top.sv                # RO-PUF top (264-bit response)
│   │   ├── kp_puf_control.sv            # PUF control FSM
│   │   ├── kp_puf_cells.sv              # MUX, counter, comparator, shiftreg
│   │   ├── kp_ro_cell.sv                # Ring Oscillator cell
│   │   ├── kp_top.v                     # Board wrapper (Arty A7)
│   │   ├── kp_uart_ctrl.v               # UART bridge
│   │   ├── puf_axi_lite_wrapper.v       # AXI4-Lite wrapper
│   │   ├── LFSR.v                       # Challenge generation
│   │   ├── uart_rx.v                    # UART receiver
│   │   └── uart_tx.v                    # UART transmitter
│   │
│   ├── fe_bch/               # Fuzzy Extractor (BCH t=8)
│   │   ├── bch_encode.v                 # BCH encoder
│   │   ├── bch_syndrome.v               # Syndrome calculator
│   │   ├── bch_sigma_bma_serial.v       # Berlekamp-Massey algorithm
│   │   ├── bch_chien.v                  # Chien search
│   │   ├── bch_error_tmec.v             # Error correction
│   │   ├── bch_math.v                   # GF(2^m) arithmetic library
│   │   ├── xilinx_decoder.v             # Xilinx BCH decoder wrapper
│   │   ├── xilinx_encode.v              # Xilinx BCH encoder wrapper
│   │   └── sha256/                      # SHA-256 hash (for PUF)
│   │       ├── sha256.v
│   │       ├── sha256_core.v
│   │       ├── sha256_w_mem.v
│   │       └── sha256_k_constants.v
│   │
│   ├── kyber/                # Kyber KEM core
│   │   ├── Kyber_Server.v               # Server: KeyGen, Encap, Decap
│   │   ├── Kyber_Client.v               # Client: Decapsulation
│   │   ├── NTT_core_Server.v            # NTT core (Server)
│   │   ├── NTT_core_Client.v            # NTT core (Client)
│   │   ├── butterfly_Server.v           # NTT butterfly (Server)
│   │   ├── butterfly_Client.v           # NTT butterfly (Client)
│   │   ├── hash_core_Server.v           # Hash core (Server, rewritten)
│   │   ├── hash_core_Client.v           # Hash core (Client, rewritten)
│   │   ├── sha3_shake_core.v            # FIPS-202 sponge core (5/5 PASS)
│   │   ├── encode_Server.v              # Coefficient encoder (Server)
│   │   ├── encode_Client.v              # Coefficient encoder (Client)
│   │   ├── decode_Server.v              # Coefficient decoder (Server)
│   │   ├── decode_Client.v              # Coefficient decoder (Client)
│   │   ├── decode_keccak.v              # Keccak→coefficient decoder
│   │   ├── pattern.v                    # NTT operation pattern (k-param)
│   │   ├── LUT.v                        # Twiddle factor LUT
│   │   ├── reduc.v                      # Barrett reduction (mod 3329)
│   │   ├── mux4to2.v                    # 4:2 MUX utility
│   │   └── fifo_wrappers.v              # FIFO wrappers (Xilinx compat)
│   │
│   ├── keccak/               # Keccak-f[1600] permutation
│   │   ├── ALGORITHM.v                  # 24-round permutation top
│   │   ├── THETA1.v                     # Theta step 1
│   │   ├── THETA2_RHO_PI.v             # Theta2 + Rho + Pi
│   │   ├── CHI1.v / CHI2.v             # Chi non-linearity
│   │   ├── Chi_3_Iota.v                # Chi step3 + Iota
│   │   ├── IOTA.v                       # Round constant XOR
│   │   ├── RC.v                         # Round constant LUT
│   │   └── ADDER.v                      # Round counter utility
│   │
│   └── common/               # Shared modules
│       ├── keccak_pkg.sv                # Keccak parameters package
│       ├── generic_fifo.sv              # Parameterized FIFO
│       ├── generic_bram.sv              # Dual-port Block RAM
│       └── generic_rom.sv               # Single-port ROM
│
├── reports/                  # Vivado synthesis reports
│   ├── Kyber_System_Top_utilization_placed.rpt
│   └── Kyber_System_Top_timing_summary_routed.rpt
│
├── results/                  # Test vectors & KAT
│   ├── PQCkemKAT_1632.rsp              # Kyber-512 KAT reference
│   ├── kat_refs.svh                     # KAT SystemVerilog header
│   └── vectors.svh                      # SHA3/SHAKE FIPS-202 test vectors
│
├── docs/                     # Documentation
│   └── REPORT_KeyGen_FIPS_Resource_Timing.md
│
└── README.md                 # File này
```

---

## Pipeline hoạt động

```
UART Commands:
  0x01 = ENROLL      → PUF → FE → KDF → Generate helper data
  0x02 = RECONSTRUCT → PUF → FE → KDF → Kyber KeyGen → Server/Client → Shared Secret

┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────────────────┐
│ RO-PUF   │───▶│ Fuzzy    │───▶│ KDF      │───▶│ Kyber KEM            │
│ 264-bit  │    │ Extractor│    │ SHAKE256 │    │ Server ←──→ Client   │
│ response │    │ BCH t=8  │    │ 512-bit  │    │ KeyGen→Encap→Decap   │
└──────────┘    └──────────┘    └──────────┘    └──────────────────────┘
```

---

## Kết quả kiểm tra

| Module | Test | Kết quả | Ghi chú |
|--------|------|---------|---------|
| Keccak-f[1600] | 3 vectors (zero/unit/inc) | **PASS** | Verified vs Python reference |
| SHA3/SHAKE core | 5 FIPS-202 vectors | **PASS** | SHA3-256, SHA3-512, SHAKE128, SHAKE256 |
| RO-PUF | 1M samples | **PASS** | BER ≤ 4 bit (BCH t=8) |
| Fuzzy Extractor | 12/12 tests | **PASS** | Verilator verification |
| KDF (SHAKE256) | Key reconstruction | **PASS** | |
| Kyber full loopback | K=2 | **IN PROGRESS** | NTT deadlock, A-matrix FIFO |

---

## Resource Utilization (Zynq-7020)

| Resource | Đã dùng | Khả dụng | Tỷ lệ |
|----------|---------|----------|-------|
| LUT | 28,198 | 53,200 | 53.0% |
| FF | 21,151 | 106,400 | 19.9% |
| BRAM | 22.5 | 140 | 16.1% |
| DSP | 4 | 220 | 1.8% |

## Timing (Zynq-7020, 50 MHz)

| Metric | Giá trị |
|--------|---------|
| WNS (Setup) | +1.675 ns — **MET** |
| TNS | 0.000 ns |
| WHS (Hold) | +0.041 ns — **MET** |
| Critical path | Keccak ALGORITHM (route delay 97.4%) |

---

## FIPS 203 ML-KEM-512 sizes

| Item | Bytes |
|------|-------|
| Public Key (pk) | 800 |
| Secret Key (sk) | 1632 |
| Ciphertext (ct) | 768 |
| Shared Secret (ss) | 32 |

---

## Known Issues

1. **NTT ofifo1 deadlock**: Producer tạo 322/512 words, NTT chờ FULL. Cần counter-based gate.
2. **Client A-matrix**: ofifo0 FIFO cạn sau lần đọc đầu. Cần RAM buffer.
3. **KAT placeholder**: File `.rsp` chứa giá trị giả, cần thay bằng NIST chính thức.

---

## Toolchain

- **Vivado**: 2020.1 (lin64)
- **Simulator**: Verilator 4.2+
- **Target**: Xilinx Zynq-7020 (xc7z020clg400-2)
- **Bitstream**: Built 23/08/2026, timing MET
