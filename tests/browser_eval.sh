#!/bin/bash
# Runs tests/browser_eval.py against a dev build of iTerm2, using the Python
# module from this checkout (PyPI's doesn't have async_eval_javascript yet).
#
#   tests/browser_eval.sh [--url URL] [JS]     run JavaScript; see browser_eval.py
#   tests/browser_eval.sh smoke                run tests/browser_eval_smoke.py
#
# Start the dev build first with `make run`, and enable the Python API in its
# settings. The venv is created in tmp/browser-eval-venv on first use.
#
# IT2_SUITE picks which running iTerm2 to connect to. It defaults to the suite
# `make run` uses (this checkout's directory name). IT2_APP_PATH picks the app
# that hands out the auth cookie and defaults to the dev build.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
venv="$repo/tmp/browser-eval-venv"

export IT2_SUITE="${IT2_SUITE:-$(basename "$repo")}"
export IT2_APP_PATH="${IT2_APP_PATH:-$repo/Build/Development/iTerm2.app}"

socket="$HOME/Library/Application Support/$IT2_SUITE/private/socket"
if [[ ! -S "$socket" ]]; then
    echo "No iTerm2 API socket at $socket." >&2
    echo "Run \`make run\` and enable the Python API, or set IT2_SUITE." >&2
    exit 1
fi

if [[ ! -x "$venv/bin/python" ]]; then
    python3 -m venv "$venv"
    "$venv/bin/pip" install --quiet --upgrade pip
fi
# Reinstalls on every run so edits to the module in this checkout are picked up.
"$venv/bin/pip" install --quiet "$repo/api/library/python/iterm2"

if [[ "${1:-}" == "smoke" ]]; then
    shift
    exec "$venv/bin/python" "$repo/tests/browser_eval_smoke.py" "$@"
fi
exec "$venv/bin/python" "$repo/tests/browser_eval.py" "$@"
