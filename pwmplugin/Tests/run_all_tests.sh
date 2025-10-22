#!/bin/bash

echo "========================================"
echo "Running all password manager tests"
echo "========================================"
echo ""

TESTS=(
    "test_handshake.sh"
    "test_login.sh"
    "test_list_accounts.sh"
    "test_get_password.sh"
    "test_set_password.sh"
    "test_add_account.sh"
    "test_delete_account.sh"
    "test_integration.sh"
)

PASSED=0
FAILED=0

for test in "${TESTS[@]}"; do
    echo "Running $test..."
    if timeout 60 ./"$test" > /dev/null 2>&1; then
        echo "✓ $test PASSED"
        ((PASSED++))
    else
        echo "✗ $test FAILED"
        ((FAILED++))
    fi
    echo ""
done

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
