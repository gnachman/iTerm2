#!/bin/bash
# Test the modified iterm2 Python module's IT2_APP_PATH support.
#
# Creates a fresh venv, installs the local module from
# api/library/python/iterm2 (editable), and runs a script that connects
# and opens a new window.
#
# Usage:
#   tests/test_iterm2_python_auth.sh
#
# Optional env vars to exercise the fix:
#   IT2_APP_PATH=/path/to/iTerm2-dev.app    # target a specific build
#   IT2_SUITE=iterm2-dev                    # talk to its socket
#   ITERM2_COOKIE / ITERM2_KEY              # skip AppleScript entirely

set -eu

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODULE_DIR="$REPO_ROOT/api/library/python/iterm2"
VENV_DIR="$REPO_ROOT/tmp/iterm2-py-venv"

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
echo "    IT2_SUITE=${IT2_SUITE:-<unset>}"
echo "    IT2_APP_PATH=${IT2_APP_PATH:-<unset>}"
echo "    ITERM2_COOKIE=${ITERM2_COOKIE:+<set>}"

python3 - <<'PY'
import iterm2
import sys

async def main(connection):
    app = await iterm2.async_get_app(connection)
    win = await iterm2.Window.async_create(connection)
    if win is None:
        print("ERROR: failed to create window", file=sys.stderr)
        sys.exit(1)
    print(f"OK: created window {win.window_id}")

iterm2.run_until_complete(main)
PY
