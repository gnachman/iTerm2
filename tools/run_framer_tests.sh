#!/bin/bash
# Runs every framer.py test file (tests/framer_*_test.py) and exits nonzero if any fails.
# Usage: tools/run_framer_tests.sh [--coverage]
#   PYTHON          interpreter to use (default: python3)
#   FRAMER_TEST_TMPDIR  parent for the tests' temporary directories (default: a fresh one,
#                   removed afterwards)
#   --coverage      also measure framer.py line coverage, including the framer processes the
#                   end-to-end tests start. Needs coverage.py importable by $PYTHON; use a
#                   venv rather than installing it into the system Python.
set -u
cd "$(dirname "$0")/.." || exit 2

PYTHON=${PYTHON:-python3}
COVERAGE=0
if [ "${1:-}" = "--coverage" ]; then
    COVERAGE=1
fi

CLEANUP_TMP=""
if [ -z "${FRAMER_TEST_TMPDIR:-}" ]; then
    FRAMER_TEST_TMPDIR=$(mktemp -d -t framer-tests)
    CLEANUP_TMP=$FRAMER_TEST_TMPDIR
fi
export FRAMER_TEST_TMPDIR

if [ $COVERAGE = 1 ]; then
    if ! "$PYTHON" -c "import coverage" 2>/dev/null; then
        echo "coverage.py is not importable by $PYTHON" >&2
        exit 2
    fi
    COVERAGE_DIR=$(mktemp -d -t framer-coverage)
    export COVERAGE_FILE=$COVERAGE_DIR/.coverage
    export COVERAGE_RCFILE=$COVERAGE_DIR/coveragerc
    # The end-to-end tests run a copy of framer.py elsewhere; map it back to the original.
    cat > "$COVERAGE_RCFILE" <<EOF
[run]
parallel = True
include = */OtherResources/framer.py
[paths]
framer =
    $PWD/OtherResources/
    */OtherResources/
EOF
    export FRAMER_E2E_COVERAGE=1
fi

failed=""
for test in tests/framer_*_test.py; do
    echo "=== $test"
    start=$(date +%s)
    if [ $COVERAGE = 1 ]; then
        "$PYTHON" -m coverage run "$test"
    else
        "$PYTHON" "$test"
    fi
    status=$?
    echo "=== $test: exit $status ($(( $(date +%s) - start ))s)"
    if [ $status -ne 0 ]; then
        failed="$failed $test"
    fi
done

if [ $COVERAGE = 1 ]; then
    "$PYTHON" -m coverage combine -q
    "$PYTHON" -m coverage report -m
    rm -rf "$COVERAGE_DIR"
fi
if [ -n "$CLEANUP_TMP" ]; then
    rm -rf "$CLEANUP_TMP"
fi

if [ -n "$failed" ]; then
    echo "FAILED:$failed"
    exit 1
fi
echo "All framer tests passed."
