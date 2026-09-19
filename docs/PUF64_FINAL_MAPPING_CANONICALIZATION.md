# PUF64 final mapping canonicalization (ZYNQ-A01, golden bitstream)

Status: holdout PASS, mapping canonicalized.  **Not** integrated into
RTL/helper/KCV/operational image.  `operational_release=false`,
`asic_qualified=false`.

## Artifacts

| Artifact | Path |
|---|---|
| Public manifest (non-secret) | `constraints/puf64_final_mapping_manifest.json` |
| Canonical hashed bytes | `constraints/puf64_final_mapping.canonical.json` |
| Private binding evidence | `reports/puf64_campaign/holdout_candidate_private.json` (git-ignored) |
| Holdout report | `reports/puf64_campaign/holdout_report.json` (git-ignored) |

Full digest (SHA3-256):
`01d5d3a77d19c54d4bfb7a71844edd5627b8fa7def775ae82d911a7a706d5858`.
SHA-256 of the canonical bytes:
`a32bd6a4752b8b2145dc5480912cfbb1853fab042dd14b6fe0697c4c18bea71a`.

## 1. Canonical serialization

The hashed payload is serialized exactly as:

- UTF-8, no BOM.
- JSON object with keys sorted ascending by Unicode code point.
- No insignificant whitespace: `,` and `:` separators only.
- `ensure_ascii=true` (non-ASCII escaped; all fields here are ASCII).
- Integers are base-10 ASCII, no leading zeros, no `+`, no underscores.
- Decimal thresholds are serialized as strings (`"10.0"`, `"4.0"`) so no float
  formatting can drift; scaled integers remain integers.
- SHA-256 fields are lowercase hex without `0x`.
- Pairs are 2-element arrays `[a,b]`, canonical `a<b`, in the frozen selection
  order (264 entries).
- File on disk = canonical bytes followed by exactly one `\n`; the hash covers
  the canonical bytes **without** the trailing newline.

Included in the hash: schema, status, algorithm/config, board/part, protocol,
build, topology + semantics, measurement architecture tuple, NUM_RO/PAIR_COUNT,
mapping length, counter width/stages, clocks, REF_CYCLES/window, bitstream and
route-fingerprint SHAs, lock level, `fixed_route`, ordered 264 pairs, degree
vector/histogram, selection and input/report binding SHAs, boot counts/lists,
frozen thresholds, holdout gate + observed metrics, limitations.

Excluded from the hash: the `mapping_tag` itself and everything derived from it
(full digest, canonical SHA), timestamps, local paths, status messages.  The
public manifest adds those derived fields around the canonical payload.

## 2. Digest and on-wire tag

- `full_mapping_digest = SHA3-256(canonical_bytes)` (FIPS 202; the project
  already uses the SHA-3/SHAKE family for the KCV).
- `mapping_tag = low 16 bits of the digest, little-endian`; documented reserved
  adjustment to `0x0001` only if the value were zero.  This mapping yields
  `0xd501` (54529), nonzero.
- Endianness on the wire: the tag occupies bytes 9..10 of the 76-byte helper
  record, little-endian (`lo` at offset 9, `hi` at offset 10), and is folded
  into the KCV context as `mapping_tag[15:0]`.

## 3. Wire-encoding facts and BLOCKER

Read from the single source of truth (`scripts/helper_record_spec.py` →
`rtl/top/helper_record_spec.vh`, `firmware/helper_record_spec.h`), not assumed:

| Field | Offset | Width | Notes |
|---|---|---|---|
| `mapping_len` | 8 | 8 bit | default 0; compared against `expected_mapping_len` in RTL (`HREC_MAPPING_LEN`), firmware `EXPECTED_MAPPING_LEN`, host serializer |
| `mapping_tag` | 9 | 16 bit LE | `HREC_MAPPING_TAG` / `EXPECTED_MAPPING_TAG`, default 0 |

`mapping_len=264` **cannot** be encoded in the 1-byte field (max 255).
Therefore the on-wire mapping-length binding is **BLOCKED** and no RTL/protocol
change was made during canonicalization.  Options that require a documented
protocol revision (not chosen here) include widening the field, encoding a
length code, or moving the length into the KCV context.

Until then, the tag identifies the intended configuration (mismatch detection)
but a device can only be bound with `mapping_len=0` in the current record.
The KCV remains the same-root security binding.  A 16-bit tag is explicitly
**not** collision-resistant against an active attacker.

## 4. Reproducibility

The canonicalizer was run twice into clean directories: canonical bytes and the
public manifest are byte-identical, with identical digest, tag, and ordered
pairs.  Golden-vector unit tests pin the canonical serialization and the
digest/tag derivation (`host/tests/test_puf64_canonicalize_mapping.py`).

## 5. Security wording (exact)

- 20 train cold boots, 10 holdout cold boots, 500 holdout frames.
- 0 observed error on the selected 264-bit vector; 0 observed FE failure.
- One Zynq (`ZYNQ-A01`) and one golden bitstream.
- True FRR is **not** zero; it is not measured by this campaign.
- Inter-device uniqueness **not** proven; min-entropy 256-bit **not** proven;
  PVT (temperature/voltage) **not** evaluated.
- `log2(64!) ≈ 296` bit is a structural order-model ceiling, not measured
  entropy.
- Response balance 152/112 is an observation, never a selection criterion.

## 6. Next phase (not done)

Integration into helper record/KCV/operational image changes the netlist.  It
requires a new build, physical-fingerprint re-check, and a protocol revision for
`mapping_len`.  It is intentionally out of scope for canonicalization.
