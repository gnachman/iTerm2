#!/bin/bash
#
# Build a fat (x86_64 + arm64) macOS uv binary from source at a pinned revision
# and package it as a .tar.gz laid out exactly like Astral's official uv
# distribution (a top-level uv-<triple>/ directory containing the uv and uvx
# executables). The only intended difference from the official per-arch tarballs
# (e.g. uv-aarch64-apple-darwin.tar.gz) is that ours is a universal binary and it
# targets a higher macOS floor.
#
# This mirrors uv's own release recipe, read from the pinned checkout:
#   - .github/workflows/build-release-binaries.yml (the macos-x86_64 /
#     macos-aarch64 jobs): cargo build --release --locked --features self-update,
#     then copy target/<triple>/release/{uv,uvx} into uv-<triple>/ and tar czf.
#   - Cargo.toml [profile.release]: strip=true, lto="fat", panic="abort" (used
#     automatically by --release; not re-specified here).
#   - dist-workspace.toml unix-archive = ".tar.gz" (so macOS ships tar.gz, which
#     is what iTermUvProvisioner extracts with `tar -xzf`).
#
# Deliberate deviations from the upstream CI recipe, none of which change what uv
# does at runtime:
#   - macOS deployment target is raised to 13.0 (uv's supported floor and the
#     iTerm2 uv-migration target) via MACOSX_DEPLOYMENT_TARGET. Upstream leaves
#     the Rust default (11.0 on arm64, 10.12 on x86_64).
#   - Two per-arch builds are lipo'd into one universal binary. Upstream ships
#     separate per-arch tarballs.
#   - We do not wrap cargo with `cargo auditable` (upstream embeds an SBOM). That
#     only adds metadata; skipping it avoids installing an extra cargo extension.
#   - We do not force Rust's ld64.lld with ICF (upstream shaves ~2% off the binary
#     size that way). The default linker is used for robustness; set
#     UV_BUILD_RUSTFLAGS to opt back in.
#   - We codesign the result with a Developer ID Application identity (hardened
#     runtime + secure timestamp) instead of leaving it ad-hoc/linker-signed, so
#     the distributed binary carries a real signature. Use --no-sign for an
#     ad-hoc signature that matches the official tarballs.
#
# The RSA signature that iTermSignatureVerifier checks is a separate step,
# handled by tools/sign_and_copy_uv.sh. Pass --rsa-key to run it automatically on
# success: build_uv.sh then hands the freshly built archive (as a file:// URL) to
# sign_and_copy_uv.sh, which stages it in the website downloads directory and
# writes the RSA-SHA256 .sig alongside it.
#
# Usage:
#   tools/build_uv.sh [--rev REV] [--output DIR] [--identity ID | --no-sign]
#                     [--deployment-target VERSION] [--triple NAME]
#                     [--rsa-key PATH] [--keep-temp]
#
# Example:
#   tools/build_uv.sh --rev 0.12.0 --output ~/uv-dist
#   tools/build_uv.sh --rev 0.12.0 --rsa-key ~/keys/iterm2-uv.pem
#
# Compare the result against the official reference tarball to confirm the layout:
#   tar tzvf uv-universal2-apple-darwin.tar.gz
#   tar tzvf ~/Downloads/uv-aarch64-apple-darwin.tar.gz

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ---- Defaults -------------------------------------------------------------

REV="0.12.0"
OUTPUT_DIR="$PWD"
DEPLOYMENT_TARGET="13.0"
ARCHIVE_TRIPLE="universal2-apple-darwin"
UV_REPO="https://github.com/astral-sh/uv.git"
SIGN=1
IDENTITY=""
KEEP_TEMP=0
# When set, sign_and_copy_uv.sh is invoked on success to apply the iTerm2 RSA
# signature and stage the archive in the website downloads directory.
RSA_KEY=""

# The two architectures we build and fuse. arm64 first is irrelevant; lipo
# normalizes the order.
BUILD_TARGETS=("x86_64-apple-darwin" "aarch64-apple-darwin")

# ---- Argument parsing -----------------------------------------------------

usage() {
    sed -n '2,53p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --rev) REV="$2"; shift 2 ;;
        --output) OUTPUT_DIR="$2"; shift 2 ;;
        --identity) IDENTITY="$2"; SIGN=1; shift 2 ;;
        --no-sign) SIGN=0; shift ;;
        --deployment-target) DEPLOYMENT_TARGET="$2"; shift 2 ;;
        --triple) ARCHIVE_TRIPLE="$2"; shift 2 ;;
        --rsa-key) RSA_KEY="$2"; shift 2 ;;
        --keep-temp) KEEP_TEMP=1; shift ;;
        -h|--help) usage 0 ;;
        *) echo "Unknown argument: $1" >&2; usage 1 ;;
    esac
done

