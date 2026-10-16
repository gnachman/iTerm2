#!/bin/bash
#
# Build, notarize, sign, and publish an iTerm2 stable release without prompting.
#
# This is the unattended counterpart of release_stable.sh. Instead of reading
# secrets from the terminal and opening files in vi, it:
#   * reads the Sparkle EdDSA private key from the login keychain
#     (generic password, service "iterm2-sparkle-ed25519"),
#   * notarizes with the notarytool keychain profile "iterm2-notary"
#     (created once with `xcrun notarytool store-credentials iterm2-notary`),
#   * relies on gpg-agent + pinentry-mac having the gpg passphrase saved in
#     the keychain,
#   * takes the release notes from docs/notes-<version>.txt (or the file given
#     as the second argument), which must already be committed. They become
#     both full_changes.txt (what Sparkle shows) and the download's changelog.
#
# It also points the website's iTerm2-shell-integration submodule at the
# commit this release ships and republishes the scripts it serves, so the
# website doesn't drift behind the app.
#
# Usage: tools/release_stable_noninteractive.sh [--no-publish] <version> [notes-file]
#   e.g. tools/release_stable_noninteractive.sh 3.7.7
#
# --no-publish builds, notarizes, signs, and writes the website files, but does
# not tag, commit, or push anything. Use it to rehearse a release.
#
# Run it from a checkout of the branch being released (master or a release
# branch) that matches its counterpart on origin. All checks that can fail
# cheaply (secrets, branch, tag, notes, website repo) run before the build so a
# problem doesn't surface twenty minutes in.
#
# Never add `set -x` here: it would print the EdDSA private key.

set -euo pipefail

TEAM_ID=H7V7XYVQ7D
SIGNING_AUTHORITY="Developer ID Application: GEORGE NACHMAN ($TEAM_ID)"
NOTARY_PROFILE=iterm2-notary
EDDSA_KEYCHAIN_SERVICE=iterm2-sparkle-ed25519
WEBSITE_DIR=~/iterm2-website
BUILDTYPE=Deployment
SUMMARY_SUFFIX="macOS 13+"
DESCRIPTION="This is the recommended build for most users."
SHELL_INTEGRATION_SUBMODULE=submodules/iTerm2-shell-integration

function die {
    echo "ERROR: $*" >&2
    exit 1
}

function step {
    echo ""
    echo "==> $*"
}

PUBLISH=1
if [ "${1:-}" = "--no-publish" ]; then
    PUBLISH=0
    shift
fi

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo "Usage: $0 [--no-publish] <version> [notes-file]" >&2
    exit 1
fi

VERSION="$1"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Version '$VERSION' does not look like 3.7.7"

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_DIR"

NOTES_FILE="${2:-docs/notes-${VERSION}.txt}"
NAME=$(echo "$VERSION" | sed -e "s/\\./_/g")
TAG="v${VERSION}"
BUILD_DIR="$REPO_DIR/build"
APP_DIR="$BUILD_DIR/$BUILDTYPE"
WORK_DIR=$(mktemp -d -t iterm2-release)
trap 'rm -rf "$WORK_DIR"' EXIT

# ---------------------------------------------------------------------------
step "Preflight: iTerm2 repo"

BRANCH=$(git rev-parse --abbrev-ref HEAD)
[ "$BRANCH" != "HEAD" ] || die "HEAD is detached; check out the branch being released"
echo "Releasing from branch $BRANCH"
[ -z "$(git status --porcelain --untracked-files=no)" ] || die "Tracked files have uncommitted changes"
git fetch --tags origin
git rev-parse -q --verify "refs/remotes/origin/$BRANCH" >/dev/null || die "origin/$BRANCH does not exist; push the branch first"
[ "$(git rev-parse HEAD)" = "$(git rev-parse "origin/$BRANCH")" ] || die "HEAD is not origin/$BRANCH; pull or push first"
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || [ -n "$(git ls-remote --tags origin "refs/tags/$TAG")" ]; then
    echo "Tag $TAG already exists; it will be moved to HEAD after the website is published."
fi

[ -f "$NOTES_FILE" ] || die "Release notes $NOTES_FILE not found"
git ls-files --error-unmatch "$NOTES_FILE" >/dev/null 2>&1 || die "$NOTES_FILE is not committed"
grep -q "^Version $VERSION " <<< "$(head -1 "$NOTES_FILE")" || die "$NOTES_FILE does not start with “Version $VERSION”"

