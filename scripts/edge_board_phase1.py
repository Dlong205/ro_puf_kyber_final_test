#!/usr/bin/env python3
"""
edge_board_phase1.py — On-board Phase 1 same-root KCV binding verification.

Talks the record-framed transport of Edge_Zynq_Diagnostic_100MHz_Top
(rtl/top/edge_uart_transport.sv) over a USB-UART on a Zynq-7020 board:

  INFO    : 5-byte "EA" banner + protocol info.
  ENROLL  : 0xAA + 76-byte versioned helper record (header, helper, KCV,
            CRC16/CCITT-FALSE low,high).  Validated against
            scripts/helper_record_spec.py on the host.
  SESSION : 'H' -> 76-byte record + 4-byte nonce -> 'P' + 800-byte Kyber pk
            -> 'C' -> 768-byte ciphertext -> 0xAA + 4-byte result tag.
  Failing sessions return 0xFF + a record-validation or pipeline code.

Board commands:
  1. Program build/fpga_100mhz/<run>/Edge_Zynq_Diagnostic_100MHz_Top.bit
     (volatile) with scripts/program_board.tcl.
  2. python3 scripts/edge_board_phase1.py --port /dev/ttyUSB0

Exit 0 on all checks passing, 1 on any board/host failure.
"""

import argparse
import struct
import sys
import time

import serial

sys.path.insert(0, "/home/donglong/Documents/Duy_prj/"
                  "KECCAK_OPTIMIZE_POWER/OPTIMIZE_POWER/"
                  "kyber_puf_mlkem_novelty/scripts")
import helper_record_spec as spec

BAUD = 115200
CMD_INFO = 0x00
CMD_ENROLL = 0x01
CMD_SESSION = 0x02
STATUS_OK = 0xAA
STATUS_FAIL = 0xFF
PK_BYTES = 200 * 4
CT_BYTES = 192 * 4

FAIL_NAMES = {
    0x01: "unsupported command",
    0x02: "enrollment FE failure",
    0x03: "reconstruction failed (FE decode or KCV gate)",
    0xf0: "transport RX timeout",
    0xf1: "trailing byte after nonce",
}

failures = []


def check(name, ok, detail=""):
    mark = "PASS" if ok else "FAIL"
    print(f"[{mark} ] {name}{('  ' + detail) if detail else ''}")
    if not ok:
        failures.append(name)
    return ok


def read_exact(ser, n, label, timeout=20.0):
    buf = bytearray()
    end = time.time() + timeout
    while len(buf) < n:
        remaining = end - time.time()
        if remaining <= 0:
            raise TimeoutError(f"timeout reading {label}: got {len(buf)}/{n}")
        chunk = ser.read(min(4096, max(1, n - len(buf))))
        if chunk:
            buf += chunk
    return bytes(buf)


def drain(ser):
    time.sleep(0.15)
    waiting = ser.in_waiting
    if waiting:
        stale = ser.read(waiting)
        print(f"[*] Drained {len(stale)} stale byte(s): {stale.hex()}")


def do_info(ser):
    ser.write(bytes([CMD_INFO]))
    banner = read_exact(ser, 5, "INFO banner")
    ok = banner[:2] == b"EA" and banner[2:4] == bytes([0x01, 0x01])
    check("INFO banner EA.01.01", ok,
          detail="resp=" + banner.hex())
    return ok


def do_enroll(ser):
    ser.write(bytes([CMD_ENROLL]))
    status = read_exact(ser, 1, "enroll status")
    ok = status[0] == STATUS_OK
    check("ENROLL STATUS_OK", ok, detail=f"got 0x{status[0]:02x}")
    if not ok:
        fail = ser.read(1)
        check("ENROLL captured helper + KCV", False, detail=f"fail code {fail.hex()}")
        return None
    record = read_exact(ser, spec.RECORD_BYTES, "enroll record")
    check("ENROLL record length=76", len(record) == 76)
    return record


