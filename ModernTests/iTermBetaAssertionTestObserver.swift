//
//  iTermBetaAssertionTestObserver.swift
//  ModernTests
//
//  Makes a failed Swift beta assertion fail the running test with its message, instead of
//  crashing the test host.
//
//  The tests build in Development, where a failed beta assertion is fatal (decisions.md,
//  2026-11-20: the migration helpers assert aggressively in Development, Beta, Nightly and tests).
//  Crashing the host would end every test left in that process and report only a crash; failing
//  the test names the test and the assertion and lets the run continue. The helper then returns
//  the C result, as it does in release.
//
//  iTermBetaAssertionTestObserverLoader.m registers this observer when the test bundle loads.
//  While a test case runs, a failed beta assertion (it_betaAssert, it_conservativeBetaAssert,
//  it_synchronized with a nil lock, and every event reported by the arithmetic and conversion
//  helpers) records a test failure at the caller's file and line. Outside a test case, as during
//  the app's launch or from work a finished test left running, it crashes as in production.
//
//  Tests that replace iTermBetaAssertions.crashHandler themselves save and restore whatever is
//  installed, so they work unchanged on top of this.
//

import XCTest
@testable import iTerm2SharedARC

/// Registered for the whole test run. See the file comment.
@objc(iTermBetaAssertionTestObserver)
final class iTermBetaAssertionTestObserver: NSObject, XCTestObservation {
    private static let lock = NSLock()
    /// The test case that is running, if any. Guarded by `lock`, since an assertion can fail on
    /// any thread.
    private static var runningTest: XCTestCase?
    /// The crash handler this replaced, used outside a test case.
    private static var productionCrashHandler: iTermBetaAssertionFailureHandler?

    /// Called once, from iTermBetaAssertionTestObserverLoader's +load.
    @objc static func registerObserver() {
        lock.lock()
        let alreadyRegistered = productionCrashHandler != nil
        if !alreadyRegistered {
            productionCrashHandler = iTermBetaAssertions.crashHandler
        }
        lock.unlock()
        if alreadyRegistered {
            return
        }
        iTermBetaAssertions.crashHandler = iTermBetaAssertionTestObserver.handleFailure
        XCTestObservationCenter.shared.addTestObserver(iTermBetaAssertionTestObserver())
    }

    /// Whether this observer is the installed crash handler's owner. For the test that checks the
    /// registration happened.
    static var isRegistered: Bool {
        lock.lock()
        defer {
            lock.unlock()
        }
        return productionCrashHandler != nil
    }

    func testCaseWillStart(_ testCase: XCTestCase) {
        Self.lock.lock()
        Self.runningTest = testCase
        Self.lock.unlock()
    }

    func testCaseDidFinish(_ testCase: XCTestCase) {
        Self.lock.lock()
        Self.runningTest = nil
        Self.lock.unlock()
    }

    /// The crash handler while the tests run.
    private static func handleFailure(_ message: String,
                                      file: StaticString,
                                      line: UInt,
                                      function: StaticString) {
        lock.lock()
        let test = runningTest
        let production = productionCrashHandler
        lock.unlock()
        guard test != nil else {
            production?(message, file, line, function)
            return
        }
        XCTFail("[BETA ASSERT] \(message) (in \(function))", file: file, line: line)
    }
}
