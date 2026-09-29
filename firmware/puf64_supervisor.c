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

#define SUP_READY_MAGIC   0x52563332u /* "RV32" */
#define SUP_APPROVE_MAGIC 0x41505052u /* "APPR" */
#define SUP_IDENT_VALUE   0x50554632u /* "PUF2" */

int main(void)
{
    /* A wrong image must never become an operational supervisor. */
    if (SUP_IDENT != SUP_IDENT_VALUE)
        for (;;) { }

    SUP_READY = SUP_READY_MAGIC;

    for (;;) {
        uint32_t status = SUP_STATUS;
        if ((status & SUP_REQUIRED) == SUP_REQUIRED)
            SUP_APPROVE = SUP_APPROVE_MAGIC;
    }
}
