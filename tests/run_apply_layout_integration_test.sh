#!/usr/bin/env bash
#
# Spin up a clean virtualenv, install the in-tree iterm2 Python module,
# and run the apply_layout integration test suite against a running
# iTerm2 instance.
#
# Pre-requisite: a debug iTerm2 build with the apply_layout BIF must
# already be running (e.g. `make run`). The test script connects to
# whichever iTerm2 process is currently accepting Python API connections.
#
# Usage:
#   tests/run_apply_layout_integration_test.sh                    # all tests
#   tests/run_apply_layout_integration_test.sh test_swap          # filter
#   tests/run_apply_layout_integration_test.sh -v                 # verbose

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENV_DIR="${REPO_ROOT}/tmp/integration_venv"
MODULE_DIR="${REPO_ROOT}/api/library/python/iterm2"
TEST_SCRIPT="${REPO_ROOT}/tests/apply_layout_integration_test.py"

if [[ ! -d "${MODULE_DIR}" ]]; then
  echo "Cannot find iterm2 module at ${MODULE_DIR}" >&2
  exit 1
fi
if [[ ! -f "${TEST_SCRIPT}" ]]; then
  echo "Cannot find test script at ${TEST_SCRIPT}" >&2
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

# Sanity-check that the installed module exposes async_apply_layout (it
# was added in 2.16; the system-installed module may be 2.15).
"${VENV_PY}" - <<'PY'
import iterm2
import iterm2._version
ver = iterm2._version.__version__
ok = hasattr(iterm2.App, 'async_apply_layout')
print(f"iterm2 module version: {ver}")
print(f"async_apply_layout present: {ok}")
if not ok:
    raise SystemExit(
        f"installed iterm2 module {ver} does not expose async_apply_layout; "
        "is the in-tree module out of date?")
PY

echo
echo "Running integration tests against the live iTerm2 process"
echo "(make sure a debug iTerm2 build with apply_layout is running)"
echo
exec "${VENV_PY}" "${TEST_SCRIPT}" "$@"
