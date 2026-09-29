#!/usr/bin/env python3
"""Extend the checked-in ML-KEM-512 corpus with differential vectors.

Keeps the 25 ACVP TCs first (TCID 1-25), appends pq-crystals reference
outputs (commit 3edd5af, same as generate_decap_vectors.py):
  keygen: 75 random (d,z) incl. all-zero / all-FF / alternating edges
  encap : 75 random (m, fresh ek)
  decap : 25 random-key blocks, each with the same 7 rejection mutations
Reference library: /tmp/pqkyber512_ref.so (namespace-renamed kyber512 ref).
Idempotent: skips TCIDs already present.
"""
import ctypes
import os
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SIM = ROOT / "sim/mlkem"
LIB = Path(os.environ.get("PQKYBER_LIB", "/tmp/pqkyber512_ref.so"))
SEED = int(os.environ.get("PQKYBER_SEED", "203"))

MUTATIONS = ((0, 0x01), (319, 0x80), (320, 0x01), (511, 0x80),
             (639, 0x80), (640, 0x01), (767, 0x80))

lib = ctypes.CDLL(str(LIB))
u8p = ctypes.POINTER(ctypes.c_uint8)
keypair = lib.pqcrystals_kyber512_ref_keypair_derand
encaps = lib.pqcrystals_kyber512_ref_enc_derand
decaps = lib.pqcrystals_kyber512_ref_dec
# ref kem.h: keypair_derand(pk, sk, coins); enc_derand(ct, ss, pk, coins);
# dec(ss, ct, sk)
keypair.argtypes = [u8p, u8p, u8p]
keypair.restype = ctypes.c_int
encaps.argtypes = [u8p, u8p, u8p, u8p]
encaps.restype = ctypes.c_int
decaps.argtypes = [u8p, u8p, u8p]
decaps.restype = ctypes.c_int


def buf(n):
    b = (ctypes.c_uint8 * n)()
    return b


def hx(b):
    return bytes(b).hex().upper()


def keygen(d: bytes, z: bytes):
    coins = (ctypes.c_uint8 * 64)(*d, *z)
    pk, sk = buf(800), buf(1632)
    assert keypair(pk, sk, coins) == 0
    return bytes(pk), bytes(sk)


def encap(m: bytes, pk: bytes):
    ct, ss = buf(768), buf(32)
    coins = (ctypes.c_uint8 * 32)(*m)
    assert encaps(ct, ss, (ctypes.c_uint8 * 800)(*pk), coins) == 0
    return bytes(ct), bytes(ss)


def existing_tcids(path: Path):
    ids = set()
    for line in path.read_text().splitlines():
        if line.startswith("TCID="):
            ids.add(int(line.split("=")[1]))
    return ids


def main() -> int:
    rng = random.Random(SEED)
    # --- keygen ---
    kg = SIM / "mlkem512_keygen_acvp.txt"
    have = existing_tcids(kg)
    edges = [(b"\x00" * 32, b"\x00" * 32), (b"\xff" * 32, b"\xff" * 32),
             (bytes(range(32)), bytes(range(32, 64)))]
    new_keys = []  # (d, z, ek, dk) for reuse by encap/decap
    lines = []
    tcid = 26
    for d, z in edges + [(rng.randbytes(32), rng.randbytes(32))
                         for _ in range(72)]:
        if tcid in have:
            tcid += 1
            continue
        ek, dk = keygen(d, z)
        new_keys.append((d, z, ek, dk))
        lines.append(f"TCID={tcid}\nD={d.hex().upper()}\n"
                     f"Z={z.hex().upper()}\nEK={hx(ek)}\nDK={hx(dk)}\n")
        tcid += 1
    if lines:
        with kg.open("a") as f:
            f.write("# Differential extension: pq-crystals ref 3edd5af, "
                    "75 keys (3 edge + 72 random), seed 203\n")
            f.write("".join(lines))
    print(f"keygen: +{len(lines)} TCs")

    # --- encap (fresh eks) ---
    en = SIM / "mlkem512_encap_acvp.txt"
    have = existing_tcids(en)
    lines, encap_keys = [], []
    tcid = 26
    for _ in range(75):
        d, z = rng.randbytes(32), rng.randbytes(32)
        ek, _ = keygen(d, z)
        m = rng.randbytes(32)
        ct, ss = encap(m, ek)
        encap_keys.append((m, ek, ct, ss))
        if tcid in have:
            tcid += 1
            continue
        lines.append(f"TCID={tcid}\nM={m.hex().upper()}\nEK={hx(ek)}\n"
                     f"C={hx(ct)}\nK={hx(ss)}\n")
        tcid += 1
    if lines:
        with en.open("a") as f:
            f.write("# Differential extension: pq-crystals ref 3edd5af, "
                    "75 encaps, seed 203\n")
            f.write("".join(lines))
    print(f"encap: +{len(lines)} TCs")

    # --- decap blocks (valid + 7 mutations each) ---
    dc = SIM / "mlkem512_decap_ref.txt"
    have = existing_tcids(dc)
    import hashlib
    lines = []
    tcid = 26
    for _ in range(25):
        d, z = rng.randbytes(32), rng.randbytes(32)
        ek, dk = keygen(d, z)
        m = rng.randbytes(32)
        ct, ss = encap(m, ek)
        if tcid in have:
            tcid += 1
            continue
        block = [f"TCID={tcid}", f"D={d.hex().upper()}",
                 f"Z={z.hex().upper()}", f"M={m.hex().upper()}",
                 f"C={hx(ct)}", f"K={hx(ss)}"]
        for off, mask in MUTATIONS:
            bad = bytearray(ct)
            bad[off] ^= mask
            j = hashlib.shake_256(z + bytes(bad)).digest(32)
            block.append(f"INVALID_J_{off}_{mask:02X}={j.hex().upper()}")
        lines.append("\n".join(block) + "\n")
        tcid += 1
    if lines:
        with dc.open("a") as f:
            f.write("# Differential extension: pq-crystals ref 3edd5af, "
                    "25 keys x 7 mutations, seed 203\n")
            f.write("".join(lines))
    print(f"decap: +{len(lines)} blocks (+{len(lines) * 7} rejections)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
