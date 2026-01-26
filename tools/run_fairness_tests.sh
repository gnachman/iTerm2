#!/bin/bash
#
# Run fairness scheduler tests in isolation from legacy tests.
# Usage:
#   ./tools/run_fairness_tests.sh              # Run all fairness tests
#   ./tools/run_fairness_tests.sh SessionTests # Run specific test class
#

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

# Test classes that are part of the fairness scheduler test suite
# Milestone 1: FairnessScheduler (Checkpoint 1)
FAIRNESS_TEST_CLASSES=(
    "FairnessSchedulerSessionTests"
    "FairnessSchedulerBusyListTests"
    "FairnessSchedulerTurnExecutionTests"
    "FairnessSchedulerRoundRobinTests"
)

# Milestone 2: TokenExecutor Fairness (Checkpoint 2)
TOKENEXECUTOR_TEST_CLASSES=(
    "TokenExecutorNonBlockingTests"
    "TokenExecutorAccountingTests"
    "TokenExecutorExecuteTurnTests"
    "TokenExecutorBudgetEdgeCaseTests"
    "TokenExecutorSchedulerEntryPointTests"
    "TokenExecutorLegacyRemovalTests"
    "TokenExecutorCleanupTests"
    "TokenExecutorAccountingInvariantTests"
)

# All test classes
ALL_TEST_CLASSES=("${FAIRNESS_TEST_CLASSES[@]}" "${TOKENEXECUTOR_TEST_CLASSES[@]}")

# Build the -only-testing arguments
build_only_testing_args() {
    local filter="$1"
    local args=""
    local classes_to_check=()

    # Determine which classes to check based on filter
    case "$filter" in
        milestone1|phase1|checkpoint1)
            classes_to_check=("${FAIRNESS_TEST_CLASSES[@]}")
            ;;
        milestone2|phase2|checkpoint2)
            classes_to_check=("${TOKENEXECUTOR_TEST_CLASSES[@]}")
            ;;
        *)
            classes_to_check=("${ALL_TEST_CLASSES[@]}")
            ;;
    esac

    for class in "${classes_to_check[@]}"; do
        if [[ -z "$filter" ]] || [[ "$filter" == "milestone1" ]] || [[ "$filter" == "milestone2" ]] || \
           [[ "$filter" == "phase1" ]] || [[ "$filter" == "phase2" ]] || \
           [[ "$filter" == "checkpoint1" ]] || [[ "$filter" == "checkpoint2" ]] || \
           [[ "$class" == *"$filter"* ]]; then
            args="$args -only-testing:ModernTests/$class"
        fi
    done

    echo "$args"
}

# Parse arguments
FILTER=""
VERBOSE=0

while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        *)
            FILTER="$1"
            shift
            ;;
    esac
done

ONLY_TESTING_ARGS=$(build_only_testing_args "$FILTER")

if [[ -z "$ONLY_TESTING_ARGS" ]]; then
    echo "Error: No matching test classes found for filter: $FILTER"
    echo ""
    echo "Usage: $0 [filter]"
    echo ""
    echo "Filters:"
    echo "  milestone1  - Run FairnessScheduler tests only (Checkpoint 1)"
    echo "  milestone2  - Run TokenExecutor fairness tests only (Checkpoint 2)"
    echo "  <classname> - Run tests matching class name"
    echo "  (no filter) - Run all fairness tests"
    echo ""
    echo "Milestone 1 test classes (FairnessScheduler):"
    for class in "${FAIRNESS_TEST_CLASSES[@]}"; do
        echo "  - $class"
    done
    echo ""
    echo "Milestone 2 test classes (TokenExecutor):"
    for class in "${TOKENEXECUTOR_TEST_CLASSES[@]}"; do
        echo "  - $class"
    done
    exit 1
fi

echo "Running fairness scheduler tests..."
if [[ -n "$FILTER" ]]; then
    echo "Filter: $FILTER"
fi
echo ""

# Clean up previous test results
rm -rf "TestResults/FairnessSchedulerTests.xcresult"

# Run tests (with code signing disabled for command-line builds)
SIGNING_FLAGS="CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO"

if [[ $VERBOSE -eq 1 ]]; then
    xcodebuild test \
        -project iTerm2.xcodeproj \
        -scheme ModernTests \
        $ONLY_TESTING_ARGS \
        -parallel-testing-enabled NO \
        -resultBundlePath "TestResults/FairnessSchedulerTests.xcresult" \
        $SIGNING_FLAGS \
        2>&1 | tee test_output.log
else
    xcodebuild test \
        -project iTerm2.xcodeproj \
        -scheme ModernTests \
        $ONLY_TESTING_ARGS \
        -parallel-testing-enabled NO \
        -resultBundlePath "TestResults/FairnessSchedulerTests.xcresult" \
        $SIGNING_FLAGS \
        2>&1 | grep -E "(Test Case|passed|failed|error:|\*\*)"
fi

echo ""
echo "Done."
