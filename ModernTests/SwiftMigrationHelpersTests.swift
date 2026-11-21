//
//  SwiftMigrationHelpersTests.swift
//  iTerm2
//
//  Tests for the Swift migration helper library (docs/swift-migration/phase0.md section 7).
//
//  A failed beta assertion is fatal in Development, which is what the tests are built with; in
//  the test host iTermBetaAssertionTestObserver turns the crash into a failure of the running
//  test. Most failure paths are driven through the injectable entry points, which take the
//  failure handler as a parameter, with a handler that records the failure.
//  SwiftMigrationPublicHelperPolicyTests calls the public entry points with the crash hook
//  replaced, to check that they apply the build's policy.
//

import XCTest
@testable import iTerm2SharedARC

/// Records failures reported through an iTermBetaAssertionFailureHandler.
private final class FailureRecorder {
    struct Failure {
        let message: String
        let file: String
        let line: UInt
        let function: String
    }

    private(set) var failures = [Failure]()

    var handler: iTermBetaAssertionFailureHandler {
        return { [unowned self] message, file, line, function in
            failures.append(Failure(message: message,
                                    file: "\(file)",
                                    line: line,
                                    function: "\(function)"))
        }
    }
}

/// Runs `operation` with a recording handler and checks the result and whether it failed.
private func check<T: Equatable>(_ description: String,
                                 _ operation: (iTermBetaAssertionFailureHandler) -> T,
                                 _ expected: T,
                                 fails: Bool,
                                 file: StaticString = #filePath,
                                 line: UInt = #line) {
    let recorder = FailureRecorder()
    let actual = operation(recorder.handler)
    XCTAssertEqual(actual, expected, description, file: file, line: line)
    XCTAssertEqual(recorder.failures.count, fails ? 1 : 0,
                   "\(description): expected \(fails ? "one failure" : "no failure"), got \(recorder.failures.map(\.message))",
                   file: file, line: line)
}

/// The value that applies on the processor the tests run on. The two processors' C conversions
/// of a float to an integer differ for NaN and out-of-range values (translation-rules.md
/// section 1).
private func valueOnThisProcessor<T>(arm64: T, x86_64: T) -> T {
#if arch(arm64)
    return arm64
#elseif arch(x86_64)
    return x86_64
#else
#error("Only arm64 and x86_64 are supported")
#endif
}

// MARK: - Beta assertions

final class SwiftMigrationBetaAssertTests: XCTestCase {
    func testTestBuildIsABetaBuild() {
        // The tests build with the Development configuration, which defines BETA, so a failed
        // beta assertion is fatal here as ITBetaAssert is (and iTermBetaAssertionTestObserver
        // makes it fail the running test).
        XCTAssertTrue(iTermBetaAssertions.areFatal)
    }

    func testSwiftBetaConditionAgreesWithObjectiveCMacro() {
        // The Swift BETA compilation condition of iTerm2SharedARC and the C BETA macro are set
        // separately in the project. This checks the configuration the tests are built in; a
        // disagreement in any configuration also fails to link (see DebugLogging.m).
        XCTAssertEqual(iTermSwiftBetaConditionIsActive, iTermBetaMacroIsDefined())
    }

    func testTestBuildHasSwiftBetaCondition() {
        // Development defines BETA for Swift as it does for C, so it_conservativeBetaAssert is
        // compiled in.
        XCTAssertTrue(iTermSwiftBetaConditionIsActive)
    }

    func testPassingAssertionDoesNotReport() {
        let recorder = FailureRecorder()
        var messageEvaluated = false
        it_betaAssert(true, { messageEvaluated = true; return "unused" }(), onFailure: recorder.handler)
        XCTAssertTrue(recorder.failures.isEmpty)
        XCTAssertFalse(messageEvaluated, "The message is built only on failure")
    }

    func testFailingAssertionReportsMessageAndLocation() {
        let recorder = FailureRecorder()
        let expectedLine: UInt = #line + 1
        it_betaAssert(1 + 1 == 3, "arithmetic is broken", onFailure: recorder.handler)
        XCTAssertEqual(recorder.failures.count, 1)
        XCTAssertEqual(recorder.failures.first?.message, "arithmetic is broken")
        XCTAssertEqual(recorder.failures.first?.line, expectedLine)
        XCTAssertTrue(recorder.failures.first?.file.hasSuffix("SwiftMigrationHelpersTests.swift") ?? false)
        XCTAssertEqual(recorder.failures.first?.function, "testFailingAssertionReportsMessageAndLocation()")
    }

    func testConditionIsAlwaysEvaluated() {
        // ITBetaAssert evaluates its condition in every build.
        var evaluations = 0
        let recorder = FailureRecorder()
        it_betaAssert({ evaluations += 1; return true }(), onFailure: recorder.handler)
        XCTAssertEqual(evaluations, 1)
    }

    func testConservativeAssertionDisabledDoesNotEvaluateCondition() {
        let recorder = FailureRecorder()
        var evaluated = false
        it_conservativeBetaAssert({ evaluated = true; return false }(),
                                  "unused",
                                  enabled: false,
                                  onFailure: recorder.handler)
        XCTAssertFalse(evaluated)
        XCTAssertTrue(recorder.failures.isEmpty)
    }

    func testConservativeAssertionEnabledReportsFailure() {
        let recorder = FailureRecorder()
        it_conservativeBetaAssert(false, "expensive check failed", enabled: true, onFailure: recorder.handler)
        XCTAssertEqual(recorder.failures.map(\.message), ["expensive check failed"])
    }

    func testConservativeAssertionEnabledPassingDoesNotReport() {
        let recorder = FailureRecorder()
        it_conservativeBetaAssert(true, "unused", enabled: true, onFailure: recorder.handler)
        XCTAssertTrue(recorder.failures.isEmpty)
    }

    func testConservativeAssertionIsEnabledInTestBuild() {
        XCTAssertTrue(iTermBetaAssertions.conservativeAssertionsEnabled)
    }

    func testFailureInBetaBuildCrashes() {
        let crashes = FailureRecorder()
        iTermBetaAssertionFailed("beta failure", file: "File.swift", line: 12, function: "f()",
                                 fatal: true, crash: crashes.handler)
        XCTAssertEqual(crashes.failures.count, 1)
        XCTAssertEqual(crashes.failures.first?.message, "beta failure")
        XCTAssertEqual(crashes.failures.first?.file, "File.swift")
        XCTAssertEqual(crashes.failures.first?.line, 12)
        XCTAssertEqual(crashes.failures.first?.function, "f()")
    }

    func testFailureInReleaseBuildLogsAndContinues() {
        let crashes = FailureRecorder()
        iTermBetaAssertionFailed("release failure", file: "File.swift", line: 12, function: "f()",
                                 fatal: false, crash: crashes.handler)
        XCTAssertTrue(crashes.failures.isEmpty)
    }

    func testPublicAssertionWithTrueConditionDoesNothing() {
        // The public entry point with a passing condition must not crash in any build.
        it_betaAssert(true, "unused")
        it_conservativeBetaAssert(true, "unused")
    }
}

// MARK: - A failed beta assertion in an ordinary test

/// With no handler installed by the test, a helper's assertion fails the running test with its
/// message (iTermBetaAssertionTestObserver) instead of crashing the test host or only logging.
final class SwiftMigrationBetaAssertionFailsTestTests: XCTestCase {
    private func expectBetaAssertionFailure(containing text: String,
                                            file: StaticString = #filePath,
                                            line: UInt = #line,
                                            _ body: () -> Void) {
        let options = XCTExpectedFailure.Options()
        options.issueMatcher = { issue in
            issue.compactDescription.contains("[BETA ASSERT] \(text)")
        }
        XCTExpectFailure("a failed beta assertion fails the running test", options: options) {
            body()
        }
    }

    func testOverflowInAHelperFailsTheRunningTest() {
        expectBetaAssertionFailure(containing: "overflow in 127 + 1 (Int8)") {
            // The test continues after the failure, with the C result.
            XCTAssertEqual(it_add(Int8.max, Int8(1)), Int8.min)
        }
    }

    func testFloatConversionInAHelperFailsTheRunningTest() {
        expectBetaAssertionFailure(containing: "converting nan (Double) to Int32 is out of range") {
            _ = it_floatToInteger(Double.nan, to: Int32.self)
        }
    }

    func testBetaAssertFailsTheRunningTest() {
        expectBetaAssertionFailure(containing: "an assumption that does not hold") {
            it_betaAssert(false, "an assumption that does not hold")
        }
    }

    func testObserverIsRegistered() {
        XCTAssertTrue(iTermBetaAssertionTestObserver.isRegistered)
    }
}

// MARK: - Public entry points and the build's policy

/// Calls the public helpers, which report to iTermBetaAssertionFailed, with the crash hook
/// replaced by a recorder. This checks that each public helper applies the build's policy: in a
/// BETA build (which the tests are) a failure reaches the crash hook exactly once.
///
/// These tests replace process-wide state (iTermBetaAssertions.crashHandler and
/// iTermBetaAssertionsCrash). setUp saves it and tearDown restores it, so a failing assertion
/// cannot leave it replaced. They rely on XCTest running the tests of a process one at a time on
/// the main thread; a parallel run puts test classes in separate processes, each with its own
/// copy of the state.
final class SwiftMigrationPublicHelperPolicyTests: XCTestCase {
    private var savedCrashHandler: iTermBetaAssertionFailureHandler?
    private var savedFatal = iTermBetaAssertionsCrash
    private var crashes = FailureRecorder()

    override func setUp() {
        super.setUp()
        savedCrashHandler = iTermBetaAssertions.crashHandler
        savedFatal = iTermBetaAssertionsCrash
        crashes = FailureRecorder()
        iTermBetaAssertions.crashHandler = crashes.handler
    }

    override func tearDown() {
        if let savedCrashHandler {
            iTermBetaAssertions.crashHandler = savedCrashHandler
        }
        iTermBetaAssertionsCrash = savedFatal
        super.tearDown()
    }

