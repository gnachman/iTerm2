#!/bin/bash
#
# copy_models.sh - publish the AI model catalog to the iTerm2 website.
#
# The catalog (OtherResources/ai-models.json) is authored in this repo but must
# be SERVED from the website repo (iterm2.com), so running copies of iTerm2 can
# pick up new models without an app update. This script bridges the two repos.
#
# It:
#   1. Copies the catalog payload into the website repo as
#      downloads/ai/models.json (a stable URL the website and app both read).
#   2. Signs the exact bytes with the RSA private key at $RSA_PRIV and rewrites
#      downloads/ai/manifest.json - the signed manifest the app fetches - with an
#      entry {version, url, signature, minimum_ai_version} for this version.
#   3. scps both files live to the `bryan` host (see update-patrons.sh) and
#      offers to purge the Cloudflare cache.
#
# The app verifies the payload signature against the bundled rsa_pub.pem (the
# same key pair as the Python runtime), so $RSA_PRIV must be that private key.
# The self-check in step 2 refuses to publish anything rsa_pub.pem would reject.
#
# FULL RELEASE PROCESS (this script automates only steps 3-4):
#   1. Edit OtherResources/ai-models.json (add/adjust models). Capture any new
#      refusal fixtures the tests require (see AIMetadata.swift header).
#   2. Bump the top-level "version" in ai-models.json. The app only installs a
#      downloaded catalog whose version is greater than the bundled/cached one,
#      and it must match the manifest entry, so this bump is mandatory.
#   3. Build/ship the app so the bundled snapshot matches (an app upgrade always
#      wins over a stale cache of the same-or-lower version).
#   4. Run this script to sign and publish to iterm2.com.
#   5. Commit the website repo (models.json + manifest.json) so the deploy is
#      reproducible.
#
# Usage:
#   RSA_PRIV=/path/to/rsa_priv.pem tools/copy_models.sh
# Optional:
#   AI_MIN_VERSION=<int>   minimum app AI-compatibility version required to
#                          consume this catalog (default 1). Bump only when the
#                          catalog references a serializer/feature added in a
#                          newer app; see AIModelCatalog.appCatalogCompatibilityVersion.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO_DIR/OtherResources/ai-models.json"
PUBKEY="$REPO_DIR/OtherResources/rsa_pub.pem"

WEBSITE_DIR="$HOME/iterm2-website"
AI_DIR="$WEBSITE_DIR/downloads/ai"

PAYLOAD_NAME="models.json"
MANIFEST_NAME="manifest.json"
PAYLOAD_URL="https://iterm2.com/downloads/ai/$PAYLOAD_NAME"
MANIFEST_URL="https://iterm2.com/downloads/ai/$MANIFEST_NAME"

# Remote is the served docroot on the `bryan` host; mirrors update-patrons.sh's
# `scp source/patrons.txt bryan:iterm2.com/patrons.txt`.
REMOTE_HOST="bryan"
REMOTE_DIR="iterm2.com/downloads/ai"

MIN_AI_VERSION="${AI_MIN_VERSION:-1}"

die() { echo "error: $*" >&2; exit 1; }

[[ -n "${RSA_PRIV:-}" ]] || die "\$RSA_PRIV is not set (path to the RSA private key)"
[[ -f "$RSA_PRIV" ]] || die "\$RSA_PRIV ($RSA_PRIV) is not a file"
[[ -f "$SRC" ]] || die "catalog not found at $SRC"
[[ -f "$PUBKEY" ]] || die "public key not found at $PUBKEY"
[[ -d "$WEBSITE_DIR" ]] || die "website repo not found at $WEBSITE_DIR"

# The manifest entry's version must equal the catalog's own version; the app
# rejects a payload whose decoded version does not match the manifest.
VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$SRC")"
[[ -n "$VERSION" ]] || die "could not read \"version\" from $SRC"

mkdir -p "$AI_DIR"

# 1. Copy the payload verbatim. Sign the EXACT bytes we serve, so nothing may
#    reformat the file after this point.
cp "$SRC" "$AI_DIR/$PAYLOAD_NAME"

# 2. Sign, then self-verify against the shipped public key before touching the
#    manifest, so a wrong key or corrupt copy fails here instead of in the field.
SIGNATURE="$(openssl dgst -sha256 -sign "$RSA_PRIV" "$AI_DIR/$PAYLOAD_NAME" | openssl base64 -A)"

SIGBIN="$(mktemp)"
trap 'rm -f "$SIGBIN"' EXIT
printf '%s' "$SIGNATURE" | openssl base64 -d -A > "$SIGBIN"
openssl dgst -sha256 -verify "$PUBKEY" -signature "$SIGBIN" "$AI_DIR/$PAYLOAD_NAME" >/dev/null 2>&1 \
    || die "signature failed to verify against $PUBKEY; is \$RSA_PRIV the matching private key?"

# Merge into any existing manifest: replace this version's entry and keep the
# rest, so older app ranges can still be offered an older catalog.
MANIFEST_PATH="$AI_DIR/$MANIFEST_NAME"
python3 - "$MANIFEST_PATH" "$VERSION" "$PAYLOAD_URL" "$SIGNATURE" "$MIN_AI_VERSION" <<'PY'
import json, os, sys
path, version, url, sig, min_ai = sys.argv[1:6]
version, min_ai = int(version), int(min_ai)
entries = []
if os.path.exists(path):
    with open(path) as f:
        entries = json.load(f)
    entries = [e for e in entries if e.get("version") != version]
entries.append({
    "version": version,
    "url": url,
    "signature": sig,
    "minimum_ai_version": min_ai,
})
entries.sort(key=lambda e: e["version"])
with open(path, "w") as f:
    json.dump(entries, f, indent=2)
    f.write("\n")
PY

echo "Wrote $AI_DIR/$PAYLOAD_NAME (version $VERSION) and updated $MANIFEST_PATH"

# 3. Push live. Ensure the remote directory exists (scp will not create it).
ssh "$REMOTE_HOST" "mkdir -p $REMOTE_DIR"
scp "$AI_DIR/$PAYLOAD_NAME" "$REMOTE_HOST:$REMOTE_DIR/$PAYLOAD_NAME"
scp "$MANIFEST_PATH" "$REMOTE_HOST:$REMOTE_DIR/$MANIFEST_NAME"
echo "Pushed to $REMOTE_HOST:$REMOTE_DIR"

# Both files sit at stable URLs, so a CDN can serve stale copies. Purge them.
echo "Purge the Cloudflare cache for:"
echo "  $PAYLOAD_URL"
echo "  $MANIFEST_URL"
if command -v open >/dev/null 2>&1; then
    open 'https://dash.cloudflare.com/fd2981af5d94d04f7535c150ada305bc/iterm2.com/caching/configuration'
fi
