#!/bin/bash
#
# Add or replace an entry in the uv download manifest that the app fetches from
# iterm2.com. Each entry matches iTermUvManifestEntry (sources/API/iTermUvManifest.swift):
#   { uv_version, url, signature, size, minimum_macos_version, maximum_macos_version }
# The app downloads only an entry whose [minimum_macos_version, maximum_macos_version]
# bracket includes the running macOS, and picks the newest compatible uv_version.
#
# Runnable on its own (e.g. with the size/signature that sign_and_copy_uv.sh printed),
# and also called by sign_and_copy_uv.sh.
#
# Usage:
#   tools/update_uv_manifest.sh --uv-version V --url URL --signature SIG --size BYTES \
#                               --min-macos X.Y [--max-macos X.Y] [--manifest PATH]
#
# An entry with the same --uv-version is replaced.

set -euo pipefail

manifest="$HOME/iterm2-website/downloads/uv/manifest.json"
uv_version=""
url=""
signature=""
size=""
min_macos=""
max_macos=""

usage() {
    echo "Usage: $0 --uv-version V --url URL --signature SIG --size BYTES --min-macos X.Y [--max-macos X.Y] [--manifest PATH]" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --uv-version) uv_version="${2:-}"; shift 2;;
        --url)        url="${2:-}"; shift 2;;
        --signature)  signature="${2:-}"; shift 2;;
        --size)       size="${2:-}"; shift 2;;
        --min-macos)  min_macos="${2:-}"; shift 2;;
        --max-macos)  max_macos="${2:-}"; shift 2;;
        --manifest)   manifest="${2:-}"; shift 2;;
        -h|--help)    usage;;
        *) echo "Unknown argument: $1" >&2; usage;;
    esac
done

for name in uv_version url signature size min_macos; do
    if [[ -z "${!name}" ]]; then
        echo "Error: missing required --${name//_/-}" >&2
        usage
    fi
done

if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: python3 is required to edit the manifest JSON." >&2
    exit 1
fi

mkdir -p "$(dirname "$manifest")"

UV_VERSION="$uv_version" URL="$url" SIGNATURE="$signature" SIZE="$size" \
MIN_MACOS="$min_macos" MAX_MACOS="$max_macos" MANIFEST="$manifest" \
python3 - <<'PY'
import json, os, sys

path = os.environ["MANIFEST"]
try:
    with open(path) as f:
        entries = json.load(f)
    if not isinstance(entries, list):
        sys.exit("Error: %s is not a JSON array" % path)
except FileNotFoundError:
    entries = []

try:
    size = int(os.environ["SIZE"])
except ValueError:
    sys.exit("Error: --size must be an integer number of bytes")

version = os.environ["UV_VERSION"]
entry = {
    "uv_version": version,
    "url": os.environ["URL"],
    "signature": os.environ["SIGNATURE"],
    "size": size,
    "minimum_macos_version": os.environ["MIN_MACOS"],
    "maximum_macos_version": os.environ["MAX_MACOS"] or None,
}

replaced = any(e.get("uv_version") == version for e in entries)
entries = [e for e in entries if e.get("uv_version") != version]
entries.append(entry)

with open(path, "w") as f:
    json.dump(entries, f, indent=2)
    f.write("\n")

print("%s %s in %s (%d total)" % ("Replaced" if replaced else "Added", version, path, len(entries)))
PY