    /// Checks that the crash hook was called exactly once, with this message and this line of
    /// this file.
    private func assertCrashedOnce(_ message: String,
                                   line expectedLine: UInt,
                                   file: StaticString = #filePath,
                                   line: UInt = #line) {
        XCTAssertEqual(crashes.failures.map(\.message), [message], file: file, line: line)
        XCTAssertEqual(crashes.failures.first?.line, expectedLine, file: file, line: line)
        XCTAssertTrue(crashes.failures.first?.file.hasSuffix("SwiftMigrationHelpersTests.swift") ?? false,
                      "\(crashes.failures.first?.file ?? "no failure")", file: file, line: line)
    }

    func testBetaAssert() {
        let line: UInt = #line + 1
        it_betaAssert(false, "public beta assertion")
        assertCrashedOnce("public beta assertion", line: line)
    }

    func testConservativeBetaAssert() {
        let line: UInt = #line + 1
        it_conservativeBetaAssert(false, "public conservative assertion")
        assertCrashedOnce("public conservative assertion", line: line)
    }

    func testAddSigned() {
        let line: UInt = #line + 1
        let result = it_add(Int8.max, Int8(1))
        XCTAssertEqual(result, Int8.min)
        assertCrashedOnce("overflow in 127 + 1 (Int8)", line: line)
    }

    func testAddUnsigned() {
        let line: UInt = #line + 1
        let result = it_add(UInt32.max, UInt32(1))
        XCTAssertEqual(result, 0)
        assertCrashedOnce("overflow in 4294967295 + 1 (UInt32)", line: line)
    }

    func testSubtract() {
        let line: UInt = #line + 1
        let result = it_subtract(UInt8(0), UInt8(1))
        XCTAssertEqual(result, 255)
        assertCrashedOnce("overflow in 0 - 1 (UInt8)", line: line)
    }

    func testMultiply() {
        let line: UInt = #line + 1
        let result = it_multiply(Int16(300), Int16(300))
        XCTAssertEqual(result, 24464)
        assertCrashedOnce("overflow in 300 * 300 (Int16)", line: line)
    }

    func testNegate() {
        let line: UInt = #line + 1
        let result = it_negate(Int.min)
        XCTAssertEqual(result, Int.min)
        assertCrashedOnce("overflow in -(-9223372036854775808) (Int)", line: line)
    }

    func testShiftLeft() {
        let line: UInt = #line + 1
        let result = it_shiftLeft(Int8(64), 1)
        XCTAssertEqual(result, Int8.min)
        assertCrashedOnce("overflow in 64 << 1 (Int8)", line: line)
    }

    func testShiftLeftLosingEveryBitOfANarrowType() {
        // C shifts a uint8_t at int width, where a count of 9 is defined, and the store keeps the
        // low 8 bits.
        let line: UInt = #line + 1
        let result = it_shiftLeft(UInt8(1), 9)
        XCTAssertEqual(result, 0)
        assertCrashedOnce("overflow in 1 << 9 (UInt8)", line: line)
    }

    func testShiftLeftCountOutOfRange() {
        // 33 is at least the width of int, so C leaves it undefined; the hardware masks it to 1.
        let line: UInt = #line + 1
        let result = it_shiftLeft(UInt8(1), 33)
        XCTAssertEqual(result, 2)
        assertCrashedOnce("shift count out of range in 1 << 33 (UInt8)", line: line)
    }

    func testNarrow() {
        let line: UInt = #line + 1
        let result = it_narrow(70000, to: Int16.self)
        XCTAssertEqual(result, 4464)
        assertCrashedOnce("narrowing 70000 (Int) to Int16 is out of range", line: line)
    }

    func testFloatToInteger() {
        let line: UInt = #line + 1
        let result = it_floatToInteger(Double.nan, to: Int32.self)
        XCTAssertEqual(result, valueOnThisProcessor(arm64: 0, x86_64: Int32.min))
        assertCrashedOnce("converting nan (Double) to Int32 is out of range", line: line)
    }

    func testSynchronizedNilLock() {
        let nilLock: AnyObject? = nil
        var ran = false
        let line: UInt = #line + 1
        let value: Int = it_synchronized(nilLock) {
            ran = true
            return 11
        }
        XCTAssertTrue(ran)
        XCTAssertEqual(value, 11)
        assertCrashedOnce("nil lock passed to it_synchronized; running unprotected", line: line)
    }

    // The Deployment policy, set through the flag the public helpers read.

    func testDeploymentPolicyPublicHelpersLogWithoutCrashing() {
        iTermBetaAssertionsCrash = false
        it_betaAssert(false, "logged, not fatal")
        // The release policy gives the same results, the C results, and only logs.
        XCTAssertEqual(it_add(Int8.max, Int8(1)), Int8.min)
        XCTAssertEqual(it_shiftLeft(UInt32(1), 33), 2)
        XCTAssertEqual(it_narrow(-1, to: UInt16.self), UInt16.max)
        XCTAssertEqual(it_floatToInteger(-Double.infinity, to: Int32.self), Int32.min)
        let nilLock: AnyObject? = nil
        XCTAssertEqual(it_synchronized(nilLock) { 3 }, 3)
        XCTAssertTrue(crashes.failures.isEmpty, "\(crashes.failures.map(\.message))")
    }

    func testDeploymentPolicyConservativeAssertDoesNotEvaluate() {
        iTermBetaAssertionsCrash = false
        var conditionEvaluated = false
        var messageEvaluated = false
        it_conservativeBetaAssert({ conditionEvaluated = true; return false }(),
                                  { messageEvaluated = true; return "unused" }())
        XCTAssertFalse(conditionEvaluated)
        XCTAssertFalse(messageEvaluated)
        XCTAssertTrue(crashes.failures.isEmpty)
    }

    // The policy injected directly, with the crash hook as the crash function.

    func testInjectedPolicyNotFatalDoesNotCallHook() {
        iTermBetaAssertionFailed("not fatal", file: "File.swift", line: 3, function: "f()",
                                 fatal: false, crash: iTermBetaAssertions.crashHandler)
        XCTAssertTrue(crashes.failures.isEmpty)
    }

    func testInjectedPolicyFatalCallsHook() {
        iTermBetaAssertionFailed("fatal", file: "File.swift", line: 3, function: "f()",
                                 fatal: true, crash: iTermBetaAssertions.crashHandler)
        XCTAssertEqual(crashes.failures.map(\.message), ["fatal"])
        XCTAssertEqual(crashes.failures.first?.line, 3)
    }
}

// MARK: - Arithmetic

/// Every result below is what the C expression gives on arm64 and x86_64 (a C probe compiled with
/// clang at -O0 and -Os; see translation-rules.md section 1): add, subtract, multiply and negate
/// wrap, and a shift drops the bits shifted out with its count masked as the hardware masks it.
/// `fails` is whether the event is reported.
final class SwiftMigrationArithmeticTests: XCTestCase {
    private func addCases<T: FixedWidthInteger>(_: T.Type) {
        let t = "\(T.self)"
        check("\(t) 2 + 3", { it_add(T(2), T(3), onFailure: $0) }, T(5), fails: false)
        check("\(t) max + 0", { it_add(T.max, T(0), onFailure: $0) }, T.max, fails: false)
        check("\(t) (max - 1) + 1", { it_add(T.max - 1, T(1), onFailure: $0) }, T.max, fails: false)
        check("\(t) max + 1", { it_add(T.max, T(1), onFailure: $0) }, T.min, fails: true)
        check("\(t) 1 + max", { it_add(T(1), T.max, onFailure: $0) }, T.min, fails: true)
        check("\(t) max + max", { it_add(T.max, T.max, onFailure: $0) }, T(truncatingIfNeeded: -2), fails: true)
        check("\(t) min + 0", { it_add(T.min, T(0), onFailure: $0) }, T.min, fails: false)
        if T.isSigned {
            check("\(t) min + -1", { it_add(T.min, T(-1), onFailure: $0) }, T.max, fails: true)
            check("\(t) -1 + min", { it_add(T(-1), T.min, onFailure: $0) }, T.max, fails: true)
            check("\(t) (min + 1) + -1", { it_add(T.min + 1, T(-1), onFailure: $0) }, T.min, fails: false)
            check("\(t) min + min", { it_add(T.min, T.min, onFailure: $0) }, T(0), fails: true)
            check("\(t) max + min", { it_add(T.max, T.min, onFailure: $0) }, T(-1), fails: false)
            check("\(t) max + -1", { it_add(T.max, T(-1), onFailure: $0) }, T.max - 1, fails: false)
        }
    }

    private func subtractCases<T: FixedWidthInteger>(_: T.Type) {
        let t = "\(T.self)"
        check("\(t) 5 - 3", { it_subtract(T(5), T(3), onFailure: $0) }, T(2), fails: false)
        check("\(t) min - 0", { it_subtract(T.min, T(0), onFailure: $0) }, T.min, fails: false)
        check("\(t) (min + 1) - 1", { it_subtract(T.min + 1, T(1), onFailure: $0) }, T.min, fails: false)
        check("\(t) min - 1", { it_subtract(T.min, T(1), onFailure: $0) }, T.max, fails: true)
        check("\(t) min - max", { it_subtract(T.min, T.max, onFailure: $0) }, T(1), fails: true)
        check("\(t) max - max", { it_subtract(T.max, T.max, onFailure: $0) }, T(0), fails: false)
        check("\(t) max - 0", { it_subtract(T.max, T(0), onFailure: $0) }, T.max, fails: false)
        if T.isSigned {
            check("\(t) max - -1", { it_subtract(T.max, T(-1), onFailure: $0) }, T.min, fails: true)
            check("\(t) (max - 1) - -1", { it_subtract(T.max - 1, T(-1), onFailure: $0) }, T.max, fails: false)
            check("\(t) 0 - min", { it_subtract(T(0), T.min, onFailure: $0) }, T.min, fails: true)
            check("\(t) -1 - min", { it_subtract(T(-1), T.min, onFailure: $0) }, T.max, fails: false)
            check("\(t) max - min", { it_subtract(T.max, T.min, onFailure: $0) }, T(-1), fails: true)
            check("\(t) 0 - max", { it_subtract(T(0), T.max, onFailure: $0) }, T.min + 1, fails: false)
            check("\(t) -2 - max", { it_subtract(T(-2), T.max, onFailure: $0) }, T.max, fails: true)
        } else {
            // C wraps: 0u - 1 is the maximum.
            check("\(t) 0 - 1", { it_subtract(T(0), T(1), onFailure: $0) }, T.max, fails: true)
            check("\(t) 3 - 5", { it_subtract(T(3), T(5), onFailure: $0) }, T.max - 1, fails: true)
        }
    }

