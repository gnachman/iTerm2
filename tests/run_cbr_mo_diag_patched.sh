#!/bin/bash
#
# Run cbr_mo_diag.py against the running development iTerm2 using the PATCHED
# in-repo iterm2 Python library (version 2.23, with the ListSessionsResponse
# selected_tab_id / active_session_id fix) instead of whatever is installed in
# the uv venv. Because 2.23 is outside the affected range [2.21, 2.23), this
# exercises the "gate off" path: the CreateTab focus-deferral workaround should
# NOT engage, and current_tab / current_session must be correct purely from the
# proto fields.
#
# Prerequisites:
#   - A development build is running under the "iterm2-alt" suite (make run).
#   - The Python API is enabled and ~/Library/Application Support/iterm2-alt/
#     contains disable-automation-auth (so no auth UI prompt).
#
# Overridable via environment:
#   IT2_SUITE       prefs/support suite the dev app uses      (default: iterm2-alt)
#   IT2_APP_PATH    dev app bundle for the cookie request     (default: repo Build/Development/iTerm2.app)
#   VENV_PYTHON     interpreter to run under                  (default: the suite's uv 3.14 venv)
#   DIAG_SCRIPT     script to run                             (default: the suite's Scripts/cbr_mo_diag.py)

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export IT2_SUITE="${IT2_SUITE:-iterm2-alt}"
export IT2_APP_PATH="${IT2_APP_PATH:-$REPO/Build/Development/iTerm2.app}"

VENV_PYTHON="${VENV_PYTHON:-$HOME/.config/$IT2_SUITE/AppSupport/uv/venvs/3.14/bin/python}"
DIAG_SCRIPT="${DIAG_SCRIPT:-$HOME/Library/Application Support/$IT2_SUITE/Scripts/cbr_mo_diag.py}"

# The in-repo library package parent. Prepending it to PYTHONPATH makes "import
# iterm2" resolve to the patched 2.23 tree while its dependencies (websockets,
# protobuf, pyobjc) still come from the venv's site-packages.
PATCHED_LIB="$REPO/api/library/python/iterm2"

# Fail early with a clear message if anything is missing.
for p in "$VENV_PYTHON" "$DIAG_SCRIPT" "$PATCHED_LIB/iterm2/__init__.py" "$IT2_APP_PATH"; do
    if [[ ! -e "$p" ]]; then
        echo "error: not found: $p" >&2
        exit 1
    fi
done
if [[ ! -S "$HOME/Library/Application Support/$IT2_SUITE/private/socket" ]]; then
    echo "error: no API socket at ~/Library/Application Support/$IT2_SUITE/private/socket" >&2
    echo "       Is the development build running under -suite $IT2_SUITE with the Python API enabled?" >&2
    exit 1
fi

export PYTHONPATH="$PATCHED_LIB${PYTHONPATH:+:$PYTHONPATH}"
export PYTHONUNBUFFERED=1

# Confirm which library version actually got loaded before running the script,
# so it is obvious whether the patched (2.23) tree is in effect.
LOADED_VERSION="$("$VENV_PYTHON" -c 'import iterm2; print(iterm2.__version__)')"
echo "Using iterm2 library version: $LOADED_VERSION (from $PATCHED_LIB)"
if [[ "$LOADED_VERSION" != "2.23" ]]; then
    echo "warning: expected 2.23 from the in-repo tree but loaded $LOADED_VERSION" >&2
fi
echo "IT2_SUITE=$IT2_SUITE"
echo "IT2_APP_PATH=$IT2_APP_PATH"
echo "Running: $DIAG_SCRIPT"
echo "----------------------------------------"

exec "$VENV_PYTHON" "$DIAG_SCRIPT"
