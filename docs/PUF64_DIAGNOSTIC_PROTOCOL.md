# PUF64 Diagnostic Bench Protocol v1 (D1)

Diagnostic-only endpoint for the C1-C4 scaling gate.  It is **not** a campaign
protocol: its output must never be written as a train/holdout campaign and it
must not replace or extend the production `puf_allpairs_uart` record format.

## 1. Roles

- Host -> device commands (1 byte unless noted).
- Device -> host responses.
- One response is fully streamed before the next command is accepted.
- `RUN` default measures disjoint pairs `(0,1),(2,3),...,(N-2,N-1)` so every RO
  is covered exactly once.  Full `C(N,2)` is only exercised at C4 production.

## 2. Commands

| Command | Code | Payload |
|---|---|---|
| CMD_INFO | 0x00 | - |
| CMD_RUN | 0x01 | - |
| CMD_STATUS | 0x02 | - |
| CMD_READ | 0x03 | 1 byte ro_index |
| CMD_ABORT | 0x04 | - |

Errors:
- `RUN` while busy -> status error `0xE1`.
- `READ` before done -> error `0xE2`.
- `READ` index >= NUM_RO -> error `0xE3`.

## 3. Responses

### INFO (IDINFO), 21 bytes
`50 55 46 D1` | build_id u16 | num_ro u8 | topology_id u16 | ref_cycles u16 |
mmcm_locked u8 | input_hz u32 | system_hz u32 | flags u8 (bit0 = diagnostic,
not valid for campaign).

### STATUS 0xA5
`A5` | busy u8 | done u8 | error u8 | valid_count u16 |
valid_bitmap ceil(NUM_RO/8) bytes.

### READ 0xA6, fixed 22 bytes
`A6` | diag_ver u8 | build_id u16 | num_ro u8 | topology_id u16 | ro_index u8 |
count u16 | flags u8 (bit0 valid, bit1 stable, bit2 timeout, bit3 wrap,
bit4 mmcm_locked) | input_hz u32 | system_hz u32 | ref_cycles u16 | error u8.

### ERROR 0xFF, 2 bytes
`FF` | error_code u8.

All multi-byte fields little-endian.

## 4. TX handshake (ready/valid)

- When a byte must be sent: `tx_valid` asserted, `tx_data` valid and held.
- Both held until the cycle `tx_valid && tx_ready`.
- Byte index only advances after the handshake.
- No one-cycle `tx_valid` pulse when `tx_ready = 0`.
- A response being streamed is never overwritten by a new command; the parser
  accepts a new command only after the previous response completed.
- Responses are built into a buffer, then streamed; the bench is never streamed
  live (UART is slower than the measurement sweep).

## 5. Status semantics

- `valid == 1` only after a coherent `capture_stable` record for that RO.
- `count == 0`, `timeout`, `wrap` are reported to the host and make the host
  fail; the endpoint never hides them.
- A second `RUN` clears all counters/valid/status before starting.

## 6. Host contract

1. Read INFO; verify build_id, NUM_RO, topology, 50/100 MHz, REF_CYCLES,
   mmcm_locked.
2. Send RUN; poll STATUS with a finite timeout.
3. READ each index exactly once.
4. Detect missing/duplicate indices.
5. Reject count=0, invalid, unstable, timeout, wrap, build-ID change.
6. Print min/max/mean count and the per-RO list.
7. Never write a campaign/train/holdout file.
8. Exit non-zero if any RO fails.
