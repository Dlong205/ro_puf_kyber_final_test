#include <stdint.h>

#define REG(addr) (*((volatile uint32_t*)(addr)))

#define UART_DATA   REG(0x10000000)
#define UART_STATUS REG(0x10000004)
#define SYS_CTRL    REG(0x10000008)
#define HELPER_WORD(idx) REG(0x10000010 + (idx)*4)

#define KDF_SEED(idx)     REG(0x10000040 + (idx)*4)
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
#define PROTOCOL_MINOR 1

#define CMD_INFO   0x00
#define CMD_ENROLL 0x01
#define CMD_RECON  0x02

#define STATUS_SUCCESS 0xAA
#define STATUS_FAIL    0xFF

#define RESULT_KEY_FOLLOWS (1u << 0)
#define CAP_KEY_EXPORT     (1u << 0)
#define CAP_SESSION_DIVERSIFICATION (1u << 1)
#define CAP_KYBER_ZEROIZE  (1u << 2)
#define CAP_KYBER_RETRY    (1u << 3)

#define ERR_UART_TIMEOUT  0x01
#define ERR_PUF_TIMEOUT   0x02
#define ERR_FE_TIMEOUT    0x03
#define ERR_FE_DECODE     0x04
#define ERR_KDF_TIMEOUT   0x05
#define ERR_KYBER_CONFIG  0x06
#define ERR_KYBER_TIMEOUT 0x07
#define ERR_KEY_MISMATCH  0x08

#define KYBER_ST_DONE         (1u << 2)
#define KYBER_ST_BUSY         (1u << 3)
#define KYBER_ST_CONFIG_ERROR (1u << 4)
#define KYBER_ST_KEY_MATCH    (1u << 5)

#define HW_TIMEOUT      20000000u
#define KYBER_TIMEOUT    2000000u
#define UART_TIMEOUT    50000000u
#define KYBER_MAX_ATTEMPTS 16u

static uint32_t session_counter;

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

static int wait_kyber_done(void) {
    // A normal KEM finishes far below this bound. Keep a shorter Kyber-only
    // watchdog so a rare stuck legacy-core input can be reset and retried
    // without blocking the UART protocol for tens of seconds per attempt.
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

static void kyber_zeroize(void) {
    // CTRL[1] resets both Kyber cores and clears all seed/status registers.
    KYBER_CTRL = 0x02;
}

static void send_failure(uint8_t code, int clear_kyber) {
    if (clear_kyber)
        kyber_zeroize();
    uart_putchar(STATUS_FAIL);
    uart_putchar(code);
}

static void process_info(void) {
    uint8_t capabilities = CAP_SESSION_DIVERSIFICATION |
                           CAP_KYBER_ZEROIZE |
                           CAP_KYBER_RETRY;
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
    SYS_CTRL = 0x01;
    if (!wait_sys_status(0x01)) {
        send_failure(ERR_PUF_TIMEOUT, 0);
        return;
    }

    SYS_CTRL = 0x02;
    if (!wait_sys_status(0x02)) {
        send_failure(ERR_FE_TIMEOUT, 0);
        return;
    }

    uart_putchar(STATUS_SUCCESS);
    for (int w = 0; w < 8; w++) {
        uint32_t word = HELPER_WORD(w);
        uart_putchar((word >>  0) & 0xFF);
        uart_putchar((word >>  8) & 0xFF);
        uart_putchar((word >> 16) & 0xFF);
        uart_putchar((word >> 24) & 0xFF);
    }
    uart_putchar(HELPER_WORD(8) & 0xFF);
}

static int receive_helper(void) {
    uint8_t byte;
    uart_putchar('X');
    for (int w = 0; w < 8; w++) {
        uint32_t word = 0;
        for (int b = 0; b < 4; b++) {
            if (!uart_getchar_timeout(&byte)) {
                send_failure(ERR_UART_TIMEOUT, 0);
                return 0;
            }
            word |= ((uint32_t)byte) << (8 * b);
        }
        HELPER_WORD(w) = word;
        uart_putchar('0' + w);
    }
    if (!uart_getchar_timeout(&byte)) {
        send_failure(ERR_UART_TIMEOUT, 0);
        return 0;
    }
    HELPER_WORD(8) = byte;
    uart_putchar('8');
    return 1;
}

static void process_recon(void) {
    if (!receive_helper())
        return;

    uart_putchar('A');
    SYS_CTRL = 0x01;
    if (!wait_sys_status(0x01)) {
        send_failure(ERR_PUF_TIMEOUT, 0);
        return;
    }
    uart_putchar('B');

    SYS_CTRL = 0x06;
    if (!wait_sys_status(0x02)) {
        send_failure(ERR_FE_TIMEOUT, 0);
        return;
    }
    uart_putchar('C');
    if (!(SYS_CTRL & 0x04)) {
        send_failure(ERR_FE_DECODE, 0);
        return;
    }

    uart_putchar('D');
    SYS_CTRL = 0x08;
    if (!wait_sys_status(0x08)) {
        send_failure(ERR_KDF_TIMEOUT, 0);
        return;
    }
    uart_putchar('E');

    // d and z are stable root-key-derived seeds. m is diversified for every
    // transaction and retry using the secret KDF output, a monotonic in-boot
    // counter and the cycle counter. This prevents same-boot KEM randomness
    // reuse. It is not a substitute for a characterized TRNG in production.
    uint32_t session_mix = mix32(KDF_SEED(0) ^ read_cycle() ^ ++session_counter);
    uart_putchar('F');
    int key_match = 0;
    int final_attempt_timed_out = 0;
    for (uint32_t attempt = 0; attempt < KYBER_MAX_ATTEMPTS; attempt++) {
        if (attempt != 0)
            kyber_zeroize();

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
            // Some seed combinations can stall the imported legacy core.
            // Treat that raw attempt like a mismatch: reset both cores and
            // try a freshly diversified m, within the same bounded budget.
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

    uart_putchar(STATUS_SUCCESS);
#if !RELEASE_BUILD
    uint32_t server_key[8];
    uart_putchar(RESULT_KEY_FOLLOWS);
    for (int i = 0; i < 8; i++) {
        uint32_t key_word = KYBER_K_SERVER(i);
        server_key[i] = key_word;
        uart_putchar((key_word >>  0) & 0xFF);
        uart_putchar((key_word >>  8) & 0xFF);
        uart_putchar((key_word >> 16) & 0xFF);
        uart_putchar((key_word >> 24) & 0xFF);
    }
    secure_zero_words(server_key, 8);
#else
    uart_putchar(0x00);
#endif
    kyber_zeroize();
}

int main(void) {
    session_counter = 0;
    uart_putchar('S');
    uart_putchar('T');
    uart_putchar('A');
    uart_putchar('R');
    uart_putchar('T');
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