# The website must serve the shell integration this release ships, so the
# checked-out submodule must be exactly what HEAD records, and pushed.
SHELL_INTEGRATION_SHA=$(git rev-parse "HEAD:$SHELL_INTEGRATION_SUBMODULE") || die "Could not read the commit recorded for $SHELL_INTEGRATION_SUBMODULE"
[ -z "$(git -C "$SHELL_INTEGRATION_SUBMODULE" status --porcelain)" ] || die "$SHELL_INTEGRATION_SUBMODULE has uncommitted changes"
CHECKED_OUT_SHA=$(git -C "$SHELL_INTEGRATION_SUBMODULE" rev-parse HEAD)
[ "$CHECKED_OUT_SHA" = "$SHELL_INTEGRATION_SHA" ] || die "$SHELL_INTEGRATION_SUBMODULE is at $CHECKED_OUT_SHA but HEAD records $SHELL_INTEGRATION_SHA. Run git submodule update or commit the new pointer."

# ---------------------------------------------------------------------------
step "Preflight: website repo"

[ -d "$WEBSITE_DIR/.git" ] || die "$WEBSITE_DIR is not a git repo"
[ "$(git -C "$WEBSITE_DIR" rev-parse --abbrev-ref HEAD)" = "master" ] || die "$WEBSITE_DIR is not on master"
git -C "$WEBSITE_DIR" fetch origin
[ -z "$(git -C "$WEBSITE_DIR" rev-list HEAD..origin/master)" ] || die "$WEBSITE_DIR is behind origin/master; pull first"
if [ -e "$WEBSITE_DIR/downloads/stable/iTerm2-${NAME}.zip" ]; then
    echo "$WEBSITE_DIR/downloads/stable/iTerm2-${NAME}.zip already exists; it will be replaced by this build."
fi

WEB_SHELL_INTEGRATION="$WEBSITE_DIR/$SHELL_INTEGRATION_SUBMODULE"
git -C "$WEB_SHELL_INTEGRATION" fetch origin
[ -n "$(git -C "$WEB_SHELL_INTEGRATION" branch -r --contains "$SHELL_INTEGRATION_SHA" 2>/dev/null)" ] || die "Shell integration commit $SHELL_INTEGRATION_SHA is not pushed to origin"

APPCAST_FILES=(
    "source/appcasts/full_changes.txt"
    "source/appcasts/final_new.xml"
    "source/appcasts/final_modern.xml"
    "downloads/stable/.htaccess"
)
SHELL_INTEGRATION_PATHS=(
    "$SHELL_INTEGRATION_SUBMODULE"
    "source/shell_integration"
    "source/utilities"
)
WEBSITE_FILES=(
    "downloads/stable/iTerm2-${NAME}.summary"
    "downloads/stable/iTerm2-${NAME}.description"
    "downloads/stable/iTerm2-${NAME}.changelog"
    "downloads/stable/iTerm2-${NAME}.zip"
    "${APPCAST_FILES[@]}"
    "${SHELL_INTEGRATION_PATHS[@]}"
)
for f in "${APPCAST_FILES[@]}" "${SHELL_INTEGRATION_PATHS[@]}"; do
    [ -z "$(git -C "$WEBSITE_DIR" status --porcelain -- "$f")" ] || die "$WEBSITE_DIR/$f has uncommitted changes"
done

# ---------------------------------------------------------------------------
step "Preflight: secrets"

grep -qF "$SIGNING_AUTHORITY" <<< "$(security find-identity -v -p codesigning)" || die "Signing identity “$SIGNING_AUTHORITY” not found"

EDPRIVKEY=$(security find-generic-password -s "$EDDSA_KEYCHAIN_SERVICE" -w 2>/dev/null) || die "Could not read the EdDSA key from the keychain (service $EDDSA_KEYCHAIN_SERVICE)"
[ -n "$EDPRIVKEY" ] || die "The EdDSA key in the keychain is empty"

xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 || die "notarytool keychain profile “$NOTARY_PROFILE” does not work"

echo preflight | gpg --batch --clearsign >/dev/null 2>&1 || die "gpg could not sign; is the passphrase saved in the keychain via pinentry-mac?"

echo "All preflight checks passed."

# ---------------------------------------------------------------------------
step "Build $VERSION"

echo "$VERSION" > version.txt
trap 'git -C "$REPO_DIR" checkout -- version.txt; rm -rf "$WORK_DIR"' EXIT