    private func multiplyCases<T: FixedWidthInteger>(_: T.Type) {
        let t = "\(T.self)"
        let half = T.max / 2
        check("\(t) 6 * 7", { it_multiply(T(6), T(7), onFailure: $0) }, T(42), fails: false)
        check("\(t) max * 0", { it_multiply(T.max, T(0), onFailure: $0) }, T(0), fails: false)
        check("\(t) max * 1", { it_multiply(T.max, T(1), onFailure: $0) }, T.max, fails: false)
        check("\(t) half * 2", { it_multiply(half, T(2), onFailure: $0) }, T.max - 1, fails: false)
        // (half + 1) * 2 is 2^(bitWidth - 1) for signed types and 2^bitWidth for unsigned ones.
        check("\(t) (half + 1) * 2", { it_multiply(half + 1, T(2), onFailure: $0) }, T.min, fails: true)
        check("\(t) max * 2", { it_multiply(T.max, T(2), onFailure: $0) }, T(truncatingIfNeeded: -2), fails: true)
        check("\(t) max * max", { it_multiply(T.max, T.max, onFailure: $0) }, T(1), fails: true)
        check("\(t) min * 1", { it_multiply(T.min, T(1), onFailure: $0) }, T.min, fails: false)
        if T.isSigned {
            check("\(t) min * -1", { it_multiply(T.min, T(-1), onFailure: $0) }, T.min, fails: true)
            check("\(t) -1 * min", { it_multiply(T(-1), T.min, onFailure: $0) }, T.min, fails: true)
            check("\(t) max * -1", { it_multiply(T.max, T(-1), onFailure: $0) }, T.min + 1, fails: false)
            check("\(t) min * 2", { it_multiply(T.min, T(2), onFailure: $0) }, T(0), fails: true)
            check("\(t) max * -2", { it_multiply(T.max, T(-2), onFailure: $0) }, T(2), fails: true)
            check("\(t) -2 * max", { it_multiply(T(-2), T.max, onFailure: $0) }, T(2), fails: true)
            check("\(t) min * min", { it_multiply(T.min, T.min, onFailure: $0) }, T(0), fails: true)
            check("\(t) min * max", { it_multiply(T.min, T.max, onFailure: $0) }, T.min, fails: true)
            check("\(t) (min / 2) * 2", { it_multiply(T.min / 2, T(2), onFailure: $0) }, T.min, fails: false)
            check("\(t) -3 * -4", { it_multiply(T(-3), T(-4), onFailure: $0) }, T(12), fails: false)
        }
    }

    private func negateCases<T: FixedWidthInteger & SignedInteger>(_: T.Type) {
        let t = "\(T.self)"
        check("\(t) -0", { it_negate(T(0), onFailure: $0) }, T(0), fails: false)
        check("\(t) -5", { it_negate(T(5), onFailure: $0) }, T(-5), fails: false)
        check("\(t) -max", { it_negate(T.max, onFailure: $0) }, T.min + 1, fails: false)
        check("\(t) -(min + 1)", { it_negate(T.min + 1, onFailure: $0) }, T.max, fails: false)
        check("\(t) -min", { it_negate(T.min, onFailure: $0) }, T.min, fails: true)
    }

    private func shiftCases<T: FixedWidthInteger>(_: T.Type) {
        let t = "\(T.self)"
        let w = T.bitWidth
        // C shifts 8 and 16 bit values at the width of int.
        let narrow = w < 32
        check("\(t) 1 << 0", { it_shiftLeft(T(1), 0, onFailure: $0) }, T(1), fails: false)
        check("\(t) 3 << 2", { it_shiftLeft(T(3), 2, onFailure: $0) }, T(12), fails: false)
        check("\(t) 0 << (w - 1)", { it_shiftLeft(T(0), w - 1, onFailure: $0) }, T(0), fails: false)
        check("\(t) 1 << (w - 2)", { it_shiftLeft(T(1), w - 2, onFailure: $0) }, T(1) << (w - 2), fails: false)
        check("\(t) max << 1", { it_shiftLeft(T.max, 1, onFailure: $0) }, T(truncatingIfNeeded: -2), fails: true)
        // A count of w is defined in C for the narrow types, and the store keeps no bit. For the
        // others it is undefined, and the hardware masks it to 0.
        check("\(t) 1 << w", { it_shiftLeft(T(1), w, onFailure: $0) }, narrow ? T(0) : T(1), fails: true)
        check("\(t) 1 << (w + 7)", { it_shiftLeft(T(1), w + 7, onFailure: $0) }, narrow ? T(0) : T(128), fails: true)
        check("\(t) 0 << w", { it_shiftLeft(T(0), w, onFailure: $0) }, T(0), fails: !narrow)
        check("\(t) 1 << 31", { it_shiftLeft(T(1), 31, onFailure: $0) }, narrow ? T(0) : T(1) << 31,
              fails: narrow || (w == 32 && T.isSigned))
        // 33 is at least the width of int, so it is undefined unless T is 64 bits wide.
        check("\(t) 1 << 33", { it_shiftLeft(T(1), 33, onFailure: $0) }, w == 64 ? T(1) << 33 : T(2), fails: w != 64)
        // A negative count is undefined in C. The hardware uses its low bits: 5 of them for a
        // shift at int width, 6 for a 64 bit shift.
        check("\(t) 8 << -2", { it_shiftLeft(T(8), -2, onFailure: $0) }, T(0), fails: true)
        check("\(t) 1 << -31", { it_shiftLeft(T(1), -31, onFailure: $0) }, w == 64 ? T(1) << 33 : T(2), fails: true)
        check("\(t) 8 << Int.min", { it_shiftLeft(T(8), Int.min, onFailure: $0) }, T(8), fails: true)
        // The count may be any integer type, and is masked by the width of the shifted value.
        check("\(t) 1 << UInt8(3)", { it_shiftLeft(T(1), UInt8(3), onFailure: $0) }, T(8), fails: false)
        check("\(t) 1 << UInt64(100)", { it_shiftLeft(T(1), UInt64(100), onFailure: $0) },
              w == 64 ? T(1) << 36 : (narrow ? T(truncatingIfNeeded: 16) : T(16)), fails: true)
        if T.isSigned {
            check("\(t) 1 << (w - 1)", { it_shiftLeft(T(1), w - 1, onFailure: $0) }, T.min, fails: true)
            check("\(t) -1 << (w - 1)", { it_shiftLeft(T(-1), w - 1, onFailure: $0) }, T.min, fails: false)
            check("\(t) -3 << 2", { it_shiftLeft(T(-3), 2, onFailure: $0) }, T(-12), fails: false)
            check("\(t) min << 1", { it_shiftLeft(T.min, 1, onFailure: $0) }, T(0), fails: true)
            check("\(t) -1 << w", { it_shiftLeft(T(-1), w, onFailure: $0) }, narrow ? T(0) : T(-1), fails: true)
            check("\(t) (max / 2 + 1) << 1", { it_shiftLeft(T.max / 2 + 1, 1, onFailure: $0) }, T.min, fails: true)
            check("\(t) -8 << -2", { it_shiftLeft(T(-8), -2, onFailure: $0) }, T(0), fails: true)
            check("\(t) -8 << Int.min", { it_shiftLeft(T(-8), Int.min, onFailure: $0) }, T(-8), fails: true)
            check("\(t) -1 << -31", { it_shiftLeft(T(-1), -31, onFailure: $0) },
                  w == 64 ? T(-1) << 33 : T(-2), fails: true)
        } else {
            check("\(t) 1 << (w - 1)", { it_shiftLeft(T(1), w - 1, onFailure: $0) }, T(1) << (w - 1), fails: false)
            check("\(t) (max / 2 + 1) << 1", { it_shiftLeft(T.max / 2 + 1, 1, onFailure: $0) }, T(0), fails: true)
        }
    }

    private func allCases<T: FixedWidthInteger>(_ type: T.Type) {
        addCases(type)
        subtractCases(type)
        multiplyCases(type)
        shiftCases(type)
    }

    func testInt() { allCases(Int.self); negateCases(Int.self) }
    func testInt8() { allCases(Int8.self); negateCases(Int8.self) }
    func testInt16() { allCases(Int16.self); negateCases(Int16.self) }
    func testInt32() { allCases(Int32.self); negateCases(Int32.self) }
    func testInt64() { allCases(Int64.self); negateCases(Int64.self) }
    func testUInt() { allCases(UInt.self) }
    func testUInt8() { allCases(UInt8.self) }
    func testUInt16() { allCases(UInt16.self) }
    func testUInt32() { allCases(UInt32.self) }
    func testUInt64() { allCases(UInt64.self) }

