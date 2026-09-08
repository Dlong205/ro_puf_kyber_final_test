#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "params.h"
#include "poly.h"
#include "polyvec.h"
#include "indcpa.h"
#include "symmetric.h"

static void print_packed_head(const char *label, const poly *p)
{
    unsigned int i;

    printf("%s", label);
    for (i = 0; i < 8; ++i) {
        uint16_t lo = (uint16_t)p->coeffs[2 * i];
        uint16_t hi = (uint16_t)p->coeffs[2 * i + 1];
        lo = (uint16_t)(lo + (((int16_t)lo >> 15) & KYBER_Q));
        hi = (uint16_t)(hi + (((int16_t)hi >> 15) & KYBER_Q));
        printf(" %06x", ((unsigned int)(hi & 0xfff) << 12) |
                          (unsigned int)(lo & 0xfff));
    }
    putchar('\n');
}

static void print_packed_all(const char *label, const poly *p)
{
    unsigned int i;

    printf("%s", label);
    for (i = 0; i < KYBER_N / 2; ++i) {
        uint16_t lo = (uint16_t)p->coeffs[2 * i];
        uint16_t hi = (uint16_t)p->coeffs[2 * i + 1];
        lo = (uint16_t)(lo + (((int16_t)lo >> 15) & KYBER_Q));
        hi = (uint16_t)(hi + (((int16_t)hi >> 15) & KYBER_Q));
        printf(" %06x", ((unsigned int)(hi & 0xfff) << 12) |
                          (unsigned int)(lo & 0xfff));
    }
    putchar('\n');
}

int main(void)
{
    static const uint8_t m[KYBER_SYMBYTES] = {
        0xdc, 0xac, 0xfe, 0x4d, 0xe1, 0xc1, 0x15, 0xda,
        0x10, 0x6a, 0xcd, 0x1e, 0xef, 0xea, 0xfd, 0xc7,
        0xf0, 0xf4, 0xe5, 0x70, 0x74, 0x53, 0xee, 0x2d,
        0x6b, 0x0d, 0x69, 0xd3, 0x4c, 0xc0, 0xef, 0x4a
    };
    /* Last 32 bytes of the ACVP encapsulation key are rho. */
    static const uint8_t rho[KYBER_SYMBYTES] = {
        0x07, 0x1d, 0x87, 0xb8, 0x2a, 0xbb, 0xdd, 0x6d,
        0x36, 0x9e, 0x32, 0x6e, 0x47, 0x53, 0x25, 0xed,
        0x5a, 0xe7, 0xed, 0x23, 0x2b, 0x37, 0xf4, 0x93,
        0x88, 0xc0, 0x6a, 0x74, 0x0d, 0x42, 0x12, 0x04
    };
    /* H(ek), obtained independently with SHA3-256 over the 800-byte ACVP ek. */
    static const uint8_t h_ek[KYBER_SYMBYTES] = {
        0xf3, 0x14, 0x04, 0xc1, 0xc6, 0x25, 0x03, 0x95,
        0x60, 0xad, 0xfe, 0x0b, 0xf4, 0x27, 0xc4, 0x50,
        0x2b, 0x11, 0x5f, 0xa8, 0xd0, 0x2d, 0x78, 0xb4,
        0xf2, 0xef, 0x1a, 0x45, 0x07, 0x8a, 0x1f, 0x80
    };
    uint8_t buf[2 * KYBER_SYMBYTES];
    uint8_t kr[2 * KYBER_SYMBYTES];
    polyvec at[KYBER_K];
    polyvec sp;
    polyvec ep;
    polyvec bp;
    poly epp;
    uint8_t prf_head[16];
    unsigned int i;

    memcpy(buf, m, KYBER_SYMBYTES);
    memcpy(buf + KYBER_SYMBYTES, h_ek, KYBER_SYMBYTES);
    hash_g(kr, buf, sizeof(buf));
    printf("K");
    for (i = 0; i < KYBER_SYMBYTES; ++i)
        printf("%02x", kr[i]);
    printf("\nR");
    for (i = KYBER_SYMBYTES; i < sizeof(kr); ++i)
        printf("%02x", kr[i]);
    putchar('\n');

    for (i = 0; i < 2 * KYBER_K + 1; ++i) {
        unsigned int j;
        kyber_shake256_prf(prf_head, sizeof(prf_head),
                           kr + KYBER_SYMBYTES, (uint8_t)i);
        printf("PRF%u", i);
        for (j = 0; j < sizeof(prf_head); ++j)
            printf("%02x", prf_head[j]);
        putchar('\n');
    }

    gen_matrix(at, rho, 1);
    print_packed_head("AT00_PACK", &at[0].vec[0]);
    print_packed_head("AT01_PACK", &at[0].vec[1]);
    print_packed_head("AT10_PACK", &at[1].vec[0]);
    print_packed_head("AT11_PACK", &at[1].vec[1]);

    for (i = 0; i < KYBER_K; ++i)
        poly_getnoise_eta1(&sp.vec[i], kr + KYBER_SYMBYTES, (uint8_t)i);
    for (i = 0; i < KYBER_K; ++i)
        poly_getnoise_eta2(&ep.vec[i], kr + KYBER_SYMBYTES,
                           (uint8_t)(KYBER_K + i));
    poly_getnoise_eta2(&epp, kr + KYBER_SYMBYTES, (uint8_t)(2 * KYBER_K));

    print_packed_head("SP0_CBD_PACK", &sp.vec[0]);
    print_packed_head("SP1_CBD_PACK", &sp.vec[1]);
    print_packed_head("EP0_CBD_PACK", &ep.vec[0]);
    print_packed_head("EP1_CBD_PACK", &ep.vec[1]);
    print_packed_head("EPP_CBD_PACK", &epp);
    print_packed_all("EP0_CBD_ALL", &ep.vec[0]);
    print_packed_all("EP1_CBD_ALL", &ep.vec[1]);
    print_packed_all("EPP_CBD_ALL", &epp);
    polyvec_ntt(&sp);
    print_packed_head("SP0_NTT_PACK", &sp.vec[0]);
    print_packed_head("SP1_NTT_PACK", &sp.vec[1]);
    for (i = 0; i < KYBER_K; ++i)
        polyvec_basemul_acc_montgomery(&bp.vec[i], &at[i], &sp);
    polyvec_invntt_tomont(&bp);
    print_packed_head("BP0_PRE_EP_PACK", &bp.vec[0]);
    print_packed_head("BP1_PRE_EP_PACK", &bp.vec[1]);
    print_packed_all("BP0_PRE_EP_ALL", &bp.vec[0]);
    print_packed_all("BP1_PRE_EP_ALL", &bp.vec[1]);
    polyvec_add(&bp, &bp, &ep);
    polyvec_reduce(&bp);
    print_packed_head("BP0_POST_EP_PACK", &bp.vec[0]);
    print_packed_head("BP1_POST_EP_PACK", &bp.vec[1]);
    return 0;
}
