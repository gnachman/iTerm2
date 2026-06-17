// swift-tools-version: 5.9

import PackageDescription

// CompanionCore holds the code shared between the macOS iTerm2 app and the
// iTerm2 Companion iOS app. Everything in CompanionProtocol must build on both
// platforms, so nothing there may import AppKit, UIKit, or any iTerm2 type.
//
// Layering (bottom to top):
//   CNoise            - the vendored rweather/noise-c C library (submodule
//                       under Sources/CNoise/vendor) compiled down to just the
//                       primitives Noise_XK_25519_ChaChaPoly_BLAKE2s needs,
//                       plus a Swift-facing umbrella header.
//   CompanionProtocol - pure-Swift wire DTOs, pairing-code parsing, the
//                       transport abstraction, and the framed RPC envelope.
//   CompanionNoise    - the Noise XK handshake driver and the encrypted
//                       NoiseChannel (a MessageTransport that wraps another
//                       MessageTransport), built on CNoise + CompanionProtocol.
let package = Package(
    name: "CompanionCore",
    platforms: [
        .macOS(.v12),
        .iOS(.v16)
    ],
    products: [
        .library(name: "CompanionProtocol", targets: ["CompanionProtocol"]),
        .library(name: "CompanionNoise", targets: ["CompanionNoise"]),
        .library(name: "CompanionTransport", targets: ["CompanionTransport"])
    ],
    targets: [
        // The reference-backend subset of noise-c. We compile only the
        // protocol core plus Curve25519 / ChaChaPoly / BLAKE2s and stub the
        // other primitive constructors (see shim/cnoise_stubs.c), avoiding the
        // x86-assembly NewHope / Curve448 / Ed25519 sources XK never touches.
        .target(
            name: "CNoise",
            path: "Sources/CNoise",
            sources: [
                "shim/cnoise_stubs.c",
                // noise-c protocol core (rand_sodium.c omitted: reference build
                // uses rand_os.c for OS entropy, no libsodium).
                "vendor/src/protocol/cipherstate.c",
                "vendor/src/protocol/dhstate.c",
                "vendor/src/protocol/errors.c",
                "vendor/src/protocol/handshakestate.c",
                "vendor/src/protocol/hashstate.c",
                "vendor/src/protocol/internal.c",
                "vendor/src/protocol/names.c",
                "vendor/src/protocol/patterns.c",
                "vendor/src/protocol/randstate.c",
                "vendor/src/protocol/signstate.c",
                "vendor/src/protocol/symmetricstate.c",
                "vendor/src/protocol/util.c",
                "vendor/src/protocol/rand_os.c",
                // XK primitives (reference backend).
                "vendor/src/backend/ref/cipher-chachapoly.c",
                "vendor/src/backend/ref/dh-curve25519.c",
                "vendor/src/backend/ref/hash-blake2s.c",
                // Reference crypto these primitives include. curve25519-donna
                // is #included directly by dh-curve25519.c, so it is not listed.
                "vendor/src/crypto/chacha/chacha.c",
                "vendor/src/crypto/blake2/blake2s.c",
                "vendor/src/crypto/donna/poly1305-donna.c",
                // SHA-256 is pulled in by util.c's fingerprint formatter.
                "vendor/src/crypto/sha2/sha256.c"
            ],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("vendor/include"),
                .headerSearchPath("vendor/src"),
                .headerSearchPath("vendor/src/protocol")
            ]
        ),
        .target(
            name: "CompanionProtocol",
            path: "Sources/CompanionProtocol"
        ),
        .target(
            name: "CompanionNoise",
            dependencies: ["CompanionProtocol", "CNoise"],
            path: "Sources/CompanionNoise"
        ),
        .target(
            name: "CompanionTransport",
            dependencies: ["CompanionProtocol"],
            path: "Sources/CompanionTransport"
        ),
        .testTarget(
            name: "CompanionProtocolTests",
            dependencies: ["CompanionProtocol"],
            path: "Tests/CompanionProtocolTests"
        ),
        .testTarget(
            name: "CompanionNoiseTests",
            dependencies: ["CompanionNoise"],
            path: "Tests/CompanionNoiseTests"
        ),
        .testTarget(
            name: "CompanionTransportTests",
            dependencies: ["CompanionTransport", "CompanionNoise"],
            path: "Tests/CompanionTransportTests"
        )
    ]
)