    /// Values observed from the C probe, one per helper and type family.
    func testValuesObservedFromC() {
        check("int32 INT32_MAX + 1", { it_add(Int32.max, 1, onFailure: $0) }, Int32(-2147483648), fails: true)
        check("int64 INT64_MAX + 1", { it_add(Int64.max, 1, onFailure: $0) }, Int64.min, fails: true)
        check("uint8 255 + 1", { it_add(UInt8(255), 1, onFailure: $0) }, UInt8(0), fails: true)
        check("int8 127 + 1", { it_add(Int8(127), 1, onFailure: $0) }, Int8(-128), fails: true)
        check("uint32 0 - 1", { it_subtract(UInt32(0), 1, onFailure: $0) }, UInt32(4294967295), fails: true)
        check("int16 300 * 300", { it_multiply(Int16(300), 300, onFailure: $0) }, Int16(24464), fails: true)
        check("uint16 65535 * 65535", { it_multiply(UInt16(65535), 65535, onFailure: $0) }, UInt16(1), fails: true)
        check("int32 46341 * 46341", { it_multiply(Int32(46341), 46341, onFailure: $0) }, Int32(-2147479015), fails: true)
        check("int64 INT64_MAX * 2", { it_multiply(Int64.max, 2, onFailure: $0) }, Int64(-2), fails: true)
        check("int8 -(-128)", { it_negate(Int8(-128), onFailure: $0) }, Int8(-128), fails: true)
        check("uint8 1 << 39", { it_shiftLeft(UInt8(1), 39, onFailure: $0) }, UInt8(128), fails: true)
        check("int16 65 << 9", { it_shiftLeft(Int16(65), 9, onFailure: $0) }, Int16(-32256), fails: true)
        check("uint16 65 << 100", { it_shiftLeft(UInt16(65), 100, onFailure: $0) }, UInt16(1040), fails: true)
        check("int32 -1 << -2", { it_shiftLeft(Int32(-1), -2, onFailure: $0) }, Int32(-1073741824), fails: true)
        check("uint32 65 << 63", { it_shiftLeft(UInt32(65), 63, onFailure: $0) }, UInt32(2147483648), fails: true)
        check("int64 1 << 64", { it_shiftLeft(Int64(1), 64, onFailure: $0) }, Int64(1), fails: true)
        check("int64 -1 << -33", { it_shiftLeft(Int64(-1), -33, onFailure: $0) }, Int64(-2147483648), fails: true)
        check("uint64 65 << 65", { it_shiftLeft(UInt64(65), 65, onFailure: $0) }, UInt64(130), fails: true)
    }

    func testOverflowMessageNamesOperationAndOperands() {
        let recorder = FailureRecorder()
        _ = it_add(Int8(127), Int8(1), onFailure: recorder.handler)
        _ = it_subtract(UInt8(0), UInt8(1), onFailure: recorder.handler)
        _ = it_multiply(Int16(300), Int16(300), onFailure: recorder.handler)
        _ = it_negate(Int32.min, onFailure: recorder.handler)
        _ = it_shiftLeft(Int8(64), 1, onFailure: recorder.handler)
        _ = it_shiftLeft(Int8(1), 9, onFailure: recorder.handler)
        _ = it_shiftLeft(Int8(1), 33, onFailure: recorder.handler)
        XCTAssertEqual(recorder.failures.map(\.message), [
            "overflow in 127 + 1 (Int8)",
            "overflow in 0 - 1 (UInt8)",
            "overflow in 300 * 300 (Int16)",
            "overflow in -(-2147483648) (Int32)",
            "overflow in 64 << 1 (Int8)",
            "overflow in 1 << 9 (Int8)",
            "shift count out of range in 1 << 33 (Int8)",
        ])
    }

    func testFailureCarriesCallerLocation() {
        let recorder = FailureRecorder()
        let expectedLine: UInt = #line + 1
        _ = it_add(Int8.max, 1, onFailure: recorder.handler)
        XCTAssertEqual(recorder.failures.first?.line, expectedLine)
        XCTAssertEqual(recorder.failures.first?.function, "testFailureCarriesCallerLocation()")
    }

    func testPublicHelpersWithoutOverflow() {
        // The public entry points must give the plain result when nothing overflows.
        XCTAssertEqual(it_add(Int32(2), Int32(3)), 5)
        XCTAssertEqual(it_subtract(UInt(10), UInt(4)), 6)
        XCTAssertEqual(it_multiply(Int64(-6), Int64(7)), -42)
        XCTAssertEqual(it_negate(Int16(9)), -9)
        XCTAssertEqual(it_shiftLeft(UInt8(3), 4), 48)
        XCTAssertEqual(it_narrow(300, to: Int16.self), 300)
        XCTAssertEqual(it_floatToInteger(-2.75, to: Int32.self), -2)
    }
}

// MARK: - Narrowing

/// A C conversion between integer types keeps the low bits of the two's complement value, and
/// sign-extends or zero-extends into a wider type.
final class SwiftMigrationNarrowingTests: XCTestCase {
    /// In range at both ends, one past each end, and far past each end.
    private func boundaryCases<S: FixedWidthInteger, T: FixedWidthInteger>(from: S.Type, to: T.Type) {
        let d = "\(S.self) -> \(T.self)"
        check("\(d) 0", { it_narrow(S(0), to: T.self, onFailure: $0) }, T(0), fails: false)
        check("\(d) S.max", { it_narrow(S.max, to: T.self, onFailure: $0) },
              T(truncatingIfNeeded: S.max), fails: T(exactly: S.max) == nil)
        check("\(d) S.min", { it_narrow(S.min, to: T.self, onFailure: $0) },
              T(truncatingIfNeeded: S.min), fails: T(exactly: S.min) == nil)
        if let tMax = S(exactly: T.max) {
            check("\(d) T.max", { it_narrow(tMax, to: T.self, onFailure: $0) }, T.max, fails: false)
            if tMax < S.max {
                // T.max + 1 keeps the low bits of 2^(bits of T), or of 2^(bits of T - 1) for a
                // signed T: T.min either way.
                check("\(d) T.max + 1", { it_narrow(tMax + 1, to: T.self, onFailure: $0) }, T.min, fails: true)
            }
        }
        if let tMin = S(exactly: T.min) {
            check("\(d) T.min", { it_narrow(tMin, to: T.self, onFailure: $0) }, T.min, fails: false)
            if tMin > S.min {
                check("\(d) T.min - 1", { it_narrow(tMin - 1, to: T.self, onFailure: $0) }, T.max, fails: true)
            }
        }
        if S.isSigned {
            // -1 is all ones in every width.
            check("\(d) -1", { it_narrow(S(-1), to: T.self, onFailure: $0) },
                  T.isSigned ? T(-1) : T.max, fails: !T.isSigned)
        }
    }

    func testIntToNarrowerSigned() {
        boundaryCases(from: Int.self, to: Int32.self)
        boundaryCases(from: Int.self, to: Int16.self)
        boundaryCases(from: Int.self, to: Int8.self)
        boundaryCases(from: Int64.self, to: Int32.self)
        boundaryCases(from: Int32.self, to: Int16.self)
        boundaryCases(from: Int16.self, to: Int8.self)
    }

    func testSignedToUnsigned() {
        boundaryCases(from: Int.self, to: UInt8.self)
        boundaryCases(from: Int.self, to: UInt16.self)
        boundaryCases(from: Int.self, to: UInt32.self)
        boundaryCases(from: Int.self, to: UInt.self)
        boundaryCases(from: Int64.self, to: UInt64.self)
        boundaryCases(from: Int32.self, to: UInt32.self)
        boundaryCases(from: Int32.self, to: UInt8.self)
    }

    func testUnsignedToSigned() {
        boundaryCases(from: UInt.self, to: Int.self)
        boundaryCases(from: UInt64.self, to: Int64.self)
        boundaryCases(from: UInt32.self, to: Int32.self)
        boundaryCases(from: UInt32.self, to: Int16.self)
        boundaryCases(from: UInt16.self, to: Int8.self)
    }

    func testUnsignedToNarrowerUnsigned() {
        boundaryCases(from: UInt.self, to: UInt32.self)
        boundaryCases(from: UInt64.self, to: UInt16.self)
        boundaryCases(from: UInt32.self, to: UInt8.self)
    }

    func testWideningNeverFails() {
        boundaryCases(from: Int32.self, to: Int.self)
        boundaryCases(from: UInt8.self, to: Int16.self)
        boundaryCases(from: UInt32.self, to: UInt64.self)
    }

    func testWideningSignedToUnsignedSignExtends() {
        // (uint64_t)(int8_t)-1 is UINT64_MAX in C: the value is sign-extended, then reinterpreted.
        check("Int8 -1 -> UInt64", { it_narrow(Int8(-1), to: UInt64.self, onFailure: $0) }, UInt64.max, fails: true)
        check("Int8 -112 -> UInt64", { it_narrow(Int8(-112), to: UInt64.self, onFailure: $0) },
              UInt64(18446744073709551504), fails: true)
    }

    /// Values observed from the C probe.
    func testSpecificValues() {
        check("Int 70000 -> Int16", { it_narrow(70000, to: Int16.self, onFailure: $0) }, Int16(4464), fails: true)
        check("Int -70000 -> Int16", { it_narrow(-70000, to: Int16.self, onFailure: $0) }, Int16(-4464), fails: true)
        check("Int -70000 -> UInt8", { it_narrow(-70000, to: UInt8.self, onFailure: $0) }, UInt8(144), fails: true)
        check("Int -70000 -> UInt32", { it_narrow(-70000, to: UInt32.self, onFailure: $0) },
              UInt32(4294897296), fails: true)
        check("Int 300 -> Int8", { it_narrow(300, to: Int8.self, onFailure: $0) }, Int8(44), fails: true)
        check("Int 128 -> Int8", { it_narrow(128, to: Int8.self, onFailure: $0) }, Int8(-128), fails: true)
        check("Int 2147483648 -> Int32", { it_narrow(2147483648, to: Int32.self, onFailure: $0) },
              Int32.min, fails: true)
        check("UInt32 2147483648 -> Int32", { it_narrow(UInt32(2147483648), to: Int32.self, onFailure: $0) },
              Int32.min, fails: true)
        check("Int 32767 -> Int16", { it_narrow(32767, to: Int16.self, onFailure: $0) }, Int16(32767), fails: false)
        check("Int -32768 -> Int16", { it_narrow(-32768, to: Int16.self, onFailure: $0) }, Int16(-32768), fails: false)
        // NSNotFound stored in an int is -1 (integer-findings.md section 4.8).
        check("NSNotFound -> Int32", { it_narrow(NSNotFound, to: Int32.self, onFailure: $0) }, Int32(-1), fails: true)
    }