ARCHIVE_NAME="uv-${ARCHIVE_TRIPLE}"
# Version-qualify the output filename when --rev is a real uv version, so the file
# staged and published is self-describing and immutable per version (sign_and_copy_uv.sh
# derives the hosted name from this basename and must never clobber a prior release's
# bytes that an older manifest entry still references). The tarball's internal top-level
# directory stays uv-<triple>/ (the app locates the binary one level down regardless).
if [[ "$REV" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    ARCHIVE_FILE="uv-${REV}-${ARCHIVE_TRIPLE}.tar.gz"
else
    ARCHIVE_FILE="${ARCHIVE_NAME}.tar.gz"
fi

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }

# ---- Preflight ------------------------------------------------------------

for tool in git cargo rustc rustup lipo tar shasum codesign vtool; do
    command -v "$tool" >/dev/null 2>&1 || die "required tool not found: $tool"
done

# Validate the sign-and-copy prerequisites up front so a bad key does not waste a
# full (slow) build before failing.
SIGN_AND_COPY="$SCRIPT_DIR/sign_and_copy_uv.sh"
if [[ -n "$RSA_KEY" ]]; then
    [[ -x "$SIGN_AND_COPY" ]] || die "sign_and_copy_uv.sh not found or not executable: $SIGN_AND_COPY"
    [[ -f "$RSA_KEY" ]] || die "RSA private key not found: $RSA_KEY"
fi

if [[ "$SIGN" -eq 1 && -z "$IDENTITY" ]]; then
    # Prefer a Developer ID Application identity; fall back to ad-hoc if none.
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | awk '/Developer ID Application/ {print $2; exit}')"
    if [[ -z "$IDENTITY" ]]; then
        log "No Developer ID Application identity found; using an ad-hoc signature."
        SIGN=0
    fi
fi

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/build_uv.XXXXXX")"
cleanup() {
    if [[ "$KEEP_TEMP" -eq 1 ]]; then
        log "Leaving work directory in place: $WORK"
    else
        rm -rf "$WORK"
    fi
}
trap cleanup EXIT

# ---- Clone the pinned revision -------------------------------------------

CLONE="$WORK/uv"
log "Cloning uv at $REV"
# --depth 1 on the tag/branch is enough; fall back to a full clone + checkout for
# revisions that are not directly fetchable (e.g. a bare commit SHA).
if ! git clone --depth 1 --branch "$REV" "$UV_REPO" "$CLONE" 2>/dev/null; then
    log "Shallow tag clone failed; doing a full clone to resolve $REV"
    git clone "$UV_REPO" "$CLONE"
    git -C "$CLONE" checkout "$REV"
fi
RESOLVED_SHA="$(git -C "$CLONE" rev-parse HEAD)"
log "Building uv $REV ($RESOLVED_SHA)"

# Optional supply-chain pin: because --rev may be a mutable tag/branch, allow the
# caller to assert the exact commit it must resolve to. A mismatch means the tag
# was moved (or points somewhere unexpected), so abort rather than build it.
if [[ -n "${UV_EXPECTED_COMMIT:-}" ]]; then
    if [[ "$RESOLVED_SHA" != "$UV_EXPECTED_COMMIT" ]]; then
        die "resolved commit $RESOLVED_SHA does not match UV_EXPECTED_COMMIT $UV_EXPECTED_COMMIT (tag $REV may have moved)"
    fi
    log "Verified resolved commit matches UV_EXPECTED_COMMIT"
fi

# ---- Build each architecture ---------------------------------------------

export MACOSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET"
# CARGO_INCREMENTAL=0 matches the release environment and avoids incremental
# artifacts leaking into a release build.
export CARGO_INCREMENTAL=0
if [[ -n "${UV_BUILD_RUSTFLAGS:-}" ]]; then
    export RUSTFLAGS="$UV_BUILD_RUSTFLAGS"
fi

TARGET_DIR="$CLONE/target"
for target in "${BUILD_TARGETS[@]}"; do
    log "Ensuring Rust target is installed: $target"
    # Add the target from inside the clone so uv's rust-toolchain.toml override
    # applies and the std component lands on the toolchain cargo will actually
    # use (uv pins a specific channel), not the caller's default toolchain.
    ( cd "$CLONE" && rustup target add "$target" ) >/dev/null 2>&1 || true

    log "Building uv + uvx for $target (macOS $DEPLOYMENT_TARGET floor, this is slow: fat LTO)"
    ( cd "$CLONE" && cargo build \
        --release \
        --locked \
        --features self-update \
        --package uv \
        --target "$target" )

    for bin in uv uvx; do
        [[ -f "$TARGET_DIR/$target/release/$bin" ]] \
            || die "expected binary missing after build: $TARGET_DIR/$target/release/$bin"
    done
done

