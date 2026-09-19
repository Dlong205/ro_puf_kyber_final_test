#include <stdint.h>
#include "helper_record_spec.h"

#define REG(addr) (*((volatile uint32_t*)(addr)))

#define UART_DATA   REG(0x10000000)
#define UART_STATUS REG(0x10000004)
#define SYS_CTRL    REG(0x10000008)
#define HELPER_WORD(idx) REG(0x10000010 + (idx)*4)

#define KDF_SEED(idx)     REG(0x10000040 + (idx)*4)
#define KCV_REF(idx)      REG(0x100000A0 + (idx)*4)
#define KCV_CTX_LO        REG(0x100000BC)
#define KCV_CTX_HI        REG(0x100000C0)
#define KCV_CTRL          REG(0x100000C4)
#define KYBER_SEED_D(idx) REG(0x10000100 + (idx)*4)
#define KYBER_SEED_Z(idx) REG(0x10000120 + (idx)*4)
#define KYBER_CTRL        REG(0x10000140)
#define KYBER_STATUS      REG(0x10000144)
#define KYBER_PARAM       REG(0x10000148)
#define KYBER_K_SERVER(idx) REG(0x10000160 + (idx)*4)
#define KYBER_SEED_M(idx) REG(0x10000180 + (idx)*4)

#ifndef RELEASE_BUILD
#define RELEASE_BUILD 1
#endif

#define PROTOCOL_MAJOR 1
#define PROTOCOL_MINOR 4

// Compile-time lifecycle: operational/release images must reject CMD_ENROLL;
// only manufacturing/diagnostic bring-up images set EDGE_ALLOW_ENROLL=1.
#ifndef EDGE_ALLOW_ENROLL
#define EDGE_ALLOW_ENROLL 0
#endif

#define CMD_INFO   0x00
#define CMD_ENROLL 0x01
#define CMD_RECON  0x02

#define STATUS_SUCCESS 0xAA
#define STATUS_FAIL    0xFF

#define RESULT_KEY_FOLLOWS (1u << 0)
#define CAP_KEY_EXPORT     (1u << 0)
#define CAP_SESSION_DIVERSIFICATION (1u << 1)
#define CAP_ACCELERATOR_ZEROIZE (1u << 2)
#define CAP_HELPER_RECORD  (1u << 3)

#define ERR_UART_TIMEOUT  0x01
#define ERR_PUF_TIMEOUT   0x02
#define ERR_FE_TIMEOUT    0x03
#define ERR_FE_DECODE     0x04
#define ERR_KDF_TIMEOUT   0x05
#define ERR_KYBER_CONFIG  0x06
#define ERR_KYBER_TIMEOUT 0x07
#define ERR_KEY_MISMATCH  0x08
#define ERR_ZEROIZE_TIMEOUT 0x09
#define ERR_HELPER_RECORD 0x0A
#define ERR_ENROLL_FORBIDDEN 0x0B
#define ERR_KCV_TIMEOUT  0x0C
#define ERR_KCV_MISMATCH 0x0D
#define ERR_KCV_UNPROVISIONED 0x0E

// Provisioned immutable binding for this platform image.  Must match the
// values the host serialized into the record and the Edge RTL parameters.
#define EXPECTED_PROFILE  0x01
#define EXPECTED_FE_PARAM 0x01
#define EXPECTED_MAPPING_LEN_BYTES 0x21
#define EXPECTED_MAPPING_TAG 0xD501

#define SYS_ST_PUF_DONE       (1u << 0)
#define SYS_ST_FE_DONE        (1u << 1)
#define SYS_ST_FE_SUCCESS     (1u << 2)
#define SYS_ST_KDF_DONE       (1u << 3)
#define SYS_ST_ZEROIZE_DONE   (1u << 4)

#define KCV_ST_DONE   (1u << 0)
#define KCV_ST_PASS   (1u << 1)