    func testMessage() {
        let recorder = FailureRecorder()
        _ = it_narrow(Int(-1), to: UInt32.self, onFailure: recorder.handler)
        XCTAssertEqual(recorder.failures.map(\.message), ["narrowing -1 (Int) to UInt32 is out of range"])
    }
}

// MARK: - Float to integer

/// One value converted to every integer type, with the C results on each processor in the order
/// Int8, UInt8, Int16, UInt16, Int32, UInt32, Int64, UInt64.
///
/// The arm64 columns are the output of a C probe compiled with clang at -Os (as Deployment builds
/// the C) and run on Apple silicon: each conversion in a function of its own whose result is
/// stored in a variable of the target type. The x86_64 columns come from the instructions clang
/// emits for the same probe with -arch x86_64 at -O0 and -Os (identical), evaluated with the
/// Intel SDM's definition of cvttsd2si and cvttss2si; Rosetta was not available to run them.
private struct FloatConversionRow {
    let value: Double
    let arm64: [String]
    let x86_64: [String]

    init(_ value: Double, arm64: [String], x86_64: [String]) {
        self.value = value
        self.arm64 = arm64
        self.x86_64 = x86_64
    }

    var onThisProcessor: [String] {
        return valueOnThisProcessor(arm64: arm64, x86_64: x86_64)
    }
}

// Double values, which CGFloat shares (CGFLOAT_IS_DOUBLE is 1 and the probe's CGFloat rows were
// identical to its Double rows).
private let doubleConversionRows: [FloatConversionRow] = [
        .init(.nan, arm64: ["0", "0", "0", "0", "0", "0", "0", "0"], x86_64: ["0", "0", "0", "0", "-2147483648", "0", "-9223372036854775808", "9223372036854775808"]),
        .init(.infinity, arm64: ["-1", "255", "-1", "65535", "2147483647", "4294967295", "9223372036854775807", "18446744073709551615"], x86_64: ["0", "0", "0", "0", "-2147483648", "0", "-9223372036854775808", "9223372036854775808"]),
        .init(-.infinity, arm64: ["0", "0", "0", "0", "-2147483648", "0", "-9223372036854775808", "0"], x86_64: ["0", "0", "0", "0", "-2147483648", "0", "-9223372036854775808", "9223372036854775808"]),
        .init(1e+300, arm64: ["-1", "255", "-1", "65535", "2147483647", "4294967295", "9223372036854775807", "18446744073709551615"], x86_64: ["0", "0", "0", "0", "-2147483648", "0", "-9223372036854775808", "9223372036854775808"]),
        .init(-1e+300, arm64: ["0", "0", "0", "0", "-2147483648", "0", "-9223372036854775808", "0"], x86_64: ["0", "0", "0", "0", "-2147483648", "0", "-9223372036854775808", "9223372036854775808"]),
        .init(2.75, arm64: ["2", "2", "2", "2", "2", "2", "2", "2"], x86_64: ["2", "2", "2", "2", "2", "2", "2", "2"]),
        .init(-2.75, arm64: ["-2", "254", "-2", "65534", "-2", "0", "-2", "0"], x86_64: ["-2", "254", "-2", "65534", "-2", "4294967294", "-2", "18446744073709551614"]),
        .init(-0.5, arm64: ["0", "0", "0", "0", "0", "0", "0", "0"], x86_64: ["0", "0", "0", "0", "0", "0", "0", "0"]),
        .init(-1.0, arm64: ["-1", "255", "-1", "65535", "-1", "0", "-1", "0"], x86_64: ["-1", "255", "-1", "65535", "-1", "4294967295", "-1", "18446744073709551615"]),
        .init(127.9, arm64: ["127", "127", "127", "127", "127", "127", "127", "127"], x86_64: ["127", "127", "127", "127", "127", "127", "127", "127"]),
        .init(128.0, arm64: ["-128", "128", "128", "128", "128", "128", "128", "128"], x86_64: ["-128", "128", "128", "128", "128", "128", "128", "128"]),
        .init(-129.0, arm64: ["127", "127", "-129", "65407", "-129", "0", "-129", "0"], x86_64: ["127", "127", "-129", "65407", "-129", "4294967167", "-129", "18446744073709551487"]),
        .init(255.9, arm64: ["-1", "255", "255", "255", "255", "255", "255", "255"], x86_64: ["-1", "255", "255", "255", "255", "255", "255", "255"]),
        .init(256.0, arm64: ["0", "0", "256", "256", "256", "256", "256", "256"], x86_64: ["0", "0", "256", "256", "256", "256", "256", "256"]),
        .init(300.0, arm64: ["44", "44", "300", "300", "300", "300", "300", "300"], x86_64: ["44", "44", "300", "300", "300", "300", "300", "300"]),
        .init(-300.0, arm64: ["-44", "212", "-300", "65236", "-300", "0", "-300", "0"], x86_64: ["-44", "212", "-300", "65236", "-300", "4294966996", "-300", "18446744073709551316"]),
        .init(32768.0, arm64: ["0", "0", "-32768", "32768", "32768", "32768", "32768", "32768"], x86_64: ["0", "0", "-32768", "32768", "32768", "32768", "32768", "32768"]),
        .init(65535.5, arm64: ["-1", "255", "-1", "65535", "65535", "65535", "65535", "65535"], x86_64: ["-1", "255", "-1", "65535", "65535", "65535", "65535", "65535"]),
        .init(65536.0, arm64: ["0", "0", "0", "0", "65536", "65536", "65536", "65536"], x86_64: ["0", "0", "0", "0", "65536", "65536", "65536", "65536"]),
        .init(70000.0, arm64: ["112", "112", "4464", "4464", "70000", "70000", "70000", "70000"], x86_64: ["112", "112", "4464", "4464", "70000", "70000", "70000", "70000"]),
        .init(-70000.0, arm64: ["-112", "144", "-4464", "61072", "-70000", "0", "-70000", "0"], x86_64: ["-112", "144", "-4464", "61072", "-70000", "4294897296", "-70000", "18446744073709481616"]),
        .init(2147483647.9, arm64: ["-1", "255", "-1", "65535", "2147483647", "2147483647", "2147483647", "2147483647"], x86_64: ["-1", "255", "-1", "65535", "2147483647", "2147483647", "2147483647", "2147483647"]),
        .init(2147483648.0, arm64: ["-1", "255", "-1", "65535", "2147483647", "2147483648", "2147483648", "2147483648"], x86_64: ["0", "0", "0", "0", "-2147483648", "2147483648", "2147483648", "2147483648"]),
        .init(-2147483648.9, arm64: ["0", "0", "0", "0", "-2147483648", "0", "-2147483648", "0"], x86_64: ["0", "0", "0", "0", "-2147483648", "2147483648", "-2147483648", "18446744071562067968"]),
        .init(-2147483649.0, arm64: ["0", "0", "0", "0", "-2147483648", "0", "-2147483649", "0"], x86_64: ["0", "0", "0", "0", "-2147483648", "2147483647", "-2147483649", "18446744071562067967"]),
        .init(4294967295.5, arm64: ["-1", "255", "-1", "65535", "2147483647", "4294967295", "4294967295", "4294967295"], x86_64: ["0", "0", "0", "0", "-2147483648", "4294967295", "4294967295", "4294967295"]),
        .init(4294967296.0, arm64: ["-1", "255", "-1", "65535", "2147483647", "4294967295", "4294967296", "4294967296"], x86_64: ["0", "0", "0", "0", "-2147483648", "0", "4294967296", "4294967296"]),
        .init(4294967303.0, arm64: ["-1", "255", "-1", "65535", "2147483647", "4294967295", "4294967303", "4294967303"], x86_64: ["0", "0", "0", "0", "-2147483648", "7", "4294967303", "4294967303"]),
        .init(-4294967303.0, arm64: ["0", "0", "0", "0", "-2147483648", "0", "-4294967303", "0"], x86_64: ["0", "0", "0", "0", "-2147483648", "4294967289", "-4294967303", "18446744069414584313"]),
        .init(10000000000.0, arm64: ["-1", "255", "-1", "65535", "2147483647", "4294967295", "10000000000", "10000000000"], x86_64: ["0", "0", "0", "0", "-2147483648", "1410065408", "10000000000", "10000000000"]),
        .init(-5000000000.0, arm64: ["0", "0", "0", "0", "-2147483648", "0", "-5000000000", "0"], x86_64: ["0", "0", "0", "0", "-2147483648", "3589934592", "-5000000000", "18446744068709551616"]),
        .init(9.223372036854776e+18, arm64: ["-1", "255", "-1", "65535", "2147483647", "4294967295", "9223372036854775807", "9223372036854775808"], x86_64: ["0", "0", "0", "0", "-2147483648", "0", "-9223372036854775808", "9223372036854775808"]),
        .init(-9.223372036854776e+18, arm64: ["0", "0", "0", "0", "-2147483648", "0", "-9223372036854775808", "0"], x86_64: ["0", "0", "0", "0", "-2147483648", "0", "-9223372036854775808", "9223372036854775808"]),
        .init(-9.223372036854778e+18, arm64: ["0", "0", "0", "0", "-2147483648", "0", "-9223372036854775808", "0"], x86_64: ["0", "0", "0", "0", "-2147483648", "0", "-9223372036854775808", "9223372036854775808"]),
        .init(1.3835058055282164e+19, arm64: ["-1", "255", "-1", "65535", "2147483647", "4294967295", "9223372036854775807", "13835058055282163712"], x86_64: ["0", "0", "0", "0", "-2147483648", "0", "-9223372036854775808", "13835058055282163712"]),
        .init(1.8446744073709552e+19, arm64: ["-1", "255", "-1", "65535", "2147483647", "4294967295", "9223372036854775807", "18446744073709551615"], x86_64: ["0", "0", "0", "0", "-2147483648", "0", "-9223372036854775808", "9223372036854775808"]),
        .init(1.844674407370955e+19, arm64: ["-1", "255", "-1", "65535", "2147483647", "4294967295", "9223372036854775807", "18446744073709549568"], x86_64: ["0", "0", "0", "0", "-2147483648", "0", "-9223372036854775808", "18446744073709549568"]),
]