def parse_and_validate(record, tag=""):
    ok = True
    if len(record) != 76:
        check(f"{tag} record length", False)
        return
    magic = struct.unpack("<I", record[0:4])[0]
    check(f"{tag} magic 0xRKPU", magic == spec.MAGIC,
          detail=f"0x{magic:08x}")
    for off, name, want in [
        (spec.OFF_RECORD_VERSION, "record_version", spec.RECORD_VERSION),
        (spec.OFF_PROTOCOL_VERSION, "protocol_version", spec.PROTOCOL_VERSION),
        (spec.OFF_PROFILE, "profile", spec.DEFAULT_PROFILE),
        (spec.OFF_FE_PARAM, "fe_param", spec.DEFAULT_FE_PARAM),
        (spec.OFF_MAPPING_LEN, "mapping_len", spec.DEFAULT_MAPPING_LEN),
        (spec.OFF_GENERATION, "generation", spec.DEFAULT_GENERATION),
        (spec.OFF_RESERVED, "reserved", spec.RESERVED),
    ]:
        got = record[off]
        if got != want:
            check(f"{tag} header.{name}", False, detail=f"got 0x{got:02x} want 0x{want:02x}")
            ok = False
    mapping_tag = struct.unpack("<H", record[spec.OFF_MAPPING_TAG:spec.OFF_MAPPING_TAG + 2])[0]
    check(f"{tag} mapping_tag=0x0000", mapping_tag == spec.DEFAULT_MAPPING_TAG,
          detail=f"0x{mapping_tag:04x}")
    helper = record[spec.OFF_HELPER:spec.OFF_KCV]
    kcv = record[spec.OFF_KCV:spec.OFF_CRC]
    check(f"{tag} helper length=33", len(helper) == 33)
    check(f"{tag} KCV length=28", len(kcv) == 28)
    check(f"{tag} KCV non-zero", any(kcv))
    crc_lo, crc_hi = record[74], record[75]
    host_crc = spec.crc16_ccitt_false(record[0:74])
    wire_crc = (crc_hi << 8) | crc_lo
    check(f"{tag} CRC valid", host_crc == wire_crc,
          detail=f"wire=0x{wire_crc:04x} host=0x{host_crc:04x}")
    status, ctx, _, _ = spec.validate_record(record)
    check(f"{tag} spec.validate_record OK", status == spec.REC_OK,
          detail=spec.ERROR_NAMES.get(status, "?"))
    check(f"{tag} ctx generation=1"
          "", (ctx >> 48) == spec.DEFAULT_GENERATION,
          detail=f"ctx=0x{ctx:014x}")
    print(f"    {tag} helper={helper.hex()}")
    print(f"    {tag} kcv   ={kcv.hex()}")
    return ok


def build_record(helper, kcv, **overrides):
    return spec.serialize_record(helper, kcv, **overrides)


def mutate_record(record, fn):
    body = bytearray(record[0:74])
    fn(body)
    crc = spec.crc16_ccitt_false(bytes(body))
    body += struct.pack("<H", crc)
    return bytes(body)


