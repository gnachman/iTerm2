//
//  AIConnectionTestCancellationTests.swift
//  iTerm2
//

import XCTest
@testable import iTerm2SharedARC

// Test Connection against an unresponsive server lasts as long as the AI
// timeout, so the editor lets the user stop it.
final class AIConnectionTestCancellationTests: XCTestCase {
    func testCancelReportsCancelledOnceAndStopsTheRequest() {
        var outcomes = [AIConnectionTestOutcome]()
        let test = AIConnectionTest { outcome, _ in outcomes.append(outcome) }
        let request = Cancellation()
        test.attach(request)

        test.cancel()
        test.finish(.failure, "The request timed out.")
        test.cancel()

        XCTAssertEqual(outcomes, [.cancelled])
        XCTAssertTrue(request.canceled)
    }

    func testFinishReportsOnce() {
        var outcomes = [AIConnectionTestOutcome]()
        let test = AIConnectionTest { outcome, _ in outcomes.append(outcome) }
        test.finish(.success, "")
        test.cancel()
        XCTAssertEqual(outcomes, [.success])
    }

    // A request started after the test was already stopped is cancelled.
    func testAttachingAfterCancelCancelsTheRequest() {
        let test = AIConnectionTest { _, _ in }
        test.cancel()
        let request = Cancellation()
        test.attach(request)
        XCTAssertTrue(request.canceled)
    }

    // The editor keeps the returned test to stop it while the request is in
    // flight; stopping reports exactly one outcome.
    @MainActor
    func testStoppingTesterRightAfterStartReportsOnce() {
        var outcomes = [AIConnectionTestOutcome]()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                              styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let test = AIConnectionTester.test(modelName: "m",
                                           url: "http://127.0.0.1:1/v1/chat/completions",
                                           api: .chatCompletions,
                                           credential: AIModelCredential.none.storedValue,
                                           modelAPIKey: nil,
                                           functionCalling: false,
                                           supportsTemperature: true,
                                           customHeaders: [],
                                           inWindow: window) { outcome, _ in
            outcomes.append(outcome)
        }
        test.cancel()
        XCTAssertEqual(outcomes, [.cancelled])
    }
}
