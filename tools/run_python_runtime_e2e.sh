#!/bin/bash
# Live uv Python-runtime end-to-end harness. Runs the ITERM2_UV_LIVE-gated tests
# in UvProvisionerLiveTests against the REAL hosted uv build and real uv
# provisioning. NOT a unit test: it hits the network (iterm2.com), downloads uv
# plus a CPython interpreter, builds a venv, and pip-installs iterm2/certifi/pyobjc.
# Mirrors tools/run_ai_live.sh: live, opt-in, and outside the default ModernTests run.
#
# Usage:
#   tools/run_python_runtime_e2e.sh            # both live tests
#   tools/run_python_runtime_e2e.sh download   # download + RSA-verify + install uv
#   tools/run_python_runtime_e2e.sh provision  # full-env provision + imports + REPL
#   tools/run_python_runtime_e2e.sh <ExactTestMethodName>
#
# What it covers today (Tier B and the provisioning slice of Tier C):
#   - Fetch the hosted manifest, select the compatible entry, RSA-verify the
#     downloaded tarball against the bundled public key, install uv, run
#     `uv --version` (testFetchManifestDownloadVerifyInstall).
#   - `uv venv` + `uv pip install --only-binary=:all: iterm2 certifi pyobjc` (a
#     passing install proves no compiler is needed), assert the .venv layout and
#     python-runtime.json marker, import iterm2 / objc (+ an AppKit symbol) /
#     certifi, and confirm `python -m asyncio` supports top-level await for the
#     REPL (testProvisionFullEnvironmentEndToEnd).
#
# The remaining Tier C matrix (an in-process iTermAPIServer driven by a launched
# script, migration rollback triggered by a bogus dependency, and the full
# cache/gate matrix) is exercised by tests/uv-migration-manual-test-plan.md and is
# future automation. Keep this script and that plan in sync with the doc's Testing
# section.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

case "${1:-all}" in
    all)
        FILTER="ModernTests/UvProvisionerLiveTests"
        ;;
    download)
        FILTER="ModernTests/UvProvisionerLiveTests/testFetchManifestDownloadVerifyInstall"
        ;;
    provision)
        FILTER="ModernTests/UvProvisionerLiveTests/testProvisionFullEnvironmentEndToEnd"
        ;;
    *)
        FILTER="ModernTests/UvProvisionerLiveTests/$1"
        ;;
esac

# xcodebuild's test runner does not inherit shell environment variables. The
# TEST_RUNNER_ prefix makes it forward this into the test process, where the live
# tests read ITERM2_UV_LIVE to opt in (they XCTSkip without it).
export TEST_RUNNER_ITERM2_UV_LIVE=1

echo "Running live uv runtime harness: $FILTER"
exec "$SCRIPT_DIR/run_tests.expect" "$FILTER"
