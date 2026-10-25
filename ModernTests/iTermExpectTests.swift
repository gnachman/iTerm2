//
//  iTermExpectTests.swift
//  ModernTests
//

import XCTest
@testable import iTerm2SharedARC

final class iTermExpectTests: XCTestCase {
    private func drainMainQueue() {
        let drained = XCTestExpectation(description: "Main queue drained")
        DispatchQueue.main.async {
            drained.fulfill()
        }
        wait(for: [drained], timeout: 10)
    }

    // F-353: a wet copy of an expectation can be added and then match, and the match complete
    // the original on the main thread, before the main thread runs the willExpect callback the
    // add dispatched. Nothing but the expect object holds the original, so once it completes it
    // is gone. Its willExpect must run anyway, and before that of its successor.
    func testWillExpectRunsWhenTheOriginalCompletesFirst() {
        let dry = iTermExpect(dry: true)
        var calls = [String]()
        autoreleasepool {
            let first = dry.expectRegularExpression("^a",
                                                    after: nil,
                                                    deadline: nil,
                                                    willExpect: { calls.append("first") },
                                                    completion: nil)
            let second = dry.expectRegularExpression("^b",
                                                     after: first,
                                                     deadline: nil,
                                                     willExpect: { calls.append("second") },
                                                     completion: nil)
            _ = dry.expectRegularExpression("^c",
                                            after: second,
                                            deadline: nil,
                                            willExpect: { calls.append("third") },
                                            completion: nil)
        }
        var wet: iTermExpect? = (dry.copy() as! iTermExpect)
        drainMainQueue()
        XCTAssertEqual(calls, ["first"])

        // The mutation thread matches the first and then the second before the main thread runs
        // anything. Here the dispatcher completes each original at once.
        autoreleasepool {
            for regex in ["^a", "^b"] {
                guard let expectation = wet?.expectations.first(where: { $0.regex == regex }) else {
                    XCTFail("No wet expectation for \(regex)")
                    return
                }
                expectation.didMatch(withCaptureGroups: [regex]) { closure in
                    closure()
                }
            }
        }
        wet = nil
        drainMainQueue()

        XCTAssertEqual(calls, ["first", "second", "third"])
    }
}