// Enrollment context: {generation, mapping_tag, fe_param, profile, proto,
// record_version}, matching the record header the firmware emits and the Edge
// RTL transport parameters.  Single source is scripts/helper_record_spec.py.
#define ENROLL_CTX ((((uint64_t)0x01u) << 48) | \
                    (((uint64_t)EXPECTED_MAPPING_TAG) << 32) | \
                    (((uint64_t)EXPECTED_FE_PARAM) << 24) | \
                    (((uint64_t)EXPECTED_PROFILE) << 16) | \
                    (((uint64_t)HREC_PROTOCOL_VERSION) << 8) | \
                    ((uint64_t)HREC_RECORD_VERSION))

#define KYBER_ST_DONE         (1u << 2)
#define KYBER_ST_BUSY         (1u << 3)
#define KYBER_ST_CONFIG_ERROR (1u << 4)
#define KYBER_ST_KEY_MATCH    (1u << 5)

#define HW_TIMEOUT      20000000u
#define KYBER_TIMEOUT    2000000u
#define UART_TIMEOUT    50000000u
#define KYBER_MAX_ATTEMPTS 1u

static uint32_t session_counter;
static uint8_t record_buf[HREC_BYTES];

static void uart_putchar(uint8_t c) {
    while (UART_STATUS & 1u); // Wait while TX is active.
    UART_DATA = c;
}

static uint8_t uart_getchar_blocking(void) {
    while (1) {
        uint32_t value = UART_DATA;
        if (value & (1u << 8))
            return (uint8_t)value;
    }
}

static int uart_getchar_timeout(uint8_t *out) {
    for (uint32_t timeout = 0; timeout < UART_TIMEOUT; timeout++) {
        uint32_t value = UART_DATA;
        if (value & (1u << 8)) {
            *out = (uint8_t)value;
            return 1;
        }
    }
    return 0;
}

static int wait_sys_status(uint32_t mask) {
    for (uint32_t timeout = 0; timeout < HW_TIMEOUT; timeout++) {
        if (SYS_CTRL & mask)
            return 1;
    }
    return 0;
}

static void kcv_write_ref(const uint8_t *ref28) {
    // Comparison-only helper KCV shadow; the trusted anchor lives in hardware
    // and can never be overwritten by this write.
    for (int w = 0; w < 7; w++)
        KCV_REF(w) = (uint32_t)ref28[w * 4] |
                     ((uint32_t)ref28[w * 4 + 1] << 8) |
                     ((uint32_t)ref28[w * 4 + 2] << 16) |
                     ((uint32_t)ref28[w * 4 + 3] << 24);
}

static void kcv_write_ctx(uint64_t ctx) {
    KCV_CTX_LO = (uint32_t)(ctx & 0xFFFFFFFFu);
    KCV_CTX_HI = (uint32_t)((ctx >> 32) & 0xFFFFFFu);
}

#if EDGE_ALLOW_ENROLL
static void kcv_read_out(uint8_t *out28) {
    for (int w = 0; w < 7; w++) {
        uint32_t word = KCV_REF(w);
        out28[w * 4]     = (uint8_t)(word & 0xFF);
        out28[w * 4 + 1] = (uint8_t)((word >> 8) & 0xFF);
        out28[w * 4 + 2] = (uint8_t)((word >> 16) & 0xFF);
        out28[w * 4 + 3] = (uint8_t)((word >> 24) & 0xFF);
    }
}
#endif

static int kcv_wait(uint32_t *pass) {
    for (uint32_t timeout = 0; timeout < HW_TIMEOUT; timeout++) {
        uint32_t status = KCV_CTRL;
        if (status & KCV_ST_DONE) {
            *pass = (status & KCV_ST_PASS) != 0;
            return 1;
        }
    }
    return 0;
}

static uint64_t kcv_ctx_from_record(void) {
    uint16_t tag = (uint16_t)record_buf[HREC_OFF_MAPPING_TAG] |
                   ((uint16_t)record_buf[HREC_OFF_MAPPING_TAG + 1] << 8);
    return (((uint64_t)record_buf[HREC_OFF_GENERATION]) << 48) |
           (((uint64_t)tag) << 32) |
           (((uint64_t)record_buf[HREC_OFF_FE_PARAM]) << 24) |
           (((uint64_t)record_buf[HREC_OFF_PROFILE]) << 16) |
           (((uint64_t)record_buf[HREC_OFF_PROTOCOL_VERSION]) << 8) |
           ((uint64_t)record_buf[HREC_OFF_RECORD_VERSION]);
}

