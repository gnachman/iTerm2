#!/bin/bash
# Runs tests/apply_layout_focus_repro.py in a throwaway virtualenv that uses
# the in-tree iterm2 Python module (api/library/python/iterm2), NOT whatever
# is pip-installed globally. This guarantees the repro exercises the module
# code in this checkout.
#
# Any extra arguments are forwarded to the repro script, e.g.:
#     tests/run_apply_layout_focus_repro.sh --close
#
# The venv lives under tmp/ and is reused across runs; delete it to rebuild:
#     rm -rf tmp/apply_layout_focus_venv

set -euo pipefail

# Resolve repo root from this script's location so it works from anywhere.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

MODULE_DIR="${REPO_ROOT}/api/library/python/iterm2"
REPRO="${REPO_ROOT}/tests/apply_layout_focus_repro.py"
VENV="${REPO_ROOT}/tmp/apply_layout_focus_venv"

if [[ ! -f "${MODULE_DIR}/setup.py" ]]; then
    echo "error: local iterm2 module not found at ${MODULE_DIR}" >&2
    exit 1
fi

if [[ ! -d "${VENV}" ]]; then
    echo "Creating virtualenv at ${VENV}"
    python3 -m venv "${VENV}"
    # Editable install so the venv imports straight from MODULE_DIR; this
    # also pulls in the module's deps (protobuf, websockets).
    "${VENV}/bin/pip" install --quiet --upgrade pip
    "${VENV}/bin/pip" install --quiet -e "${MODULE_DIR}"
fi

# Confirm we are actually running the in-tree module, not a stray global one.
echo "Using iterm2 module from:"
"${VENV}/bin/python" -c "import iterm2, os; print('  ' + os.path.dirname(iterm2.__file__))"

exec "${VENV}/bin/python" "${REPRO}" "$@"
