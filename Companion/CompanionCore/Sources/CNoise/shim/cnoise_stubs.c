/*
 * cnoise_stubs.c
 * CNoise
 *
 * This build compiles only the noise-c primitives needed for
 * Noise_XK_25519_ChaChaPoly_BLAKE2s (Curve25519, ChaChaPoly, BLAKE2s) plus the
 * protocol core. Two kinds of symbols would otherwise be left undefined at link
 * time, and we satisfy both here so we never pull in the heavy and
 * x86-assembly-laden NewHope / Curve448 / Ed25519 sources XK never touches:
 *
 *   1. Primitive constructors the *_new_by_id() dispatchers reference
 *      unconditionally (see noise_dhstate_new_by_id et al.). For the primitives
 *      we deliberately leave out, returning NULL is correct: asking for one by
 *      name simply fails with NOISE_ERROR_NO_MEMORY / UNKNOWN_ID. Note that
 *      noise_aesgcm_new() itself lives in internal.c and dispatches to
 *      noise_aesgcm_new_ref(), so it is that *_ref entry point we stub, not
 *      noise_aesgcm_new().
 *
 *   2. curved25519_scalarmult_basepoint(), which dh-curve25519.c uses to derive
 *      a public key from a (clamped) private key. Upstream this lives in the
 *      ed25519-donna sources; we provide it via curve25519-donna instead, which
 *      is already compiled in (dh-curve25519.c #includes it). The public key is
 *      X25519(secret, 9), and dh-curve25519.c has already applied the standard
 *      X25519 clamping to the scalar, so the two donna implementations agree.
 */

#include <noise/protocol.h>
#include <stdint.h>

/* Provided by curve25519-donna (compiled via dh-curve25519.c). */
extern int curve25519_donna(uint8_t *mypublic,
                            const uint8_t *secret,
                            const uint8_t *basepoint);

/* Unused primitive constructors. */
NoiseCipherState *noise_aesgcm_new_ref(void) { return 0; }
NoiseHashState *noise_blake2b_new(void) { return 0; }
NoiseHashState *noise_sha256_new(void) { return 0; }
NoiseHashState *noise_sha512_new(void) { return 0; }
NoiseDHState *noise_curve448_new(void) { return 0; }
NoiseDHState *noise_newhope_new(void) { return 0; }
NoiseSignState *noise_ed25519_new(void) { return 0; }

/* Public-key derivation for Curve25519, backed by curve25519-donna. */
void curved25519_scalarmult_basepoint(uint8_t pk[32], const uint8_t e[32])
{
    static const uint8_t basepoint[32] = { 9 };
    curve25519_donna(pk, e, basepoint);
}
