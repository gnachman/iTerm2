#!/bin/bash
# Manual verification for issue 12864: the iterm2 Python library should
# look up disable-automation-auth in the suite-specific Application
# Support directory, not always under stock iTerm2's.
#
# Creates a fresh venv, installs the local module from
# api/library/python/iterm2 (editable), prints the state of the
# disable-automation-auth canary files for both stock and suite, then
# runs a script that connects and opens a window.
#
# Usage:
#   tests/test_iterm2_python_suite_auth.sh
#
# Env vars (defaults match the dev-build layout from the bug report):
#   IT2_SUITE=iterm2-dev                              # suite to talk to
#   IT2_APP_PATH=build/Development/iTerm2.app         # which build for
#                                                       AppleScript cookie
#   ITERM2_COOKIE / ITERM2_KEY                        # skip AppleScript
#
# Repro for the bug (before the fix):
#   1. In stock iTerm2, click "Always Allow All Apps" to create
#      ~/Library/Application Support/iTerm2/disable-automation-auth
#   2. make run  (launches dev build with -suite iterm2-dev)
#   3. Run this script with the defaults below.
#      Pre-fix: silent 401, no window created.
#      Post-fix: window created OK.

set -eu

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODULE_DIR="$REPO_ROOT/api/library/python/iterm2"
VENV_DIR="$REPO_ROOT/tmp/iterm2-py-suite-venv"

: "${IT2_SUITE:=iterm2-dev}"
: "${IT2_APP_PATH:=$REPO_ROOT/build/Development/iTerm2.app}"
export IT2_SUITE IT2_APP_PATH

STOCK_FILE="$HOME/Library/Application Support/iTerm2/disable-automation-auth"
SUITE_FILE="$HOME/Library/Application Support/$IT2_SUITE/disable-automation-auth"

echo "==> disable-automation-auth state"
for f in "$STOCK_FILE" "$SUITE_FILE"; do
    if [ -e "$f" ]; then
        owner=$(stat -f '%Su' "$f" 2>/dev/null || echo '?')
        size=$(stat -f '%z' "$f" 2>/dev/null || echo '?')
        echo "    present (uid=$owner size=$size): $f"
    else
        echo "    absent: $f"
    fi
done

echo "==> Creating venv at $VENV_DIR"
mkdir -p "$(dirname "$VENV_DIR")"
rm -rf "$VENV_DIR"
python3 -m venv "$VENV_DIR"

# shellcheck disable=SC1091
. "$VENV_DIR/bin/activate"

echo "==> Installing local iterm2 module (editable)"
pip install --quiet --upgrade pip
pip install --quiet -e "$MODULE_DIR"

echo "==> Running connection test"
echo "    IT2_SUITE=$IT2_SUITE"
echo "    IT2_APP_PATH=$IT2_APP_PATH"
echo "    ITERM2_COOKIE=${ITERM2_COOKIE:+<set>}"

python3 - <<'PY'
import os
import sys

import iterm2
from iterm2 import auth

suite = os.environ.get("IT2_SUITE", "iTerm2")
print(f"    Python sees IT2_SUITE={suite!r}")
print(f"    auth.applescript_auth_disabled() -> {auth.applescript_auth_disabled()}")

async def main(connection):
    await iterm2.async_get_app(connection)
    win = await iterm2.Window.async_create(connection)
    if win is None:
        print("ERROR: failed to create window", file=sys.stderr)
        sys.exit(1)
    print(f"OK: created window {win.window_id}")

iterm2.run_until_complete(main)
PY
