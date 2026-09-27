#!/bin/bash
#
# Rebuild tools/sign_update as a universal (arm64 + x86_64) binary.
#
# sign_update signs a release zip with the EdDSA (ed25519) private key that is
# passed on the command line (NOT read from the keychain, unlike upstream
# Sparkle's tool -- the keychain path was flaky and broke the nightly build).
# release_stable.sh calls it as:  sign_update <zip> <base64-key>
#
# Provenance (this is the "hard part" to find again):
#   * Source: iTerm2's Sparkle fork, https://github.com/gnachman/Sparkle.git
#     branch forked_1.21.2, file sign_update/main.swift, pinned at commit
#     d163511d43fa00d5b661b4f57b5f192b6c35df93 (recorded in the release commit
#     781f07fea "Fix nightly build. Update sign_update ...").
#   * ed25519: git submodule of that fork, https://github.com/orlp/ed25519
#     (commit 7fa6712ef5d581a6981ec2b08ee623314cd1d1c4). ed25519 signatures are
#     deterministic (RFC 8032), so a rebuild is byte-identical to the original.
#
# main.swift below is that file with only its unsafe-pointer closures updated for
# current Swift (the old UnsafePointer<UInt8> closure overloads were removed).
# The behavior -- key blob is base64(priv[64] || pub[32]); print base64 of the
# 64-byte ed25519 signature -- is unchanged. build verifies the result against a
# direct C ed25519_sign call before installing.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FORK_URL="https://github.com/gnachman/Sparkle.git"
FORK_COMMIT="d163511d43fa00d5b661b4f57b5f192b6c35df93"

# Prefer an existing local checkout of the fork; otherwise clone it.
SPARKLE=""
for cand in "$HOME/git/Sparkle" "$REPO_ROOT/submodules/Sparkle"; do
    if [ -d "$cand/.git" ] || [ -f "$cand/.git" ]; then
        if git -C "$cand" cat-file -e "$FORK_COMMIT^{commit}" 2>/dev/null; then
            SPARKLE="$cand"
            break
        fi
    fi
done
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
if [ -z "$SPARKLE" ]; then
    echo "Cloning Sparkle fork..."
    git clone "$FORK_URL" "$WORKDIR/Sparkle"
    SPARKLE="$WORKDIR/Sparkle"
fi

# ed25519 C sources at the pinned tree.
SRC="$SPARKLE/ed25519/src"
if [ ! -f "$SRC/ed25519.h" ]; then
    git -C "$SPARKLE" submodule update --init ed25519
fi
[ -f "$SRC/ed25519.h" ] || { echo "ERROR: ed25519 sources not found at $SRC" >&2; exit 1; }

B="$WORKDIR/build"
mkdir -p "$B"

cat > "$B/main.swift" <<'SWIFT'
import Foundation

func findKeys(_ encoded: String) -> (Data, Data) {
    if let keys = Data(base64Encoded: encoded) {
        return (keys[0..<64], keys[64..<(64 + 32)])
    }
    print("Base64 error")
    exit(1)
}

func edSignature(data: Data, publicEdKey: Data, privateEdKey: Data) -> String {
    assert(publicEdKey.count == 32)
    assert(privateEdKey.count == 64)
    let len = data.count
    var output = Data(count: 64)
    output.withUnsafeMutableBytes { (outputBuf: UnsafeMutableRawBufferPointer) in
        data.withUnsafeBytes { (dataBuf: UnsafeRawBufferPointer) in
            publicEdKey.withUnsafeBytes { (pubBuf: UnsafeRawBufferPointer) in
                privateEdKey.withUnsafeBytes { (privBuf: UnsafeRawBufferPointer) in
                    ed25519_sign(
                        outputBuf.bindMemory(to: UInt8.self).baseAddress!,
                        dataBuf.bindMemory(to: UInt8.self).baseAddress!,
                        len,
                        pubBuf.bindMemory(to: UInt8.self).baseAddress!,
                        privBuf.bindMemory(to: UInt8.self).baseAddress!)
                }
            }
        }
    }
    return output.base64EncodedString()
}

let args = CommandLine.arguments
if args.count != 3 {
    print("Usage: \(args[0]) <archive to sign> <key>.\n")
    exit(1)
}

let (priv, pub) = findKeys(args[2])

do {
    let data = try Data(contentsOf: URL(fileURLWithPath: args[1]), options: .mappedIfSafe)
    let sig = edSignature(data: data, publicEdKey: pub, privateEdKey: priv)
    print(sig)
} catch {
    print("ERROR: ", error)
}
SWIFT

echo '#import "ed25519.h"' > "$B/bridge.h"

SDK="$(xcrun --show-sdk-path)"
for arch in arm64 x86_64; do
    echo "Building $arch..."
    mkdir -p "$B/obj-$arch"
    for c in "$SRC"/*.c; do
        clang -c -O2 -arch "$arch" -mmacosx-version-min=12.0 -I"$SRC" \
            "$c" -o "$B/obj-$arch/$(basename "$c" .c).o"
    done
    swiftc -O -sdk "$SDK" -target "${arch}-apple-macos12.0" \
        -import-objc-header "$B/bridge.h" -Xcc -I"$SRC" \
        "$B/main.swift" "$B"/obj-"$arch"/*.o -o "$B/sign_update-$arch"
done
lipo -create "$B/sign_update-arm64" "$B/sign_update-x86_64" -output "$B/sign_update"

# Verify against a direct C ed25519_sign call: build a keypair from a fixed seed,
# sign a message in C, and confirm sign_update produces the identical signature.
cat > "$B/harness.c" <<'C'
#include <stdio.h>
#include <string.h>
#include "ed25519.h"
int main(void) {
    unsigned char seed[32], pub[32], priv[64], sig[64];
    for (int i = 0; i < 32; i++) seed[i] = (unsigned char)i;
    ed25519_create_keypair(pub, priv, seed);
    const char *msg = "iTerm2 sign_update compatibility check";
    size_t mlen = strlen(msg);
    ed25519_sign(sig, (const unsigned char *)msg, mlen, pub, priv);
    FILE *k = fopen("KEYFILE", "wb"); fwrite(priv,1,64,k); fwrite(pub,1,32,k); fclose(k);
    FILE *m = fopen("MSGFILE", "wb"); fwrite(msg,1,mlen,m); fclose(m);
    FILE *s = fopen("SIGFILE", "wb"); fwrite(sig,1,64,s); fclose(s);
    return ed25519_verify(sig,(const unsigned char *)msg,mlen,pub) ? 0 : 1;
}
C
sed -i '' -e "s#KEYFILE#$B/key.bin#; s#MSGFILE#$B/msg.bin#; s#SIGFILE#$B/sig_c.bin#" "$B/harness.c"
clang -O2 -arch arm64 -I"$SRC" "$B/harness.c" "$B"/obj-arm64/*.o -o "$B/harness"
"$B/harness"
KEY="$(base64 < "$B/key.bin")"
SIG_C="$(base64 < "$B/sig_c.bin")"
SIG_SWIFT="$("$B/sign_update" "$B/msg.bin" "$KEY")"
if [ "$SIG_C" != "$SIG_SWIFT" ]; then
    echo "ERROR: rebuilt sign_update does not match direct C ed25519_sign" >&2
    exit 1
fi

install -m 0755 "$B/sign_update" "$REPO_ROOT/tools/sign_update"
echo "Installed universal sign_update to $REPO_ROOT/tools/sign_update"
file "$REPO_ROOT/tools/sign_update"