// Float values: the probe's Double values rounded to Float, without duplicates.
private let floatConversionRows: [FloatConversionRow] = [
        .init(.nan, arm64: ["0", "0", "0", "0", "0", "0", "0", "0"], x86_64: ["0", "0", "0", "0", "-2147483648", "0", "-9223372036854775808", "9223372036854775808"]),
        .init(.infinity, arm64: ["-1", "255", "-1", "65535", "2147483647", "4294967295", "9223372036854775807", "18446744073709551615"], x86_64: ["0", "0", "0", "0", "-2147483648", "0", "-9223372036854775808", "9223372036854775808"]),
        .init(-.infinity, arm64: ["0", "0", "0", "0", "-2147483648", "0", "-9223372036854775808", "0"], x86_64: ["0", "0", "0", "0", "-2147483648", "0", "-9223372036854775808", "9223372036854775808"]),
        .init(2.75, arm64: ["2", "2", "2", "2", "2", "2", "2", "2"], x86_64: ["2", "2", "2", "2", "2", "2", "2", "2"]),
        .init(-2.75, arm64: ["-2", "254", "-2", "65534", "-2", "0", "-2", "0"], x86_64: ["-2", "254", "-2", "65534", "-2", "4294967294", "-2", "18446744073709551614"]),
        .init(-0.5, arm64: ["0", "0", "0", "0", "0", "0", "0", "0"], x86_64: ["0", "0", "0", "0", "0", "0", "0", "0"]),
        .init(-1.0, arm64: ["-1", "255", "-1", "65535", "-1", "0", "-1", "0"], x86_64: ["-1", "255", "-1", "65535", "-1", "4294967295", "-1", "18446744073709551615"]),
        .init(127.9000015258789, arm64: ["127", "127", "127", "127", "127", "127", "127", "127"], x86_64: ["127", "127", "127", "127", "127", "127", "127", "127"]),
        .init(128.0, arm64: ["-128", "128", "128", "128", "128", "128", "128", "128"], x86_64: ["-128", "128", "128", "128", "128", "128", "128", "128"]),
        .init(-129.0, arm64: ["127", "127", "-129", "65407", "-129", "0", "-129", "0"], x86_64: ["127", "127", "-129", "65407", "-129", "4294967167", "-129", "18446744073709551487"]),
        .init(255.89999389648438, arm64: ["-1", "255", "255", "255", "255", "255", "255", "255"], x86_64: ["-1", "255", "255", "255", "255", "255", "255", "255"]),
        .init(256.0, arm64: ["0", "0", "256", "256", "256", "256", "256", "256"], x86_64: ["0", "0", "256", "256", "256", "256", "256", "256"]),
        .init(300.0, arm64: ["44", "44", "300", "300", "300", "300", "300", "300"], x86_64: ["44", "44", "300", "300", "300", "300", "300", "300"]),
        .init(-300.0, arm64: ["-44", "212", "-300", "65236", "-300", "0", "-300", "0"], x86_64: ["-44", "212", "-300", "65236", "-300", "4294966996", "-300", "18446744073709551316"]),
        .init(32768.0, arm64: ["0", "0", "-32768", "32768", "32768", "32768", "32768", "32768"], x86_64: ["0", "0", "-32768", "32768", "32768", "32768", "32768", "32768"]),
        .init(65535.5, arm64: ["-1", "255", "-1", "65535", "65535", "65535", "65535", "65535"], x86_64: ["-1", "255", "-1", "65535", "65535", "65535", "65535", "65535"]),
        .init(65536.0, arm64: ["0", "0", "0", "0", "65536", "65536", "65536", "65536"], x86_64: ["0", "0", "0", "0", "65536", "65536", "65536", "65536"]),
        .init(70000.0, arm64: ["112", "112", "4464", "4464", "70000", "70000", "70000", "70000"], x86_64: ["112", "112", "4464", "4464", "70000", "70000", "70000", "70000"]),
        .init(-70000.0, arm64: ["-112", "144", "-4464", "61072", "-70000", "0", "-70000", "0"], x86_64: ["-112", "144", "-4464", "61072", "-70000", "4294897296", "-70000", "18446744073709481616"]),
        .init(2147483648.0, arm64: ["-1", "255", "-1", "65535", "2147483647", "2147483648", "2147483648", "2147483648"], x86_64: ["0", "0", "0", "0", "-2147483648", "2147483648", "2147483648", "2147483648"]),
        .init(-2147483648.0, arm64: ["0", "0", "0", "0", "-2147483648", "0", "-2147483648", "0"], x86_64: ["0", "0", "0", "0", "-2147483648", "2147483648", "-2147483648", "18446744071562067968"]),
        .init(4294967296.0, arm64: ["-1", "255", "-1", "65535", "2147483647", "4294967295", "4294967296", "4294967296"], x86_64: ["0", "0", "0", "0", "-2147483648", "0", "4294967296", "4294967296"]),
        .init(-4294967296.0, arm64: ["0", "0", "0", "0", "-2147483648", "0", "-4294967296", "0"], x86_64: ["0", "0", "0", "0", "-2147483648", "0", "-4294967296", "18446744069414584320"]),
        .init(10000000000.0, arm64: ["-1", "255", "-1", "65535", "2147483647", "4294967295", "10000000000", "10000000000"], x86_64: ["0", "0", "0", "0", "-2147483648", "1410065408", "10000000000", "10000000000"]),
        .init(-5000000000.0, arm64: ["0", "0", "0", "0", "-2147483648", "0", "-5000000000", "0"], x86_64: ["0", "0", "0", "0", "-2147483648", "3589934592", "-5000000000", "18446744068709551616"]),
        .init(9.223372036854776e+18, arm64: ["-1", "255", "-1", "65535", "2147483647", "4294967295", "9223372036854775807", "9223372036854775808"], x86_64: ["0", "0", "0", "0", "-2147483648", "0", "-9223372036854775808", "9223372036854775808"]),
        .init(-9.223372036854776e+18, arm64: ["0", "0", "0", "0", "-2147483648", "0", "-9223372036854775808", "0"], x86_64: ["0", "0", "0", "0", "-2147483648", "0", "-9223372036854775808", "9223372036854775808"]),
        .init(1.3835058055282164e+19, arm64: ["-1", "255", "-1", "65535", "2147483647", "4294967295", "9223372036854775807", "13835058055282163712"], x86_64: ["0", "0", "0", "0", "-2147483648", "0", "-9223372036854775808", "13835058055282163712"]),
        .init(1.8446744073709552e+19, arm64: ["-1", "255", "-1", "65535", "2147483647", "4294967295", "9223372036854775807", "18446744073709551615"], x86_64: ["0", "0", "0", "0", "-2147483648", "0", "-9223372036854775808", "9223372036854775808"]),
]

final class SwiftMigrationFloatConversionTests: XCTestCase {
    private func checkRow<F: BinaryFloatingPoint>(_ value: F,
                                                  _ expected: [String],
                                                  file: StaticString = #filePath,
                                                  line: UInt = #line) {
        func one<T: FixedWidthInteger>(_ index: Int, _ type: T.Type) {
            let recorder = FailureRecorder()
            let actual = it_floatToInteger(value, to: T.self, onFailure: recorder.handler)
            XCTAssertEqual("\(actual)", expected[index], "\(value) (\(F.self)) -> \(T.self)", file: file, line: line)
            // A failure is reported exactly when the value rounded toward zero is not a value of T.
            let truncated = value.rounded(.towardZero)
            let fits = truncated.isFinite && T(exactly: truncated) != nil
            XCTAssertEqual(recorder.failures.count, fits ? 0 : 1,
                           "\(value) (\(F.self)) -> \(T.self): \(recorder.failures.map(\.message))",
                           file: file, line: line)
        }
        one(0, Int8.self)
        one(1, UInt8.self)
        one(2, Int16.self)
        one(3, UInt16.self)
        one(4, Int32.self)
        one(5, UInt32.self)
        one(6, Int64.self)
        one(7, UInt64.self)
    }

    func testDoubleMatchesC() {
        for row in doubleConversionRows {
            checkRow(row.value, row.onThisProcessor)
        }
    }

    func testCGFloatMatchesC() {
        for row in doubleConversionRows {
            checkRow(CGFloat(row.value), row.onThisProcessor)
        }
    }

    func testFloatMatchesC() {
        for row in floatConversionRows {
            checkRow(Float(row.value), row.onThisProcessor)
        }
    }

    func testIntAndUIntAreTheSixtyFourBitConversions() {
        for row in doubleConversionRows {
            XCTAssertEqual("\(it_floatToInteger(row.value, to: Int.self, onFailure: { _, _, _, _ in }))",
                           row.onThisProcessor[6], "\(row.value) -> Int")
            XCTAssertEqual("\(it_floatToInteger(row.value, to: UInt.self, onFailure: { _, _, _, _ in }))",
                           row.onThisProcessor[7], "\(row.value) -> UInt")
        }
    }

