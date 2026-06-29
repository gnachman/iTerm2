#!/usr/bin/env bash
#
# Spin up a clean virtualenv, install the in-tree iterm2 Python module
# (NOT whatever is pip-installed system-wide), and run the apply_layout
# new_session demo against a running iTerm2 instance.
#
# The point of the venv is to guarantee the demo runs against the updated
# copy of the iterm2 module in this checkout, so new_session support and
# the supports_apply_layout_new_session capability are present.
#
# Pre-requisite: a debug iTerm2 build that advertises the new_session
# capability (protocol >= 1.16) must already be running (e.g. `make run`),
# with the Python API enabled.
#
# Usage:
#   tests/run_apply_layout_new_session_demo.sh            # leave window open
#   tests/run_apply_layout_new_session_demo.sh --close    # auto-close at end

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENV_DIR="${REPO_ROOT}/tmp/new_session_demo_venv"
MODULE_DIR="${REPO_ROOT}/api/library/python/iterm2"
DEMO_SCRIPT="${REPO_ROOT}/tests/apply_layout_new_session_demo.py"

if [[ ! -d "${MODULE_DIR}" ]]; then
  echo "Cannot find iterm2 module at ${MODULE_DIR}" >&2
  exit 1
fi
if [[ ! -f "${DEMO_SCRIPT}" ]]; then
  echo "Cannot find demo script at ${DEMO_SCRIPT}" >&2
  exit 1
fi

mkdir -p "${REPO_ROOT}/tmp"

# Recreate the venv from scratch so the installed module always matches
# the in-tree source.
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
# both async_apply_layout and the new_session capability helper. If a
# stale module shadowed it, fail loudly rather than running the demo
# against the wrong code.
"${VENV_PY}" - <<'PY'
import iterm2
import iterm2.capabilities
import iterm2._version
ver = iterm2._version.__version__
has_layout = hasattr(iterm2.App, "async_apply_layout")
has_new_session = hasattr(
    iterm2.capabilities, "supports_apply_layout_new_session")
print(f"iterm2 module: {iterm2.__file__}")
print(f"iterm2 module version: {ver}")
print(f"async_apply_layout present: {has_layout}")
print(f"supports_apply_layout_new_session present: {has_new_session}")
if not (has_layout and has_new_session):
    raise SystemExit(
        f"installed iterm2 module {ver} is missing new_session support; "
        "the in-tree module is out of date or was shadowed by another copy.")
PY

echo
echo "Running the new_session demo against the live iTerm2 process"
echo "(make sure a debug iTerm2 build with new_session support is running)"
echo
exec "${VENV_PY}" "${DEMO_SCRIPT}" "$@"
