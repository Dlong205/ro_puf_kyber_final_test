#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "params.h"
#include "poly.h"
#include "polyvec.h"
#include "indcpa.h"
#include "symmetric.h"

static void print_poly_head(const char *label, const poly *p)
{
    unsigned int i;

    printf("%s", label);
    for (i = 0; i < 16; ++i)
        printf(" %d", p->coeffs[i]);
    putchar('\n');
}

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

int main(void)
{
    static const uint8_t d[KYBER_SYMBYTES] = {
        0x47, 0xb8, 0x93, 0x47, 0x46, 0x72, 0xba, 0x92,
        0xe4, 0xb1, 0x2e, 0xe4, 0x4f, 0xb3, 0x29, 0x53,
        0xaf, 0x8e, 0x85, 0x03, 0xb5, 0xfb, 0x47, 0x1d,
        0x16, 0x14, 0xfb, 0x8a, 0x02, 0x1a, 0x66, 0x0a
    };
    uint8_t expanded[2 * KYBER_SYMBYTES];
    uint8_t ek[KYBER_INDCPA_PUBLICKEYBYTES];
    uint8_t dk_pke[KYBER_INDCPA_SECRETKEYBYTES];
    polyvec matrix[KYBER_K];
    polyvec s;
    polyvec e;
    polyvec t;
    unsigned int i;

    memcpy(expanded, d, sizeof(d));
    expanded[KYBER_SYMBYTES] = KYBER_K;
    hash_g(expanded, expanded, KYBER_SYMBYTES + 1);

    gen_matrix(matrix, expanded, 0);
    print_packed_head("A00_PACK", &matrix[0].vec[0]);
    print_packed_head("A01_PACK", &matrix[0].vec[1]);
    print_packed_head("A10_PACK", &matrix[1].vec[0]);
    print_packed_head("A11_PACK", &matrix[1].vec[1]);
    for (i = 0; i < KYBER_K; ++i)
        poly_getnoise_eta1(&s.vec[i], expanded + KYBER_SYMBYTES, (uint8_t)i);
    for (i = 0; i < KYBER_K; ++i)
        poly_getnoise_eta1(&e.vec[i], expanded + KYBER_SYMBYTES,
                           (uint8_t)(KYBER_K + i));

    print_poly_head("S0_CBD", &s.vec[0]);
    print_poly_head("S1_CBD", &s.vec[1]);
    print_poly_head("E0_CBD", &e.vec[0]);
    print_poly_head("E1_CBD", &e.vec[1]);
    print_packed_head("S0_CBD_PACK", &s.vec[0]);
    print_packed_head("S1_CBD_PACK", &s.vec[1]);
    print_packed_head("E0_CBD_PACK", &e.vec[0]);
    print_packed_head("E1_CBD_PACK", &e.vec[1]);

    polyvec_ntt(&s);
    polyvec_ntt(&e);
    print_packed_head("S0_NTT_PACK", &s.vec[0]);
    print_packed_head("S1_NTT_PACK", &s.vec[1]);
    print_packed_head("E0_NTT_PACK", &e.vec[0]);
    print_packed_head("E1_NTT_PACK", &e.vec[1]);

    for (i = 0; i < KYBER_K; ++i) {
        polyvec_basemul_acc_montgomery(&t.vec[i], &matrix[i], &s);
        poly_tomont(&t.vec[i]);
    }
    polyvec_add(&t, &t, &e);
    polyvec_reduce(&t);
    print_packed_head("T0_PACK", &t.vec[0]);
    print_packed_head("T1_PACK", &t.vec[1]);

    indcpa_keypair_derand(ek, dk_pke, d);
    printf("EK_HEAD");
    for (i = 0; i < 32; ++i)
        printf("%02x", ek[i]);
    putchar('\n');
    return 0;
}