    private func inRangeCases<F: BinaryFloatingPoint, T: FixedWidthInteger>(_: F.Type, _: T.Type) {
        let d = "\(F.self) -> \(T.self)"
        check("\(d) 0", { it_floatToInteger(F(0), to: T.self, onFailure: $0) }, T(0), fails: false)
        check("\(d) -0", { it_floatToInteger(-F(0), to: T.self, onFailure: $0) }, T(0), fails: false)
        check("\(d) leastNonzero", { it_floatToInteger(F.leastNonzeroMagnitude, to: T.self, onFailure: $0) },
              T(0), fails: false)
        check("\(d) -leastNonzero", { it_floatToInteger(-F.leastNonzeroMagnitude, to: T.self, onFailure: $0) },
              T(0), fails: false)
        // Rounding is toward zero, as C does, and dropping a fractional part is not reported.
        check("\(d) 2.75", { it_floatToInteger(F(2.75), to: T.self, onFailure: $0) }, T(2), fails: false)
        check("\(d) 2.5", { it_floatToInteger(F(2.5), to: T.self, onFailure: $0) }, T(2), fails: false)
        check("\(d) 0.999", { it_floatToInteger(F(0.999), to: T.self, onFailure: $0) }, T(0), fails: false)
        // -0.5 truncates to zero, which every integer type can hold, so it is in range even
        // for unsigned types. This matches C, where only the truncated value must fit.
        check("\(d) -0.5", { it_floatToInteger(F(-0.5), to: T.self, onFailure: $0) }, T(0), fails: false)
        if T.isSigned {
            check("\(d) -2.75", { it_floatToInteger(F(-2.75), to: T.self, onFailure: $0) }, T(-2), fails: false)
            check("\(d) -2.5", { it_floatToInteger(F(-2.5), to: T.self, onFailure: $0) }, T(-2), fails: false)
        }
        check("\(d) NaN", { it_floatToInteger(F.nan, to: T.self, onFailure: $0) },
              iTermFloatToIntegerModel.processor(Double.nan, to: T.self), fails: true)
        check("\(d) signaling NaN", { it_floatToInteger(F.signalingNaN, to: T.self, onFailure: $0) },
              iTermFloatToIntegerModel.processor(Double.nan, to: T.self), fails: true)
        check("\(d) -NaN", { it_floatToInteger(-F.nan, to: T.self, onFailure: $0) },
              iTermFloatToIntegerModel.processor(Double.nan, to: T.self), fails: true)
    }

    func testInRangeAndNaN() {
        inRangeCases(Double.self, Int.self)
        inRangeCases(Double.self, Int8.self)
        inRangeCases(Double.self, Int16.self)
        inRangeCases(Double.self, Int32.self)
        inRangeCases(Double.self, Int64.self)
        inRangeCases(Double.self, UInt.self)
        inRangeCases(Double.self, UInt8.self)
        inRangeCases(Double.self, UInt16.self)
        inRangeCases(Double.self, UInt32.self)
        inRangeCases(Double.self, UInt64.self)
        inRangeCases(Float.self, Int.self)
        inRangeCases(Float.self, Int16.self)
        inRangeCases(Float.self, Int32.self)
        inRangeCases(Float.self, UInt8.self)
        inRangeCases(Float.self, UInt32.self)
        inRangeCases(CGFloat.self, Int.self)
        inRangeCases(CGFloat.self, Int32.self)
        inRangeCases(CGFloat.self, UInt32.self)
    }

    // Float16 converts to Double exactly, so it follows the same model.
    func testFloat16() {
#if arch(arm64)
        func cases<T: FixedWidthInteger>(_ type: T.Type) {
            let d = "Float16 -> \(T.self)"
            check("\(d) +inf", { it_floatToInteger(Float16.infinity, to: T.self, onFailure: $0) }, T.max, fails: true)
            check("\(d) -inf", { it_floatToInteger(-Float16.infinity, to: T.self, onFailure: $0) }, T.min, fails: true)
            check("\(d) NaN", { it_floatToInteger(Float16.nan, to: T.self, onFailure: $0) }, T(0), fails: true)
            check("\(d) 2.75", { it_floatToInteger(Float16(2.75), to: T.self, onFailure: $0) }, T(2), fails: false)
        }
        cases(Int.self)
        cases(Int32.self)
        cases(Int64.self)
        cases(UInt.self)
        cases(UInt16.self)
        cases(UInt32.self)
        cases(UInt64.self)
        // The greatest finite Float16 is 65504, which the wide types hold.
        check("Float16 greatestFinite -> Int32",
              { it_floatToInteger(Float16.greatestFiniteMagnitude, to: Int32.self, onFailure: $0) },
              Int32(65504), fails: false)
        check("Float16 -greatestFinite -> Int64",
              { it_floatToInteger(-Float16.greatestFiniteMagnitude, to: Int64.self, onFailure: $0) },
              Int64(-65504), fails: false)
        // Out of range for Int8: fcvtzs to 32 bits gives 65504, whose low byte is 0xE0.
        check("Float16 greatestFinite -> Int8",
              { it_floatToInteger(Float16.greatestFiniteMagnitude, to: Int8.self, onFailure: $0) },
              Int8(-32), fails: true)
#endif
    }

    func testDoubleToInt32Boundaries() {
        check("2147483647.0", { it_floatToInteger(2147483647.0, to: Int32.self, onFailure: $0) }, Int32.max, fails: false)
        check("2147483647.9", { it_floatToInteger(2147483647.9, to: Int32.self, onFailure: $0) }, Int32.max, fails: false)
        check("2147483648.0", { it_floatToInteger(2147483648.0, to: Int32.self, onFailure: $0) },
              valueOnThisProcessor(arm64: Int32.max, x86_64: Int32.min), fails: true)
        check("-2147483648.0", { it_floatToInteger(-2147483648.0, to: Int32.self, onFailure: $0) }, Int32.min, fails: false)
        check("-2147483648.9", { it_floatToInteger(-2147483648.9, to: Int32.self, onFailure: $0) }, Int32.min, fails: false)
        check("-2147483649.0", { it_floatToInteger(-2147483649.0, to: Int32.self, onFailure: $0) }, Int32.min, fails: true)
    }

    func testDoubleToInt64Boundaries() {
        // 2^63 is the smallest Double too large for Int64; the next Double below it is 2^63 - 1024.
        let twoTo63 = Double(sign: .plus, exponent: 63, significand: 1)
        check("2^63", { it_floatToInteger(twoTo63, to: Int64.self, onFailure: $0) },
              valueOnThisProcessor(arm64: Int64.max, x86_64: Int64.min), fails: true)
        check("2^63.nextDown", { it_floatToInteger(twoTo63.nextDown, to: Int64.self, onFailure: $0) },
              Int64.max - 1023, fails: false)
        check("-2^63", { it_floatToInteger(-twoTo63, to: Int64.self, onFailure: $0) }, Int64.min, fails: false)
        check("(-2^63).nextDown", { it_floatToInteger((-twoTo63).nextDown, to: Int64.self, onFailure: $0) },
              Int64.min, fails: true)
        check("Double(Int64.max)", { it_floatToInteger(Double(Int64.max), to: Int64.self, onFailure: $0) },
              valueOnThisProcessor(arm64: Int64.max, x86_64: Int64.min), fails: true)
    }

    func testDoubleToUInt64Boundaries() {
        let twoTo63 = Double(sign: .plus, exponent: 63, significand: 1)
        let twoTo64 = Double(sign: .plus, exponent: 64, significand: 1)
        check("2^64", { it_floatToInteger(twoTo64, to: UInt64.self, onFailure: $0) },
              valueOnThisProcessor(arm64: UInt64.max, x86_64: UInt64(1) << 63), fails: true)
        check("2^64.nextDown", { it_floatToInteger(twoTo64.nextDown, to: UInt64.self, onFailure: $0) },
              UInt64.max - 2047, fails: false)
        check("2^63", { it_floatToInteger(twoTo63, to: UInt64.self, onFailure: $0) }, UInt64(1) << 63, fails: false)
        check("(-1).nextUp", { it_floatToInteger((-1.0).nextUp, to: UInt64.self, onFailure: $0) }, 0, fails: false)
        check("-1", { it_floatToInteger(-1.0, to: UInt64.self, onFailure: $0) },
              valueOnThisProcessor(arm64: 0, x86_64: UInt64.max), fails: true)
    }

    func testDoubleToSmallTypes() {
        check("255.9 -> UInt8", { it_floatToInteger(255.9, to: UInt8.self, onFailure: $0) }, 255, fails: false)
        check("256 -> UInt8", { it_floatToInteger(256.0, to: UInt8.self, onFailure: $0) }, 0, fails: true)
        check("127.99 -> Int8", { it_floatToInteger(127.99, to: Int8.self, onFailure: $0) }, 127, fails: false)
        check("128 -> Int8", { it_floatToInteger(128.0, to: Int8.self, onFailure: $0) }, -128, fails: true)
        check("-128.99 -> Int8", { it_floatToInteger(-128.99, to: Int8.self, onFailure: $0) }, -128, fails: false)
        check("-129 -> Int8", { it_floatToInteger(-129.0, to: Int8.self, onFailure: $0) }, 127, fails: true)
        check("65535.5 -> UInt16", { it_floatToInteger(65535.5, to: UInt16.self, onFailure: $0) }, 65535, fails: false)
        check("65536 -> UInt16", { it_floatToInteger(65536.0, to: UInt16.self, onFailure: $0) }, 0, fails: true)
    }

    func testFloatToInt32Boundaries() {
        // 2^31 is exactly representable in Float; the Float below it is 2^31 - 128.
        let twoTo31 = Float(sign: .plus, exponent: 31, significand: 1)
        check("Float 2^31", { it_floatToInteger(twoTo31, to: Int32.self, onFailure: $0) },
              valueOnThisProcessor(arm64: Int32.max, x86_64: Int32.min), fails: true)
        check("Float 2^31.nextDown", { it_floatToInteger(twoTo31.nextDown, to: Int32.self, onFailure: $0) },
              Int32.max - 127, fails: false)
        check("Float -2^31", { it_floatToInteger(-twoTo31, to: Int32.self, onFailure: $0) }, Int32.min, fails: false)
        check("Float (-2^31).nextDown", { it_floatToInteger((-twoTo31).nextDown, to: Int32.self, onFailure: $0) },
              Int32.min, fails: true)
    }