static int wait_kyber_done(void) {
    // A normal KEM finishes far below this bound.  A timeout is a hard
    // transaction failure; release firmware never retries a different seed.
    for (uint32_t timeout = 0; timeout < KYBER_TIMEOUT; timeout++) {
        uint32_t status = KYBER_STATUS;
        if (status & KYBER_ST_CONFIG_ERROR)
            return 0;
        if (status & KYBER_ST_DONE)
            return (status & KYBER_ST_BUSY) == 0;
    }
    return 0;
}

static uint32_t read_cycle(void) {
    uint32_t value;
    __asm__ volatile ("rdcycle %0" : "=r"(value));
    return value;
}

static uint32_t mix32(uint32_t value) {
    value ^= value << 13;
    value ^= value >> 17;
    value ^= value << 5;
    return value;
}

#if !RELEASE_BUILD
static void secure_zero_words(volatile uint32_t *words, uint32_t count) {
    while (count--)
        *words++ = 0;
}
#endif

static int secure_zeroize(void) {
    // SYS_CTRL[4] erases secret state in the PUF, FE, KDF and Kyber
    // accelerators. Completion is reported only after the 2048-address Kyber
    // memory scrub has finished. CPU/firmware state is outside this hardware
    // accelerator-zeroize boundary.
    SYS_CTRL = SYS_ST_ZEROIZE_DONE;
    return wait_sys_status(SYS_ST_ZEROIZE_DONE);
}

static void send_failure(uint8_t code, int clear_sensitive) {
    if (clear_sensitive && !secure_zeroize())
        code = ERR_ZEROIZE_TIMEOUT;
    uart_putchar(STATUS_FAIL);
    uart_putchar(code);
}

// ---- helper-record mirror (single spec: scripts/helper_record_spec.py) ----
// Early rejection only; the CPU-free Edge RTL remains the security
// enforcement boundary.  Field order and error precedence match the RTL
// helper_record_parse module exactly.

static uint16_t crc16_ccitt_false_buf(const uint8_t *data, uint32_t len) {
    uint16_t crc = 0xFFFF;
    for (uint32_t i = 0; i < len; i++) {
        crc ^= (uint16_t)data[i] << 8;
        for (int bit = 0; bit < 8; bit++)
            crc = (crc & 0x8000u) ? (uint16_t)((crc << 1) ^ 0x1021u)
                                  : (uint16_t)(crc << 1);
    }
    return crc;
}

static uint16_t rd16_le(const uint8_t *p) {
    return (uint16_t)(p[0] | ((uint16_t)p[1] << 8));
}

