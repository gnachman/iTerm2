#!/bin/bash
# Sets up a throwaway virtualenv with the one dependency the ping-flood DoS test
# uses (psutil, for sampling iTerm2's memory) and runs the test. Any extra
# arguments are passed through to ping_flood_dos_test.py, e.g.:
#
#   tests/run_ping_flood_dos_test.sh --pid 12345
#   tests/run_ping_flood_dos_test.sh --socket /path/to/socket --no-monitor
#
# The Python API must be enabled in the iTerm2 you are testing.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="$HERE/.venv-ping-flood"
PY="$VENV/bin/python"

if [ ! -x "$PY" ]; then
    echo "Creating virtualenv at $VENV..."
    python3 -m venv "$VENV"
    "$PY" -m pip install --quiet --upgrade pip
    "$PY" -m pip install --quiet psutil
fi

exec "$PY" "$HERE/ping_flood_dos_test.py" "$@"
