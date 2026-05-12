#!/bin/bash
# Build Sparkle CLI helpers (sign_update, generate_keys, generate_appcast) from
# the bundled submodule once. They are NOT shipped inside Sparkle.framework so
# the Sparkle Xcode project has to compile them on demand.
#
# Output:
#   build/sparkle-tools/sign_update
#   build/sparkle-tools/generate_keys
#   build/sparkle-tools/generate_appcast
#
# Usage:
#   tools/sparkle_tools.sh             # build the three tools
#   eval "$(tools/sparkle_tools.sh env)" # export SPARKLE_BIN to your shell

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPARKLE_DIR="$REPO_ROOT/submodules/Sparkle"
OUT_DIR="$REPO_ROOT/build/sparkle-tools"
DERIVED="$REPO_ROOT/build/sparkle-derived"

if [ "${1:-}" = "env" ]; then
  echo "export SPARKLE_BIN=\"$OUT_DIR\""
  echo "export PATH=\"$OUT_DIR:\$PATH\""
  exit 0
fi

mkdir -p "$OUT_DIR" "$DERIVED"

for tool in sign_update generate_keys generate_appcast; do
  if [ -x "$OUT_DIR/$tool" ]; then
    echo "[sparkle_tools] $tool already built — skip"
    continue
  fi
  echo "[sparkle_tools] building $tool..."
  xcodebuild -project "$SPARKLE_DIR/Sparkle.xcodeproj" \
             -scheme "$tool" \
             -configuration Release \
             -derivedDataPath "$DERIVED" \
             -quiet \
             SYMROOT="$DERIVED/sym" \
             OBJROOT="$DERIVED/obj" \
             build
  cp "$DERIVED/sym/Release/$tool" "$OUT_DIR/$tool"
  chmod +x "$OUT_DIR/$tool"
  echo "[sparkle_tools] wrote $OUT_DIR/$tool"
done

echo
echo "Sparkle CLI tools ready at $OUT_DIR"
echo "Run \`eval \"\$(tools/sparkle_tools.sh env)\"\` to put them on PATH."