static uint32_t rd32_le(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static uint8_t validate_record(const uint8_t *rec) {
    if (rd32_le(rec + HREC_OFF_MAGIC) != HREC_MAGIC)
        return HREC_ERR_MAGIC;
    if (rec[HREC_OFF_RECORD_VERSION] != HREC_RECORD_VERSION)
        return HREC_ERR_RECORD_VERSION;
    if (rec[HREC_OFF_PROTOCOL_VERSION] != HREC_PROTOCOL_VERSION)
        return HREC_ERR_PROTOCOL_VERSION;
    if (rec[HREC_OFF_PROFILE] != EXPECTED_PROFILE)
        return HREC_ERR_PROFILE;
    if (rec[HREC_OFF_FE_PARAM] != EXPECTED_FE_PARAM)
        return HREC_ERR_FE_PARAM;
    if (rec[HREC_OFF_RESERVED] != 0)
        return HREC_ERR_RESERVED;
    if (rec[HREC_OFF_MAPPING_LEN_BYTES] != EXPECTED_MAPPING_LEN_BYTES ||
        rd16_le(rec + HREC_OFF_MAPPING_TAG) != EXPECTED_MAPPING_TAG)
        return HREC_ERR_MAPPING;
    if (rd16_le(rec + HREC_OFF_CRC) !=
        crc16_ccitt_false_buf(rec, HREC_OFF_CRC))
        return HREC_ERR_CRC;
    return HREC_OK;
}

static int receive_record(void) {
    uart_putchar('X');
    for (uint32_t i = 0; i < HREC_BYTES; i++) {
        if (!uart_getchar_timeout(&record_buf[i])) {
            send_failure(ERR_UART_TIMEOUT, 0);
            return 0;
        }
    }
    return 1;
}

static void load_helper_from_record(void) {
    for (int w = 0; w < 8; w++) {
        uint32_t word = 0;
        for (int b = 0; b < 4; b++)
            word |= ((uint32_t)record_buf[HREC_OFF_HELPER + w * 4 + b])
                    << (8 * b);
        HELPER_WORD(w) = word;
    }
    HELPER_WORD(8) = record_buf[HREC_OFF_HELPER + 32];
}

static void process_info(void) {
    uint8_t capabilities = CAP_SESSION_DIVERSIFICATION |
                           CAP_ACCELERATOR_ZEROIZE |
                           CAP_HELPER_RECORD;
#if !RELEASE_BUILD
    capabilities |= CAP_KEY_EXPORT;
#endif
    uart_putchar('K');
    uart_putchar('P');
    uart_putchar(PROTOCOL_MAJOR);
    uart_putchar(PROTOCOL_MINOR);
    uart_putchar(capabilities);
}

static void process_enroll(void) {
#if !EDGE_ALLOW_ENROLL
    // Operational/release lifecycle: manufacturing enrollment is forbidden.
    send_failure(ERR_ENROLL_FORBIDDEN, 0);
    return;
#else
    SYS_CTRL = SYS_ST_PUF_DONE;
    if (!wait_sys_status(SYS_ST_PUF_DONE)) {
        send_failure(ERR_PUF_TIMEOUT, 1);
        return;
    }

    SYS_CTRL = SYS_ST_FE_DONE;
    if (!wait_sys_status(SYS_ST_FE_DONE)) {
        send_failure(ERR_FE_TIMEOUT, 1);
        return;
    }

    // Same-root KCV: compute the public digest from the freshly generated FE
    // key while it is still live (the key never reaches the CPU; the hardware
    // engine taps it in place and only exposes the public KCV digest).
    uint8_t rec[HREC_BYTES];
    for (uint32_t i = 0; i < HREC_BYTES; i++)
        rec[i] = 0;
    kcv_write_ctx(ENROLL_CTX);
    KCV_CTRL = 0x01;
    uint32_t kcv_pass_ignored = 0;
    if (!kcv_wait(&kcv_pass_ignored)) {
        send_failure(ERR_KCV_TIMEOUT, 1);
        return;
    }
    kcv_read_out(&rec[HREC_OFF_KCV]);

    // helper_out is public and intentionally survives this request. Erase
    // the raw PUF response and reconstructed key before returning it.
    if (!secure_zeroize()) {
        send_failure(ERR_ZEROIZE_TIMEOUT, 0);
        return;
    }

    // Emit a versioned record: header + helper + real KCV + CRC.
    rec[HREC_OFF_MAGIC + 0] = (uint8_t)(HREC_MAGIC & 0xFF);
    rec[HREC_OFF_MAGIC + 1] = (uint8_t)((HREC_MAGIC >> 8) & 0xFF);
    rec[HREC_OFF_MAGIC + 2] = (uint8_t)((HREC_MAGIC >> 16) & 0xFF);
    rec[HREC_OFF_MAGIC + 3] = (uint8_t)((HREC_MAGIC >> 24) & 0xFF);
    rec[HREC_OFF_RECORD_VERSION] = HREC_RECORD_VERSION;
    rec[HREC_OFF_PROTOCOL_VERSION] = HREC_PROTOCOL_VERSION;
    rec[HREC_OFF_PROFILE] = EXPECTED_PROFILE;
    rec[HREC_OFF_FE_PARAM] = EXPECTED_FE_PARAM;
    rec[HREC_OFF_MAPPING_LEN_BYTES] = EXPECTED_MAPPING_LEN_BYTES;
    rec[HREC_OFF_MAPPING_TAG] = (uint8_t)(EXPECTED_MAPPING_TAG & 0xFF);
    rec[HREC_OFF_MAPPING_TAG + 1] = (uint8_t)((EXPECTED_MAPPING_TAG >> 8) & 0xFF);
    rec[HREC_OFF_GENERATION] = 0x01;
    for (int w = 0; w < 8; w++) {
        uint32_t word = HELPER_WORD(w);
        for (int b = 0; b < 4; b++)
            rec[HREC_OFF_HELPER + w * 4 + b] = (uint8_t)((word >> (8 * b)) & 0xFF);
    }
    rec[HREC_OFF_HELPER + 32] = (uint8_t)(HELPER_WORD(8) & 0xFF);
    uint16_t crc = crc16_ccitt_false_buf(rec, HREC_OFF_CRC);
    rec[HREC_OFF_CRC] = (uint8_t)(crc & 0xFF);
    rec[HREC_OFF_CRC + 1] = (uint8_t)((crc >> 8) & 0xFF);

    uart_putchar(STATUS_SUCCESS);
    for (uint32_t i = 0; i < HREC_BYTES; i++)
        uart_putchar(rec[i]);
#endif
}

static void process_recon(void) {
    if (!receive_record())
        return;
    if (validate_record(record_buf) != HREC_OK) {
        // Fail-closed: reject before PUF/FE/KDF/Kyber and scrub the buffer.
        send_failure(ERR_HELPER_RECORD, 1);
        return;
    }
    load_helper_from_record();

    uart_putchar('A');
    SYS_CTRL = SYS_ST_PUF_DONE;
    if (!wait_sys_status(SYS_ST_PUF_DONE)) {
        send_failure(ERR_PUF_TIMEOUT, 1);
        return;
    }
    uart_putchar('B');

    SYS_CTRL = SYS_ST_FE_DONE | SYS_ST_FE_SUCCESS;
    if (!wait_sys_status(SYS_ST_FE_DONE)) {
        send_failure(ERR_FE_TIMEOUT, 1);
        return;
    }
    uart_putchar('C');
    if (!(SYS_CTRL & SYS_ST_FE_SUCCESS)) {
        send_failure(ERR_FE_DECODE, 1);
        return;
    }

    // Same-root KCV verification: only a recovered root whose KCV matches the
    // hardware trusted anchor may reach the KDF/ML-KEM.  The helper-provided
    // KCV is not written anywhere; it is only a consistency input in the
    // anchor comparison.  Fail-closed: if no anchor is provisioned (KCV_CTRL
    // bit2 = 0) or the digest mismatches, no KDF/Kyber start.
    if (!(KCV_CTRL & 0x04)) {
        send_failure(ERR_KCV_UNPROVISIONED, 1);
        return;
    }
    kcv_write_ref(&record_buf[HREC_OFF_KCV]);
    kcv_write_ctx(kcv_ctx_from_record());
    KCV_CTRL = 0x01;
    uint32_t kcv_pass_result = 0;
    if (!kcv_wait(&kcv_pass_result)) {
        send_failure(ERR_KCV_TIMEOUT, 1);
        return;
    }
    if (!kcv_pass_result) {
        send_failure(ERR_KCV_MISMATCH, 1);
        return;
    }

    uart_putchar('D');
    SYS_CTRL = SYS_ST_KDF_DONE;
    if (!wait_sys_status(SYS_ST_KDF_DONE)) {
        send_failure(ERR_KDF_TIMEOUT, 1);
        return;
    }
    uart_putchar('E');

    // d and z are stable root-key-derived seeds. m is diversified for every
    // transaction using the secret KDF output, a monotonic in-boot counter
    // and the cycle counter. This prevents same-boot KEM randomness
    // reuse. It is not a substitute for a characterized TRNG in production.
    uint32_t session_mix = mix32(KDF_SEED(0) ^ read_cycle() ^ ++session_counter);
    uart_putchar('F');
    int key_match = 0;
    int final_attempt_timed_out = 0;
    for (uint32_t attempt = 0; attempt < KYBER_MAX_ATTEMPTS; attempt++) {
        if (attempt != 0 && !secure_zeroize()) {
            send_failure(ERR_ZEROIZE_TIMEOUT, 0);
            return;
        }

        session_mix = mix32(session_mix ^ read_cycle() ^
                            (0x9E3779B9u + attempt));
        for (int i = 0; i < 8; i++) {
            KYBER_SEED_D(i) = KDF_SEED(i);
            KYBER_SEED_Z(i) = KDF_SEED(i+8);
            session_mix = mix32(session_mix ^
                                (0x85EBCA6Bu + (uint32_t)i));
            KYBER_SEED_M(i) = KDF_SEED(i+8) ^ session_mix;
        }

        KYBER_PARAM = 2;
        if (KYBER_PARAM != 2 || (KYBER_STATUS & KYBER_ST_CONFIG_ERROR)) {
            send_failure(ERR_KYBER_CONFIG, 1);
            return;
        }
        KYBER_CTRL = 0x01;

        if (!wait_kyber_done()) {
            if (KYBER_STATUS & KYBER_ST_CONFIG_ERROR) {
                send_failure(ERR_KYBER_CONFIG, 1);
                return;
            }
            // Do not mask a core failure by trying a different message seed.
            final_attempt_timed_out = 1;
            continue;
        }
        final_attempt_timed_out = 0;
        if (KYBER_STATUS & KYBER_ST_KEY_MATCH) {
            key_match = 1;
            break;
        }
    }

    if (!key_match) {
        send_failure(final_attempt_timed_out ? ERR_KYBER_TIMEOUT
                                             : ERR_KEY_MISMATCH,
                     1);
        return;
    }
    uart_putchar('G');

#if !RELEASE_BUILD
    uint32_t server_key[8];
    for (int i = 0; i < 8; i++) {
        uint32_t key_word = KYBER_K_SERVER(i);
        server_key[i] = key_word;
    }
    if (!secure_zeroize()) {
        secure_zero_words(server_key, 8);
        send_failure(ERR_ZEROIZE_TIMEOUT, 0);
        return;
    }
    uart_putchar(STATUS_SUCCESS);
    uart_putchar(RESULT_KEY_FOLLOWS);
    for (int i = 0; i < 8; i++) {
        uint32_t key_word = server_key[i];
        uart_putchar((key_word >>  0) & 0xFF);
        uart_putchar((key_word >>  8) & 0xFF);
        uart_putchar((key_word >> 16) & 0xFF);
        uart_putchar((key_word >> 24) & 0xFF);
    }
    secure_zero_words(server_key, 8);
#else
    if (!secure_zeroize()) {
        send_failure(ERR_ZEROIZE_TIMEOUT, 0);
        return;
    }
    uart_putchar(STATUS_SUCCESS);
    uart_putchar(0x00);
#endif
}

int main(void) {
    session_counter = 0;
    uart_putchar('S');
    uart_putchar('T');
    uart_putchar('A');
    uart_putchar('R');
    uart_putchar('T');

    // SRAM contents are not guaranteed after an ASIC cold boot and can retain
    // secret data across a warm reset.  Scrub every crypto accelerator before
    // accepting the first host command.  A failed scrub is fail-closed: expose
    // the protocol error once, then never enter the command dispatcher.
    if (!secure_zeroize()) {
        uart_putchar(STATUS_FAIL);
        uart_putchar(ERR_ZEROIZE_TIMEOUT);
        while (1) { }
    }

    while (1) {
        uint8_t command = uart_getchar_blocking();
        if (command == CMD_INFO)
            process_info();
        else if (command == CMD_ENROLL)
            process_enroll();
        else if (command == CMD_RECON)
            process_recon();
        else
            uart_putchar('?');
    }
}
