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
)

# Milestone 4: TaskNotifier Changes (Checkpoint 4)
TASKNOTIFIER_TEST_CLASSES=(
    "TaskNotifierDispatchSourceProtocolTests"
    "TaskNotifierSelectLoopTests"
    "TaskNotifierMixedModeTests"
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
    "DispatchSourceLifecycleIntegrationTests"
    "BackpressureIntegrationTests"
    "SessionLifecycleIntegrationTests"
)

# All test classes
ALL_TEST_CLASSES=("${FAIRNESS_TEST_CLASSES[@]}" "${TOKENEXECUTOR_TEST_CLASSES[@]}" "${PTYTASK_TEST_CLASSES[@]}" "${TASKNOTIFIER_TEST_CLASSES[@]}" "${INTEGRATION_TEST_CLASSES[@]}")

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
