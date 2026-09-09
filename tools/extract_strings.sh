#!/bin/bash
#
# Extract localizable strings from all first-party source code into
# sources/Localizable.xcstrings.
#
# Two languages, two mechanisms:
#
#   Swift  - swiftc emits a .stringsdata file per source file during the build
#            when SWIFT_EMIT_LOC_STRINGS=YES (set at the project level). It
#            understands String(localized:) and the LocalizedStringResource
#            family. We just collect what the build already produced.
#
#   ObjC   - clang does NOT emit stringsdata, and the build never runs a
#            genstrings-style pass over the static-library targets. So we run
#            extractLocStrings ourselves over every .m/.mm in sources/. It
#            understands the NSLocalizedString family, including
#            NSLocalizedStringWithDefaultValue (symbolic key + English default).
#
# Both sets of .stringsdata are then merged into the catalog with
# `xcstringstool sync`, which adds new keys, updates values, and marks removed
# keys stale. Because we feed it the complete first-party set, that pruning is
# correct.
#
# This must run AFTER a build of <config> so the Swift stringsdata exists. The
# Beta and Deployment Makefile targets build first and then call this; the
# standalone `make extract-strings` target depends on Development.
#
# Usage: tools/extract_strings.sh [config] [build_dir]
#   config     defaults to Development
#   build_dir  defaults to the scheme's SYMROOT (…/Build)

set -euo pipefail

CONFIG="${1:-Development}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUILD_DIR="${2:-}"
if [[ -z "$BUILD_DIR" ]]; then
    BUILD_DIR="$(xcodebuild -scheme iTerm2 -showBuildSettings 2>/dev/null \
        | sed -n 's/^ *SYMROOT = //p' | head -1)"
fi
if [[ -z "$BUILD_DIR" || ! -d "$BUILD_DIR" ]]; then
    echo "extract_strings: could not determine BUILD_DIR (got '$BUILD_DIR')" >&2
    exit 1
fi

EXTRACT="$(xcrun --find extractLocStrings)"
XCS="$(xcrun --find xcstringstool)"
CATALOG="sources/Localizable.xcstrings"

if [[ ! -f "$CATALOG" ]]; then
    echo "extract_strings: catalog not found at $CATALOG" >&2
    exit 1
fi

# Objective-C output goes to a scratch dir under the build tree.
OBJC_SD="$BUILD_DIR/loc-stringsdata-objc-$CONFIG"
rm -rf "$OBJC_SD"
mkdir -p "$OBJC_SD"

echo "extract_strings: scanning Objective-C sources with extractLocStrings…"
# ThirdParty/UKCrashReporter is a fork we own, so its user-visible strings are
# localized into our catalog like first-party code. Other ThirdParty modules keep
# their own catalogs and are intentionally excluded.
find sources ThirdParty/UKCrashReporter -type f \( -name '*.m' -o -name '*.mm' \) -print0 \
    | xargs -0 "$EXTRACT" -stringsdata -o "$OBJC_SD"

# Swift: the build already emitted a .stringsdata per file for the first-party
# ARC library. Third-party SPM packages and separate frameworks have their own
# catalogs and are intentionally excluded.
SWIFT_ROOT="$BUILD_DIR/Intermediates.noindex/iTerm2.build/$CONFIG/iTerm2SharedARC.build"
if [[ ! -d "$SWIFT_ROOT" ]]; then
    echo "extract_strings: no Swift build products at $SWIFT_ROOT" >&2
    echo "extract_strings: build $CONFIG first (SWIFT_EMIT_LOC_STRINGS must be YES)" >&2
    exit 1
fi

# Collect every stringsdata path (ObjC scratch + Swift build products) into an
# array so xcstringstool receives them as an explicit file list. A directory
# argument is silently ignored, so we must enumerate files.
STRINGSDATA=()
while IFS= read -r -d '' f; do STRINGSDATA+=("$f"); done \
    < <(find "$OBJC_SD" -name '*.stringsdata' -print0)
while IFS= read -r -d '' f; do STRINGSDATA+=("$f"); done \
    < <(find "$SWIFT_ROOT" -path '*/Objects-normal/*' -name '*.stringsdata' -print0)

if [[ ${#STRINGSDATA[@]} -eq 0 ]]; then
    echo "extract_strings: found no stringsdata to sync" >&2
    exit 1
fi

echo "extract_strings: syncing ${#STRINGSDATA[@]} stringsdata files into ${CATALOG}…"
"$XCS" sync "$CATALOG" --stringsdata "${STRINGSDATA[@]}"

# Guard: a positional specifier (%N$…) whose conversion character is invalid means a literal
# "%word" was misread as a format specifier (e.g. tmux's "%begin"/"%end" becoming "%1$begin").
# extractLocStrings itself does this, so the offending source string must move the literal '%'
# out of the localized literal (pass it as an argument). Fail loudly rather than ship garbled text.
python3 - "$CATALOG" <<'PYCHECK'
import json, re, sys
d = json.load(open(sys.argv[1]))["strings"]
valid = re.compile(r'%[0-9]+\$[-+ 0#]*[0-9]*(?:\.[0-9]+)?(?:ll|l|z|h|hh)?[@dDiuUxXoeEfFgGcsp]')
anypos = re.compile(r'%[0-9]+\$')
bad = []
for k, v in d.items():
    for loc in v.get("localizations", {}).values():
        s = loc.get("stringUnit", {}).get("value", "")
        if isinstance(s, str) and any(not valid.match(s, m.start()) for m in anypos.finditer(s)):
            bad.append((k, s))
if bad:
    print("extract_strings: ERROR: malformed positional specifier (a literal %%word misread as a format specifier):", file=sys.stderr)
    for k, s in bad:
        print(f"  {k}: {s!r}", file=sys.stderr)
    sys.exit(1)
PYCHECK

echo "extract_strings: done."