make clean BUILD_DIR="$BUILD_DIR"
make -j8 SIGNED=1 UNIVERSAL=1 BUILD_DIR="$BUILD_DIR" release

# The build runs extract_strings.sh, which rewrites the string catalog. If that
# changed anything, the committed catalog (and so the translations) is out of
# date with the source.
CHANGED_BY_BUILD=$(git status --porcelain --untracked-files=no -- . ':!version.txt')
[ -z "$CHANGED_BY_BUILD" ] || die "The build modified tracked files, so translations are out of date. Commit an updated catalog and translations, then rerun:
$CHANGED_BY_BUILD"

codesign --verify --verbose "$APP_DIR/iTerm2.app" || die "Signature not verified"
# Capture first: with pipefail, grep -q exiting early would SIGPIPE codesign
# and fail the pipeline even on a match.
SIGNATURE_INFO=$(codesign -dv --verbose=4 "$APP_DIR/iTerm2.app" 2>&1)
grep -qF "Authority=$SIGNING_AUTHORITY" <<< "$SIGNATURE_INFO" || die "Not signed with the right certificate"

# ---------------------------------------------------------------------------
step "Notarize"

cd "$APP_DIR"
# Sparkle won't accept a change to the app's folder name, so it must stay iTerm.app.
rm -rf iTerm.app
mv iTerm2.app iTerm.app

PRENOTARIZED_ZIP=iTerm2-${NAME}-prenotarized.zip
ZIP=iTerm2-${NAME}.zip
rm -f "$PRENOTARIZED_ZIP" "$ZIP"
zip -qry "$PRENOTARIZED_ZIP" iTerm.app

# --wait can exit 0 with status Invalid, so require "status: Accepted".
# Transient upload failures are retried; real rejections are not.
function notarize_with_retry {
    local zip="$1"
    local max_attempts=6
    local attempt=1
    local out="$WORK_DIR/upload.out"
    while [ $attempt -le $max_attempts ]; do
        echo "Notarization attempt $attempt of $max_attempts..."
        local rc=0
        xcrun notarytool submit --keychain-profile "$NOTARY_PROFILE" --wait "$zip" > "$out" 2>&1 || rc=$?
        cat "$out"
        if [ $rc -eq 0 ] && grep -q "status: Accepted" "$out"; then
            return 0
        fi
        if grep -qE "abortedUpload|deadlineExceeded|connection reset|connectionReset|timed out|Connection refused|networkConnectionLost" "$out"; then
            local backoff=$((attempt * 10))
            echo "Transient upload failure (attempt $attempt). Retrying in ${backoff}s..."
            sleep $backoff
            attempt=$((attempt + 1))
            continue
        fi
        local uuid
        uuid=$(grep -i "id:" "$out" | head -1 | sed -e 's/.*id: //')
        if [ -n "$uuid" ]; then
            echo "Notarization was not Accepted. Log for $uuid follows:"
            xcrun notarytool log "$uuid" --keychain-profile "$NOTARY_PROFILE" 2>&1 | head -80 || true
        fi
        return 1
    done
    echo "Notarization failed after $max_attempts attempts."
    return 1
}

notarize_with_retry "$PRENOTARIZED_ZIP" || die "Notarization failed"
xcrun stapler staple iTerm.app || die "Stapling failed (notarization ticket unavailable?)"
xcrun stapler validate iTerm.app || die "Staple validation failed"
zip -qry "$ZIP" iTerm.app

# ---------------------------------------------------------------------------
step "Write website files"

cp "$REPO_DIR/$NOTES_FILE" "$WEBSITE_DIR/source/appcasts/full_changes.txt"
rm -f "$WEBSITE_DIR/downloads/stable/$ZIP"
cp "$ZIP" "$WEBSITE_DIR/downloads/stable/"
echo "iTerm2 $VERSION ($SUMMARY_SUFFIX)" > "$WEBSITE_DIR/downloads/stable/iTerm2-${NAME}.summary"
echo "$DESCRIPTION" > "$WEBSITE_DIR/downloads/stable/iTerm2-${NAME}.description"

shasum -a256 "$ZIP" | awk '{print $1}' > "$WORK_DIR/sum"
gpg --batch --yes --clearsign --output "$WORK_DIR/sum.asc" "$WORK_DIR/sum" || die "gpg signing failed"
{
    cat "$REPO_DIR/$NOTES_FILE"
    echo ""
    echo "You can use the following to verify the zip file on https://keybase.io/verify:"
    echo ""
    cat "$WORK_DIR/sum.asc"
} > "$WEBSITE_DIR/downloads/stable/iTerm2-${NAME}.changelog"