def do_session(ser, record, nonce, want_ok, tag, ct=None):
    drain(ser)
    ser.write(bytes([CMD_SESSION]))
    marker = read_exact(ser, 1, "session 'H' marker")
    check(f"{tag} session 'H' marker", marker[0] == ord("H"),
          detail=f"got 0x{marker[0]:02x}")
    if marker[0] != ord("H"):
        drain(ser)
        return False
    ser.write(record + nonce)

    if not want_ok:
        status = read_exact(ser, 2, f"{tag} fail response")
        ok = status[0] == STATUS_FAIL
        code = status[1] if len(status) > 1 else None
        cname = FAIL_NAMES.get(code, spec.ERROR_NAMES.get(code, "?"))
        check(f"{tag} rejected with STATUS_FAIL",
              ok, detail=f"code=0x{code:02x} ({cname})" if code is not None else "")
        drain(ser)
        return ok

    marker = read_exact(ser, 1, f"{tag} 'P' marker")
    got = marker[0]
    if got == STATUS_FAIL:
        code = read_exact(ser, 1, f"{tag} fail code")
        cname = FAIL_NAMES.get(code[0], spec.ERROR_NAMES.get(code[0], "?"))
        drain(ser)
        check(f"{tag} KCV gate open ('P' marker)", False,
              detail=f"rejected code=0x{code[0]:02x} ({cname})")
        return False
    ok = got == ord("P")
    check(f"{tag} KCV gate open ('P' marker)", ok,
          detail="reconstruction + KCV binding passed on silicon"
          if ok else f"got 0x{got:02x}")
    if not ok:
        drain(ser)
        return False
    pk = read_exact(ser, PK_BYTES, f"{tag} public key")
    check(f"{tag} public key len=800", len(pk) == PK_BYTES,
          detail=f"sha256={__import__('hashlib').sha256(pk).hexdigest()[:16]}")
    marker = read_exact(ser, 1, f"{tag} 'C' marker")
    check(f"{tag} ciphertext 'C' marker", marker[0] == ord("C"),
          detail=f"got 0x{marker[0]:02x}")
    if ct is None:
        ct = bytes(r % 256 for r in range(CT_BYTES))
    ser.write(ct)
    status = read_exact(ser, 5, f"{tag} result", timeout=45.0)
    ok = status[0] == STATUS_OK
    tag_val = struct.unpack("<I", status[1:5])[0] if len(status) == 5 else None
    check(f"{tag} server decap STATUS_OK", ok,
          detail=f"result_tag=0x{tag_val:08x}" if tag_val is not None else "")
    drain(ser)
    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", "-p", default="/dev/ttyUSB0")
    args = ap.parse_args()

    try:
        ser = serial.Serial(port=args.port, baudrate=BAUD, bytesize=8,
                            parity="N", stopbits=1, timeout=1.0)
    except serial.SerialException as exc:
        print(f"[-] Cannot open {args.port}: {exc}")
        return 1
    print(f"[*] Opened {args.port} @ {BAUD}")

    drain(ser)
    do_info(ser)

    record = do_enroll(ser)
    if record is None:
        ser.close()
        return 1
    parse_and_validate(record, "ENROLL")

    nonce = bytes([0x10, 0xc0, 0xff, 0xee])
    do_session(ser, record, nonce, want_ok=True, tag="SESSION-valid",
               ct=None)

    print("--- negative: structurally corrupted records (parser gate) ---")
    bad_crc = bytearray(record)
    bad_crc[75] ^= 0x01
    do_session(ser, bytes(bad_crc), nonce, want_ok=False, tag="NEG-bad-CRC")

    bad_magic = mutate_record(record, lambda b: b.__setitem__(0, 0x00))
    do_session(ser, bad_magic, nonce, want_ok=False, tag="NEG-bad-magic")

    print("--- negative: wrong-root reference (KCV gate) ---")
    wrong_kcv = mutate_record(record, lambda b: b.__setitem__(spec.OFF_KCV, b[spec.OFF_KCV] ^ 0x01))
    do_session(ser, wrong_kcv, nonce, want_ok=False, tag="NEG-wrong-KCV")

    zero_kcv = mutate_record(record, lambda b: b.__setitem__(slice(spec.OFF_KCV, spec.OFF_CRC), bytes(28)))
    do_session(ser, zero_kcv, nonce, want_ok=False, tag="NEG-zero-KCV")

    misset_gen = mutate_record(record, lambda b: b.__setitem__(spec.OFF_GENERATION, 0x02))
    do_session(ser, misset_gen, nonce, want_ok=False, tag="NEG-wrong-generation")

    print("--- negative: out-of-radius helper (FE/KCV gate) ---")
    def bulldoze_helper(b):
        for i in range(16):
            b[spec.OFF_HELPER + (i * 2) % 33] ^= 0xff
    far_helper = mutate_record(record, bulldoze_helper)
    do_session(ser, far_helper, nonce, want_ok=False, tag="NEG-helper-out-of-radius")

    ser.close()

    print()
    if failures:
        print(f"BOARD_PHASE1_RESULT FAIL checks={len(failures)}")
        for f in failures:
            print(f"  - {f}")
        return 1
    print("BOARD_PHASE1_RESULT PASS checks=all")
    return 0


if __name__ == "__main__":
    sys.exit(main())