    func testMessage() {
        let recorder = FailureRecorder()
        _ = it_floatToInteger(Double.nan, to: Int32.self, onFailure: recorder.handler)
        _ = it_floatToInteger(1e10, to: Int32.self, onFailure: recorder.handler)
        XCTAssertEqual(recorder.failures.map(\.message), [
            "converting nan (Double) to Int32 is out of range",
            "converting 10000000000.0 (Double) to Int32 is out of range",
        ])
    }
}

/// Both models of the processor's conversion are compiled on every architecture, so the one for
/// the processor the tests do not run on is checked here against the same table.
final class SwiftMigrationFloatConversionModelTests: XCTestCase {
    private func checkModel(_ name: String,
                            _ rows: [FloatConversionRow],
                            _ expected: (FloatConversionRow) -> [String],
                            _ model: (Double, Any.Type) -> String) {
        let types: [Any.Type] = [Int8.self, UInt8.self, Int16.self, UInt16.self,
                                 Int32.self, UInt32.self, Int64.self, UInt64.self]
        for row in rows {
            for (index, type) in types.enumerated() {
                XCTAssertEqual(model(row.value, type), expected(row)[index], "\(name): \(row.value) -> \(type)")
            }
        }
    }

    private static func arm64(_ value: Double, _ type: Any.Type) -> String {
        switch type {
        case is Int8.Type: return "\(iTermFloatToIntegerModel.arm64(value, to: Int8.self))"
        case is UInt8.Type: return "\(iTermFloatToIntegerModel.arm64(value, to: UInt8.self))"
        case is Int16.Type: return "\(iTermFloatToIntegerModel.arm64(value, to: Int16.self))"
        case is UInt16.Type: return "\(iTermFloatToIntegerModel.arm64(value, to: UInt16.self))"
        case is Int32.Type: return "\(iTermFloatToIntegerModel.arm64(value, to: Int32.self))"
        case is UInt32.Type: return "\(iTermFloatToIntegerModel.arm64(value, to: UInt32.self))"
        case is Int64.Type: return "\(iTermFloatToIntegerModel.arm64(value, to: Int64.self))"
        case is UInt64.Type: return "\(iTermFloatToIntegerModel.arm64(value, to: UInt64.self))"
        default: return "unexpected type \(type)"
        }
    }

    private static func x86_64(_ value: Double, _ type: Any.Type) -> String {
        switch type {
        case is Int8.Type: return "\(iTermFloatToIntegerModel.x86_64(value, to: Int8.self))"
        case is UInt8.Type: return "\(iTermFloatToIntegerModel.x86_64(value, to: UInt8.self))"
        case is Int16.Type: return "\(iTermFloatToIntegerModel.x86_64(value, to: Int16.self))"
        case is UInt16.Type: return "\(iTermFloatToIntegerModel.x86_64(value, to: UInt16.self))"
        case is Int32.Type: return "\(iTermFloatToIntegerModel.x86_64(value, to: Int32.self))"
        case is UInt32.Type: return "\(iTermFloatToIntegerModel.x86_64(value, to: UInt32.self))"
        case is Int64.Type: return "\(iTermFloatToIntegerModel.x86_64(value, to: Int64.self))"
        case is UInt64.Type: return "\(iTermFloatToIntegerModel.x86_64(value, to: UInt64.self))"
        default: return "unexpected type \(type)"
        }
    }

    func testArm64Model() {
        checkModel("arm64", doubleConversionRows + floatConversionRows, \.arm64, Self.arm64)
    }

    func testX86_64Model() {
        checkModel("x86_64", doubleConversionRows + floatConversionRows, \.x86_64, Self.x86_64)
    }

    func testProcessorPicksTheModelForThisArchitecture() {
        for row in doubleConversionRows {
            XCTAssertEqual("\(iTermFloatToIntegerModel.processor(row.value, to: UInt8.self))", row.onThisProcessor[1])
            XCTAssertEqual("\(iTermFloatToIntegerModel.processor(row.value, to: UInt64.self))", row.onThisProcessor[7])
        }
    }
}

// MARK: - Synchronized

private struct SynchronizedTestError: Error {}

final class SwiftMigrationSynchronizedTests: XCTestCase {
    /// Fails if another thread cannot take `lock`, which means this thread still holds it.
    private func assertLockIsFree(_ lock: AnyObject) {
        let acquired = expectation(description: "another thread took the lock")
        let thread = Thread {
            objc_sync_enter(lock)
            objc_sync_exit(lock)
            acquired.fulfill()
        }
        // Match the waiting thread's priority so the wait is not a priority inversion.
        thread.qualityOfService = .userInteractive
        thread.start()
        // The timeout is only a failure limit: a free lock is taken at once.
        wait(for: [acquired], timeout: 30)
    }

    func testReturnsBodyValue() {
        let lock = NSObject()
        let value: Int = it_synchronized(lock) { 42 }
        XCTAssertEqual(value, 42)
        let string: String = it_synchronized(lock) { "abc" }
        XCTAssertEqual(string, "abc")
        assertLockIsFree(lock)
    }

    func testReentrantOnSameThread() {
        let lock = NSObject()
        let value: Int = it_synchronized(lock) {
            it_synchronized(lock) {
                it_synchronized(lock) { 7 }
            } + 1
        }
        XCTAssertEqual(value, 8)
        assertLockIsFree(lock)
    }

    func testReentrantWithDirectObjcSyncEnter() {
        // Interoperates with the primitive @synchronized compiles to.
        let lock = NSObject()
        objc_sync_enter(lock)
        let value: Int = it_synchronized(lock) { 3 }
        objc_sync_exit(lock)
        XCTAssertEqual(value, 3)
        assertLockIsFree(lock)
    }

    func testReleasesOnNormalExitFromClosure() {
        let lock = NSObject()
        var visited = false
        it_synchronized(lock) {
            visited = true
            if visited {
                return
            }
            XCTFail("unreachable")
        }
        XCTAssertTrue(visited)
        assertLockIsFree(lock)
    }

    func testReleasesOnThrow() {
        let lock = NSObject()
        XCTAssertThrowsError(try it_synchronized(lock) { () throws -> Int in
            throw SynchronizedTestError()
        }) { error in
            XCTAssertTrue(error is SynchronizedTestError)
        }
        assertLockIsFree(lock)
    }

    func testThrowingBodyThatDoesNotThrowReturnsValue() throws {
        let lock = NSObject()
        let value = try it_synchronized(lock) { () throws -> Int in 5 }
        XCTAssertEqual(value, 5)
        assertLockIsFree(lock)
    }

    /// While one thread is inside, another thread that tries to enter waits until it leaves.
    private func checkExclusion(enter: @escaping (AnyObject, () -> Void) -> Void) {
        let lock = NSObject()
        let otherIsAboutToEnter = DispatchSemaphore(value: 0)
        let otherEntered = DispatchSemaphore(value: 0)
        let otherFinished = expectation(description: "other thread finished")
        let state = NSLock()
        var holderFinished = false
        var otherSawHolderFinished: Bool?

        enter(lock) {
            let other = Thread {
                otherIsAboutToEnter.signal()
                enter(lock) {
                    state.lock()
                    otherSawHolderFinished = holderFinished
                    state.unlock()
                    otherEntered.signal()
                }
                otherFinished.fulfill()
            }
            // Match the waiting thread's priority so the wait is not a priority inversion.
            other.qualityOfService = .userInteractive
            other.start()
            otherIsAboutToEnter.wait()
            // If exclusion were broken, the other thread would get in now and signal. With a
            // working lock this wait always runs to its limit, so the limit only bounds how long
            // the test gives a broken lock to show itself; it cannot make a correct lock fail.
            let gotInWhileHeld = otherEntered.wait(timeout: .now() + 0.2) == .success
            XCTAssertFalse(gotInWhileHeld, "another thread entered while the lock was held")
            state.lock()
            holderFinished = true
            state.unlock()
        }
        wait(for: [otherFinished], timeout: 30)
        XCTAssertEqual(otherSawHolderFinished, true)
    }

    func testExcludesAnotherThread() {
        checkExclusion { lock, body in
            it_synchronized(lock) { body() }
        }
    }

    func testOptionalNonNilLockExcludesAnotherThread() {
        checkExclusion { lock, body in
            let optionalLock: AnyObject? = lock
            it_synchronized(optionalLock) { body() }
        }
    }

    func testNilLockAssertsAndRunsBodyUnprotected() {
        let recorder = FailureRecorder()
        let nilLock: AnyObject? = nil
        var ran = false
        let value: Int = it_synchronized(nilLock, onFailure: recorder.handler) {
            ran = true
            return 11
        }
        XCTAssertTrue(ran, "The Objective-C ran the body with no lock, so the port does too")
        XCTAssertEqual(value, 11)
        XCTAssertEqual(recorder.failures.map(\.message), ["nil lock passed to it_synchronized; running unprotected"])
        XCTAssertEqual(recorder.failures.first?.function, "testNilLockAssertsAndRunsBodyUnprotected()")
    }

    func testNilLockThrowingBodyPropagates() {
        let recorder = FailureRecorder()
        let nilLock: AnyObject? = nil
        XCTAssertThrowsError(try it_synchronized(nilLock, onFailure: recorder.handler) { () throws -> Int in
            throw SynchronizedTestError()
        })
        XCTAssertEqual(recorder.failures.count, 1)
    }

    func testNonNilOptionalLockDoesNotAssert() {
        let recorder = FailureRecorder()
        let lock = NSObject()
        let optionalLock: AnyObject? = lock
        let value: Int = it_synchronized(optionalLock, onFailure: recorder.handler) { 4 }
        XCTAssertEqual(value, 4)
        XCTAssertTrue(recorder.failures.isEmpty)
        assertLockIsFree(lock)
    }

    func testClassObjectAsLock() {
        let lock: AnyObject = NSObject.self
        let value: Int = it_synchronized(lock) { 9 }
        XCTAssertEqual(value, 9)
        assertLockIsFree(lock)
    }
}
