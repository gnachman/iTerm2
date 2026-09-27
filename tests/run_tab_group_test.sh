#!/usr/bin/env bash
#
# Spin up a clean virtualenv, install the in-tree iterm2 Python module
# (NOT whatever is pip-installed system-wide), and run the interactive
# tab-group test against a running iTerm2 instance.
#
# The venv guarantees the test runs against the updated copy of the iterm2
# module in this checkout, so TabGroup and the supports_tab_groups
# capability (protocol >= 1.19) are present.
#
# Pre-requisite: a debug iTerm2 build that advertises the tab-group
# capability must already be running (e.g. `make run`), with the Python
# API enabled (Settings > General > Magic > Enable Python API).
#
# The iterm2 module locates the right socket and auth material from
# IT2_SUITE (the -suite the build runs under; `make run` here uses the
# directory name) and IT2_APP_PATH (the app bundle used to obtain an
# AppleScript auth cookie). Override either if your setup differs, or set
# ITERM2_COOKIE / ITERM2_KEY to skip AppleScript auth entirely.
#
# Usage:
#   tests/run_tab_group_test.sh
#   IT2_SUITE=claude-iterm2-alt4 tests/run_tab_group_test.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENV_DIR="${REPO_ROOT}/tmp/tab_group_test_venv"
MODULE_DIR="${REPO_ROOT}/api/library/python/iterm2"
TEST_SCRIPT="${REPO_ROOT}/tests/tab_group_test.py"

: "${IT2_SUITE:=$(basename "${REPO_ROOT}")}"
: "${IT2_APP_PATH:=${REPO_ROOT}/build/Development/iTerm2.app}"
export IT2_SUITE IT2_APP_PATH

if [[ ! -d "${MODULE_DIR}" ]]; then
  echo "Cannot find iterm2 module at ${MODULE_DIR}" >&2
  exit 1
fi
if [[ ! -f "${TEST_SCRIPT}" ]]; then
  echo "Cannot find test script at ${TEST_SCRIPT}" >&2
  exit 1
fi

mkdir -p "${REPO_ROOT}/tmp"

# Recreate the venv from scratch so the installed module always matches the
# in-tree source.
if [[ -d "${VENV_DIR}" ]]; then
  echo "Removing stale venv at ${VENV_DIR}"
  rm -rf "${VENV_DIR}"
fi

echo "Creating venv at ${VENV_DIR}"
python3 -m venv "${VENV_DIR}"

VENV_PY="${VENV_DIR}/bin/python"
VENV_PIP="${VENV_DIR}/bin/pip"

echo "Upgrading pip"
"${VENV_PY}" -m pip install --quiet --upgrade pip

echo "Installing dev iterm2 module from ${MODULE_DIR}"
"${VENV_PIP}" install --quiet -e "${MODULE_DIR}"

# Confirm the venv really picked up THIS checkout's module: it must expose
# both the TabGroup class and the supports_tab_groups capability helper. If
# a stale module shadowed it, fail loudly rather than running against the
# wrong code.
"${VENV_PY}" - <<'PY'
import iterm2
import iterm2.capabilities
import iterm2._version
ver = iterm2._version.__version__
has_tab_group = hasattr(iterm2, "TabGroup")
has_cap = hasattr(iterm2.capabilities, "supports_tab_groups")
has_tab_attr = hasattr(iterm2.Tab, "tab_group")
has_win_attr = hasattr(iterm2.Window, "async_create_tab_group")
print(f"iterm2 module: {iterm2.__file__}")
print(f"iterm2 module version: {ver}")
print(f"TabGroup present: {has_tab_group}")
print(f"supports_tab_groups present: {has_cap}")
print(f"Tab.tab_group present: {has_tab_attr}")
print(f"Window.async_create_tab_group present: {has_win_attr}")
if not (has_tab_group and has_cap and has_tab_attr and has_win_attr):
    raise SystemExit(
        f"installed iterm2 module {ver} is missing tab-group support; "
        "the in-tree module is out of date or was shadowed by another copy.")
PY

echo
echo "Running the interactive tab-group test against the live iTerm2 process."
echo "It creates its own window; your other windows are left alone."
echo "  IT2_SUITE=${IT2_SUITE}"
echo "  IT2_APP_PATH=${IT2_APP_PATH}"
echo "  ITERM2_COOKIE=${ITERM2_COOKIE:+<set>}"
echo
exec "${VENV_PY}" "${TEST_SCRIPT}" "$@"