cat > "$WEBSITE_DIR/downloads/stable/.htaccess" <<EOF
Options +FollowSymlinks
Redirect 302 /downloads/stable/latest https://iterm2.com/downloads/stable/iTerm2-${NAME}.zip
<FilesMatch "\.changelog$">
    AddCharset UTF-8 .changelog
</FilesMatch>
EOF

# ---------------------------------------------------------------------------
step "Publish shell integration $SHELL_INTEGRATION_SHA to website"

git -C "$WEB_SHELL_INTEGRATION" checkout -q --detach "$SHELL_INTEGRATION_SHA"
(cd "$WEBSITE_DIR" && ./copy-shell-integration.sh) || die "copy-shell-integration.sh failed"

# ---------------------------------------------------------------------------
step "Sparkle-sign appcasts"

LENGTH=$(stat -f %z "$ZIP")
NEWSIG=$("$REPO_DIR/tools/sign_update" "$ZIP" "$EDPRIVKEY") || die "sign_update failed"
unset EDPRIVKEY
[ -n "$NEWSIG" ] || die "sign_update produced no signature"
DATE=$(date +"%a, %d %b %Y %H:%M:%S %z")

# Usage: write_appcast <output xml> <template xml>
function write_appcast {
    local xml="$1"
    local template="$2"
    sed -e "s/%XML%/${xml}/" \
        -e "s/%VER%/${VERSION}/" \
        -e "s/%DATE%/${DATE}/" \
        -e "s/%NAME%/${NAME}/" \
        -e "s/%LENGTH%/${LENGTH}/" \
        -e "s,%NEWSIG%,${NEWSIG}," \
        "$WEBSITE_DIR/source/appcasts/$template" > "$WEBSITE_DIR/source/appcasts/$xml"
    if grep -q '%[A-Z]*%' "$WEBSITE_DIR/source/appcasts/$xml"; then
        die "Unreplaced placeholder in $xml"
    fi
    echo "Wrote $WEBSITE_DIR/source/appcasts/$xml"
}

write_appcast final_new.xml final_template_new.xml
write_appcast final_modern.xml final_template_modern.xml

cd "$REPO_DIR"

if [ $PUBLISH -eq 0 ]; then
    step "--no-publish: stopping before tagging, committing, and pushing"
    echo "Zip: $APP_DIR/$ZIP"
    echo "Website files written but not committed:"
    printf '  %s\n' "${WEBSITE_FILES[@]}"
    echo "To discard them:"
    echo "  git -C $WEBSITE_DIR checkout -- ${APPCAST_FILES[*]} source/shell_integration source/utilities"
    echo "  git -C $WEBSITE_DIR clean -fdq -- source/shell_integration source/utilities"
    echo "  git -C $WEBSITE_DIR submodule update -- $SHELL_INTEGRATION_SUBMODULE"
    echo "  rm -f $WEBSITE_DIR/downloads/stable/iTerm2-${NAME}.*"
    exit 0
fi

# ---------------------------------------------------------------------------
step "Publish website"

# Publish the website before tagging: a missing tag is easy to add by hand,
# but a tag on origin with no appcast or zip behind it is a stranded release.
git -C "$WEBSITE_DIR" fetch origin
if [ -n "$(git -C "$WEBSITE_DIR" rev-list HEAD..origin/master)" ]; then
    die "origin/master of $WEBSITE_DIR moved during the build. The release files are written but not committed. Pull, then commit and push them, then run: git tag -f $TAG && git push -f origin refs/tags/$TAG"
fi

# Commit only this release's files. The website checkout routinely has
# unrelated local changes that must not be swept into the release commit.
# -A picks up shell integration files that were removed upstream.
git -C "$WEBSITE_DIR" add -A -- "${WEBSITE_FILES[@]}"
git -C "$WEBSITE_DIR" commit -m "$TAG" -- "${WEBSITE_FILES[@]}"
git -C "$WEBSITE_DIR" push origin master

# ---------------------------------------------------------------------------
step "Tag"

# -f moves the tag if this is a rebuild of a version that was already tagged.
git tag -f "$TAG"
git push -f origin "refs/tags/$TAG"

step "Released $VERSION"