# ---- Fuse into a universal binary ----------------------------------------

STAGE="$WORK/$ARCHIVE_NAME"
mkdir -p "$STAGE"

for bin in uv uvx; do
    log "Fusing $bin into a universal binary"
    lipo -create \
        "$TARGET_DIR/x86_64-apple-darwin/release/$bin" \
        "$TARGET_DIR/aarch64-apple-darwin/release/$bin" \
        -output "$STAGE/$bin"
    chmod 755 "$STAGE/$bin"

    archs="$(lipo -archs "$STAGE/$bin")"
    [[ "$archs" == *x86_64* && "$archs" == *arm64* ]] \
        || die "$bin is not universal (archs: $archs)"

    # Confirm both slices actually carry the requested deployment floor.
    for arch in x86_64 arm64; do
        minos="$(vtool -arch "$arch" -show-build "$STAGE/$bin" 2>/dev/null \
            | awk '/minos/ {print $2; exit}')"
        if [[ "$minos" != "$DEPLOYMENT_TARGET" ]]; then
            die "$bin ($arch) minos is $minos, expected $DEPLOYMENT_TARGET; refusing to ship a binary with the wrong macOS floor"
        fi
    done
done

# ---- Codesign -------------------------------------------------------------

for bin in uv uvx; do
    if [[ "$SIGN" -eq 1 ]]; then
        log "Codesigning $bin with Developer ID identity $IDENTITY"
        codesign --force --timestamp --options runtime \
            --sign "$IDENTITY" "$STAGE/$bin"
    else
        log "Ad-hoc signing $bin"
        codesign --force --sign - "$STAGE/$bin"
    fi
    codesign --verify --strict "$STAGE/$bin"
done

# ---- Package --------------------------------------------------------------

log "Creating $ARCHIVE_FILE"
# Build the archive from the staging parent so the tarball has a single
# top-level uv-<triple>/ directory, matching the official layout.
( cd "$WORK" && tar czf "$OUTPUT_DIR/$ARCHIVE_FILE" "$ARCHIVE_NAME" )
( cd "$OUTPUT_DIR" && shasum -a 256 "$ARCHIVE_FILE" > "$ARCHIVE_FILE.sha256" )

SHA256="$(awk '{print $1}' "$OUTPUT_DIR/$ARCHIVE_FILE.sha256")"
SIZE="$(stat -f %z "$OUTPUT_DIR/$ARCHIVE_FILE")"

# ---- Summary --------------------------------------------------------------

echo
log "Done."
echo "  Archive:  $OUTPUT_DIR/$ARCHIVE_FILE"
echo "  Size:     $SIZE bytes"
echo "  SHA-256:  $SHA256"
echo "  uv rev:   $REV ($RESOLVED_SHA)"
echo "  Floor:    macOS $DEPLOYMENT_TARGET"
echo "  Contents:"
tar tzf "$OUTPUT_DIR/$ARCHIVE_FILE" | sed 's/^/    /'
echo
echo "  The size value is the one the uv manifest records. The manifest"
echo "  signature is a separate RSA-SHA256 signature over these exact bytes,"
echo "  produced by sign_and_copy_uv.sh (verified against rsa_pub.pem); it is"
echo "  not the sha256 above."

# ---- RSA sign + stage in the website downloads dir (optional) -------------

if [[ -n "$RSA_KEY" ]]; then
    # The manifest records uv_version verbatim and it is compared as a dotted number,
    # so a bare commit SHA passed as --rev would parse as version 0 and quietly poison
    # the newest-version selection. Require X.Y[.Z] before signing/publishing.
    if [[ ! "$REV" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
        die "--rev '$REV' is not a dotted version (X.Y[.Z]); refusing to publish a manifest entry with a non-version uv_version"
    fi
    echo
    log "Running sign_and_copy_uv.sh"
    # sign_and_copy_uv.sh fetches from a URL; a file:// URL points it at the
    # archive we just built so it stages exactly these bytes and signs them.
    # It also needs the uv version and the minimum macOS floor for the manifest
    # entry: reuse the same $REV and $DEPLOYMENT_TARGET this build targeted. Pass the
    # sha256 we just computed so sign_and_copy's UV_EXPECTED_SHA256 cross-check
    # actually runs (otherwise it is inert in the automated path). Percent-encode
    # spaces in the file:// path so curl accepts it.
    UV_EXPECTED_SHA256="$SHA256" \
        "$SIGN_AND_COPY" "file://${OUTPUT_DIR// /%20}/$ARCHIVE_FILE" "$RSA_KEY" \
        "$REV" "$DEPLOYMENT_TARGET"
else
    echo "  To RSA-sign and stage in the website downloads dir, re-run with"
    echo "  --rsa-key PATH (invokes tools/sign_and_copy_uv.sh on success)."
fi
