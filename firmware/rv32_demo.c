/* RV32 demo for the PicoRV32 supervisor sandbox (simulation only).
 * Proves: boot from BRAM, MMIO IDENT/STATUS/READY/APPROVE protocol, ALU +
 * multiply-free arithmetic, loop/branch, and trap-free execution.
 * Visible effects: cpu_ready, authorized_start, cpu_trap (checked by TB).
 */
#include <stdint.h>

#define MMIO32(addr) (*(volatile uint32_t *)(addr))

#define SUP_STATUS   MMIO32(0x10000000u)
#define SUP_READY    MMIO32(0x10000004u)
#define SUP_APPROVE  MMIO32(0x10000008u)
#define SUP_IDENT    MMIO32(0x1000000cu)

#define SUP_ST_PENDING       (1u << 0)
#define SUP_ST_COMMAND_OK    (1u << 1)
#define SUP_ST_ANCHOR_VALID  (1u << 2)
#define SUP_ST_MMCM_LOCKED   (1u << 3)
#define SUP_ST_CORE_IDLE     (1u << 4)
#define SUP_REQUIRED (SUP_ST_PENDING | SUP_ST_COMMAND_OK | \
                      SUP_ST_ANCHOR_VALID | SUP_ST_MMCM_LOCKED | \
                      SUP_ST_CORE_IDLE)

#define SUP_READY_MAGIC   0x52563332u
#define SUP_APPROVE_MAGIC 0x41505052u
#define SUP_IDENT_VALUE   0x50554632u

/* Iterative Fibonacci (no MUL/DIV: RV32I base only). */
static uint32_t fib(uint32_t n)
{
    uint32_t a = 0, b = 1;
    while (n-- > 0) {
        uint32_t t = a + b;
        a = b;
        b = t;
    }
    return a;
}

volatile uint32_t g_checksum;

int main(void)
{
    uint32_t i, acc = 0;

    if (SUP_IDENT != SUP_IDENT_VALUE)
        for (;;) { }

    /* ALU smoke: sum fib(0..15) = 1596 (0+1+1+2+...+610). */
    for (i = 0; i < 16; i++)
        acc += fib(i);
    g_checksum = acc;
    if (acc != 1596u)
        for (;;) { } /* hang on wrong ALU => TB sees no ready */

    SUP_READY = SUP_READY_MAGIC;

    for (;;) {
        uint32_t status = SUP_STATUS;
        if ((status & SUP_REQUIRED) == SUP_REQUIRED)
            SUP_APPROVE = SUP_APPROVE_MAGIC;
    }
}
