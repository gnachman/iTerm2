#!/bin/bash
#
# Run fairness scheduler tests in isolation from legacy tests.
# Usage:
#   ./tools/run_fairness_tests.sh              # Run all fairness tests
#   ./tools/run_fairness_tests.sh SessionTests # Run specific test class
#

# Don't use set -e so we can capture exit codes and check for crashes
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

# Crash detection: Check for existing crash reports before tests run
CRASH_DIR="$HOME/Library/Logs/DiagnosticReports"

# Check for pre-existing crash reports
EXISTING_CRASHES=$(ls -1 "$CRASH_DIR"/*iTerm*.ips 2>/dev/null)
if [[ -n "$EXISTING_CRASHES" ]]; then
    echo "=========================================="
    echo "ERROR: Pre-existing iTerm2 crash reports found"
    echo "=========================================="
    echo "$EXISTING_CRASHES"
    echo ""
    echo "Review and/or delete before running tests:"
    echo "  - To view: head -100 <file> | grep -A5 'exception\\|termination'"
    echo "  - To delete: rm $CRASH_DIR/*iTerm*.ips"
    echo "=========================================="
    exit 1
fi

CRASH_REPORTS_BEFORE=0

# Function to check for new crash reports
check_for_crashes() {
    local crash_reports_after=$(ls -1 "$CRASH_DIR"/*iTerm*.ips 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$crash_reports_after" -gt "$CRASH_REPORTS_BEFORE" ]]; then
        echo ""
        echo "=========================================="
        echo "WARNING: NEW CRASH REPORT(S) DETECTED!"
        echo "=========================================="
        echo "New crash reports found in $CRASH_DIR:"
        # Show new crash reports (those newer than when we started)
        ls -lt "$CRASH_DIR"/*iTerm*.ips 2>/dev/null | head -$((crash_reports_after - CRASH_REPORTS_BEFORE))
        echo ""
        echo "To view crash details:"
        echo "  head -100 $CRASH_DIR/iTerm2-*.ips | grep -A5 'exception\|termination'"
        echo "=========================================="
        return 1
    fi
    return 0
}

# Test classes that are part of the fairness scheduler test suite
# Milestone 1: FairnessScheduler (Checkpoint 1)
FAIRNESS_TEST_CLASSES=(
    "FairnessSchedulerSessionTests"
    "FairnessSchedulerBusyListTests"
    "FairnessSchedulerTurnExecutionTests"
    "FairnessSchedulerRoundRobinTests"
    "FairnessSchedulerThreadSafetyTests"
    "FairnessSchedulerLifecycleEdgeCaseTests"
    "FairnessSchedulerSustainedLoadTests"
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
    "TokenExecutorCompletionCallbackTests"
    "TokenExecutorBudgetEnforcementDetailedTests"
    "TokenExecutorSameQueueGroupBoundaryTests"
    "TokenExecutorAvailableSlotsBoundaryTests"
    "TokenExecutorHighPriorityOrderingTests"
    "TwoTierTokenQueueTests"
    "TwoTierTokenQueueGroupingTests"
)

# Milestone 3: PTYTask Dispatch Sources (Checkpoint 3)
PTYTASK_TEST_CLASSES=(
    "PTYTaskDispatchSourceLifecycleTests"
    "PTYTaskReadStateTests"
    "PTYTaskWriteStateTests"
    "PTYTaskEventHandlerTests"
    "PTYTaskPauseStateTests"
    "PTYTaskIoAllowedPredicateTests"
    "PTYTaskBackpressureIntegrationTests"
    "PTYTaskUseDispatchSourceTests"
    "PTYTaskStateTransitionTests"
    "PTYTaskEdgeCaseTests"
    "PTYTaskReadHandlerPipelineTests"
    "PTYTaskWritePathRoundTripTests"
)

# Milestone 4: TaskNotifier Changes (Checkpoint 4)
TASKNOTIFIER_TEST_CLASSES=(
    "TaskNotifierDispatchSourceProtocolTests"
    "TaskNotifierSelectLoopTests"
    "TaskNotifierMixedModeTests"
)

# Milestone 4b: Coprocess Bridge Tests (separate due to hang investigation)
COPROCESS_TEST_CLASSES=(
    "CoprocessDataFlowBridgeTests"
)

# Milestone 5: Integration (Checkpoint 5)
INTEGRATION_TEST_CLASSES=(
    "IntegrationRegistrationTests"
    "IntegrationUnregistrationTests"
    "IntegrationAutomaticSchedulingTests"
    "IntegrationRekickTests"
    "IntegrationBackgroundForegroundFairnessTests"
    "IntegrationMutationQueueTests"
    "IntegrationDispatchSourceActivationTests"
    "IntegrationPTYSessionWiringTests"
    "PTYSessionWiringTests"
    "PTYSessionBackpressureWiringTests"
    "DispatchSourceLifecycleIntegrationTests"
    "BackpressureIntegrationTests"
    "SessionLifecycleIntegrationTests"
)

# All test classes
ALL_TEST_CLASSES=("${FAIRNESS_TEST_CLASSES[@]}" "${TOKENEXECUTOR_TEST_CLASSES[@]}" "${PTYTASK_TEST_CLASSES[@]}" "${TASKNOTIFIER_TEST_CLASSES[@]}" "${COPROCESS_TEST_CLASSES[@]}" "${INTEGRATION_TEST_CLASSES[@]}")

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
        milestone3|phase3|checkpoint3)
            classes_to_check=("${PTYTASK_TEST_CLASSES[@]}")
            ;;
        milestone4|phase4|checkpoint4)
            classes_to_check=("${TASKNOTIFIER_TEST_CLASSES[@]}")
            ;;
        coprocess)
            classes_to_check=("${COPROCESS_TEST_CLASSES[@]}")
            ;;
        milestone5|phase5|checkpoint5)
            classes_to_check=("${INTEGRATION_TEST_CLASSES[@]}")
            ;;
        *)
            classes_to_check=("${ALL_TEST_CLASSES[@]}")
            ;;
    esac

    for class in "${classes_to_check[@]}"; do
        if [[ -z "$filter" ]] || [[ "$filter" == "milestone1" ]] || [[ "$filter" == "milestone2" ]] || [[ "$filter" == "milestone3" ]] || [[ "$filter" == "milestone4" ]] || [[ "$filter" == "milestone5" ]] || \
           [[ "$filter" == "phase1" ]] || [[ "$filter" == "phase2" ]] || [[ "$filter" == "phase3" ]] || [[ "$filter" == "phase4" ]] || [[ "$filter" == "phase5" ]] || \
           [[ "$filter" == "checkpoint1" ]] || [[ "$filter" == "checkpoint2" ]] || [[ "$filter" == "checkpoint3" ]] || [[ "$filter" == "checkpoint4" ]] || [[ "$filter" == "checkpoint5" ]] || \
           [[ "$filter" == "coprocess" ]] || [[ "$class" == *"$filter"* ]]; then
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
    echo "  milestone3  - Run PTYTask dispatch source tests only (Checkpoint 3)"
    echo "  milestone4  - Run TaskNotifier dispatch source tests only (Checkpoint 4)"
    echo "  milestone5  - Run Integration tests only (Checkpoint 5)"
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
    echo ""
    echo "Milestone 3 test classes (PTYTask):"
    for class in "${PTYTASK_TEST_CLASSES[@]}"; do
        echo "  - $class"
    done
    echo ""
    echo "Milestone 4 test classes (TaskNotifier):"
    for class in "${TASKNOTIFIER_TEST_CLASSES[@]}"; do
        echo "  - $class"
    done
    echo ""
    echo "Milestone 5 test classes (Integration):"
    for class in "${INTEGRATION_TEST_CLASSES[@]}"; do
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

# Use a temp file to capture output so we can both display and analyze it
TEST_OUTPUT=$(mktemp)
trap "rm -f $TEST_OUTPUT" EXIT

if [[ $VERBOSE -eq 1 ]]; then
    xcodebuild test \
        -project iTerm2.xcodeproj \
        -scheme ModernTests \
        $ONLY_TESTING_ARGS \
        -parallel-testing-enabled NO \
        -resultBundlePath "TestResults/FairnessSchedulerTests.xcresult" \
        $SIGNING_FLAGS \
        2>&1 | tee "$TEST_OUTPUT" | tee test_output.log
    XCODE_EXIT=${PIPESTATUS[0]}
else
    xcodebuild test \
        -project iTerm2.xcodeproj \
        -scheme ModernTests \
        $ONLY_TESTING_ARGS \
        -parallel-testing-enabled NO \
        -resultBundlePath "TestResults/FairnessSchedulerTests.xcresult" \
        $SIGNING_FLAGS \
        2>&1 | tee "$TEST_OUTPUT" | grep -E "(Test Case|passed|failed|error:|\*\*)"
    XCODE_EXIT=${PIPESTATUS[0]}
fi

echo ""

# Check for crash indicators in test output
if grep -q "Program crashed" "$TEST_OUTPUT" 2>/dev/null; then
    echo "=========================================="
    echo "WARNING: TEST CRASHED! (detected 'Program crashed' in output)"
    echo "=========================================="
    XCODE_EXIT=1
fi

# Check for new crash reports
if ! check_for_crashes; then
    XCODE_EXIT=1
fi

# Final status
if [[ $XCODE_EXIT -eq 0 ]]; then
    echo "Done. All tests passed."
else
    echo "Done. Tests FAILED or CRASHED (exit code: $XCODE_EXIT)"
fi

exit $XCODE_EXIT
