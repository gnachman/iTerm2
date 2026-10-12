#!/usr/bin/env bash
#
# Run tests/context_menu_submenu_visibility_test.py against a running debug
# iTerm2, using the in-tree iterm2 Python module (NOT whatever is
# pip-installed system-wide), so the submenu and visible_when arguments of
# ContextMenuProviderRPC are available.
#
# Pre-requisite: a debug build with protocol 1.23 or later is running with
# the Python API enabled (e.g. `make run`). The script connects to the
# instance whose -suite matches IT2_SUITE, which defaults to the name of this
# checkout's directory, the same suite `make run` uses.
#
# Usage:
#   tests/run_context_menu_submenu_visibility_test.sh           # leave window open
#   tests/run_context_menu_submenu_visibility_test.sh --close   # close it at the end

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENV_DIR="${REPO_ROOT}/tmp/context_menu_test_venv"
MODULE_DIR="${REPO_ROOT}/api/library/python/iterm2"
TEST_SCRIPT="${REPO_ROOT}/tests/context_menu_submenu_visibility_test.py"

export IT2_SUITE="${IT2_SUITE:-$(basename "${REPO_ROOT}")}"
SOCKET="${HOME}/Library/Application Support/${IT2_SUITE}/private/socket"
if [[ ! -S "${SOCKET}" ]]; then
  echo "No API socket at ${SOCKET}." >&2
  echo "Start the debug build with \`make run\` and enable the Python API," >&2
  echo "or set IT2_SUITE to the suite of the instance you want to test." >&2
  exit 1
fi

mkdir -p "${REPO_ROOT}/tmp"
if [[ ! -x "${VENV_DIR}/bin/python" ]]; then
  echo "Creating venv at ${VENV_DIR}"
  python3 -m venv "${VENV_DIR}"
  "${VENV_DIR}/bin/python" -m pip install --quiet --upgrade pip
fi

# Editable install, so the venv always sees this checkout's module source.
echo "Installing dev iterm2 module from ${MODULE_DIR}"
"${VENV_DIR}/bin/pip" install --quiet -e "${MODULE_DIR}"

# Fail loudly if some other copy of the module shadowed the in-tree one.
"${VENV_DIR}/bin/python" - <<'PY'
import iterm2
import iterm2.capabilities
print(f"iterm2 module: {iterm2.__file__} ({iterm2.__version__})")
if not hasattr(iterm2.capabilities,
               "supports_context_menu_submenus_and_visibility"):
    raise SystemExit("The installed iterm2 module lacks submenu and "
                     "visible_when support; it was shadowed or is stale.")
PY

echo "Connecting to suite ${IT2_SUITE}"
exec "${VENV_DIR}/bin/python" "${TEST_SCRIPT}" "$@"
