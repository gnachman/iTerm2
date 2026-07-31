#!/bin/bash
#
# Download a uv binary archive from a source URL, place it in the iTerm2 website's
# uv downloads directory, sign it with RSA-SHA256 (the format iTermSignatureVerifier
# validates against rsa_pub.pem: openssl dgst -sha256 -sign KEY FILE | base64 -A),
# and add/replace this build's entry in the uv manifest via update_uv_manifest.sh.
#
# Usage:
#   tools/sign_and_copy_uv.sh <source-url> <rsa-private-key.pem> <uv-version> <min-macos> [max-macos]
#
# The public URL recorded in the manifest is <base>/<filename>, where <base> defaults
# to https://iterm2.com/downloads/uv (override with UV_PUBLIC_BASE_URL).
#
# To only update the manifest (without re-downloading/signing), run update_uv_manifest.sh.

set -euo pipefail

if [[ $# -lt 4 || $# -gt 5 ]]; then
    echo "Usage: $0 <source-url> <rsa-private-key.pem> <uv-version> <min-macos> [max-macos]" >&2
    exit 1
fi

source_url="$1"
private_key="$2"
uv_version="$3"
min_macos="$4"
max_macos="${5:-}"

public_base_url="${UV_PUBLIC_BASE_URL:-https://iterm2.com/downloads/uv}"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "$private_key" ]]; then
    echo "Error: private key not found: $private_key" >&2
    exit 1
fi

dest_dir="$HOME/iterm2-website/downloads/uv"
mkdir -p "$dest_dir"

# Derive the filename from the source URL, stripping any query string or fragment.
filename="$(basename "${source_url%%[?#]*}")"
if [[ -z "$filename" || "$filename" == "/" ]]; then
    echo "Error: could not determine a filename from the URL: $source_url" >&2
    exit 1
fi
dest_file="$dest_dir/$filename"

# Download to a temp file first so a failed download never leaves a partial or
# stale file in the served directory.
tmp_file="$(mktemp)"
trap 'rm -f "$tmp_file"' EXIT
echo "Downloading $source_url ..."
curl -fSL "$source_url" -o "$tmp_file"
mv -f "$tmp_file" "$dest_file"
# mktemp creates the temp file mode 600, and mv preserves it; the web server runs as
# a different user, so without this the hosted tarball would 403. Match the 644 that
# the sig/manifest get from the default umask.
chmod 644 "$dest_file"
echo "Placed:    $dest_file"

# Optional integrity cross-check: if the caller pins the expected sha256 of the
# tarball (e.g. the value build_uv.sh printed), verify the downloaded bytes match
# before signing so we never RSA-sign an unexpected/corrupted archive.
if [[ -n "${UV_EXPECTED_SHA256:-}" ]]; then
    actual_sha256="$(shasum -a 256 "$dest_file" | awk '{print $1}')"
    if [[ "$actual_sha256" != "$UV_EXPECTED_SHA256" ]]; then
        echo "Error: sha256 mismatch for $dest_file" >&2
        echo "  expected: $UV_EXPECTED_SHA256" >&2
        echo "  actual:   $actual_sha256" >&2
        exit 1
    fi
    echo "Verified sha256 matches UV_EXPECTED_SHA256."
fi

# RSA-SHA256 signature, base64-encoded on a single line, of the exact hosted bytes.
signature="$(openssl dgst -sha256 -sign "$private_key" "$dest_file" | openssl enc -base64 -A)"
sig_file="$dest_file.sig"
printf '%s\n' "$signature" > "$sig_file"
echo "Signature: $sig_file"

size="$(stat -f %z "$dest_file")"
sha256="$(shasum -a 256 "$dest_file" | awk '{print $1}')"
public_url="$public_base_url/$filename"

echo
echo "Manifest fields:"
echo "  url:       $public_url"
echo "  size:      $size"
echo "  sha256:    $sha256"
echo "  signature: $signature"
echo

# Update the manifest with this build's entry.
manifest_args=(--uv-version "$uv_version"
               --url "$public_url"
               --signature "$signature"
               --size "$size"
               --min-macos "$min_macos")
if [[ -n "$max_macos" ]]; then
    manifest_args+=(--max-macos "$max_macos")
fi
"$script_dir/update_uv_manifest.sh" "${manifest_args[@]}"
