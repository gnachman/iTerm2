#!/bin/bash

echo "========================================"
echo "Running Bitwarden adapter tests"
echo "========================================"
echo ""

# Check if BW_TEST_PASSWORD is set
if [ -z "$BW_TEST_PASSWORD" ]; then
    echo "ERROR: BW_TEST_PASSWORD environment variable is not set"
    echo "Please set it to your Bitwarden master password to run tests"
    echo "Example: BW_TEST_PASSWORD='your-password' ./bitwarden_run_all_tests.sh"
    exit 1
fi

# Check if user is logged in to Bitwarden
BW_STATUS=$(bw status 2>/dev/null | python3 -c "import sys, json; print(json.load(sys.stdin).get('status', 'unknown'))" 2>/dev/null)
if [ "$BW_STATUS" = "unauthenticated" ]; then
    echo "ERROR: Not logged in to Bitwarden"
    echo "Please run 'bw login' first"
    exit 1
fi

echo "Bitwarden status: $BW_STATUS"
echo ""

TESTS=(
    "bitwarden_test_handshake.sh"
    "bitwarden_test_login.sh"
    "bitwarden_test_integration.sh"
)

PASSED=0
FAILED=0

for test in "${TESTS[@]}"; do
    echo "Running $test..."
    if timeout 120 ./"$test" > /tmp/bw_test_output.txt 2>&1; then
        echo "✓ $test PASSED"
        ((PASSED++))
    else
        echo "✗ $test FAILED"
        echo "Output:"
        cat /tmp/bw_test_output.txt
        ((FAILED++))
    fi
    echo ""
done

rm -f /tmp/bw_test_output.txt

echo "========================================"
echo "Test Results"
echo "========================================"
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo ""

if [ $FAILED -eq 0 ]; then
    echo "✓✓✓ All tests passed! ✓✓✓"
    exit 0
else
    echo "✗✗✗ Some tests failed ✗✗✗"
    exit 1
fi
