//
//  iTermWorkingDirectoryPollerTests.swift
//  iTerm2
//
//  Tests that the poller always answers the completions handed to
//  -addOneTimeCompletion:, including when it declines to poll at all.
//

import XCTest
@testable import iTerm2SharedARC

@objc class MockWorkingDirectoryPollerDelegate: NSObject, iTermWorkingDirectoryPollerDelegate {
    var processID: pid_t = 0
    var shouldPoll = true
    var foundDirectoryCallCount = 0

    func workingDirectoryPollerShouldPoll() -> Bool {
        return shouldPoll
    }

    func workingDirectoryPollerDidFindWorkingDirectory(_ path: String?, invalidated: Bool) {
        foundDirectoryCallCount += 1
    }

    func workingDirectoryPollerProcessID() -> pid_t {
        return processID
    }
}

final class iTermWorkingDirectoryPollerTests: XCTestCase {
    private var poller: iTermWorkingDirectoryPoller!
    private var mockDelegate: MockWorkingDirectoryPollerDelegate!

    override func setUp() {
        super.setUp()
        poller = iTermWorkingDirectoryPoller()
        mockDelegate = MockWorkingDirectoryPollerDelegate()
        poller.delegate = mockDelegate
    }

    override func tearDown() {
        poller.delegate = nil
        poller = nil
        mockDelegate = nil
        super.tearDown()
    }

    // A tmux or channel session's job manager reports pid 0, and a session that never launched a
    // job reports 0 too. The poller can't look up a directory for any of those, but a caller that
    // added a completion is waiting on an answer and would hang without one.
    func testNoProcessID_StillCompletes() {
        mockDelegate.processID = 0

        var completionCount = 0
        var reportedDirectory: String? = "unset"
        poller.addOneTimeCompletion { pwd in
            completionCount += 1
            reportedDirectory = pwd
        }

        poller.poll()

        XCTAssertEqual(completionCount, 1)
        XCTAssertNil(reportedDirectory)
    }

    func testNoProcessID_DoesNotNotifyDelegateOfADirectory() {
        mockDelegate.processID = 0

        poller.poll()

        // There was no poll, so there is no result to report. Telling the delegate nil here would
        // clear a local directory it already knows about.
        XCTAssertEqual(mockDelegate.foundDirectoryCallCount, 0)
    }

    // Each completion is answered by exactly one poll: the poll it was waiting on drains it, and a
    // later poll neither calls it again nor loses a completion added in between.
    func testNoProcessID_EachCompletionIsCalledOnce() {
        mockDelegate.processID = 0

        var firstCount = 0
        var secondCount = 0
        poller.addOneTimeCompletion { _ in
            firstCount += 1
        }

        poller.poll()
        XCTAssertEqual(firstCount, 1)
        XCTAssertEqual(secondCount, 0)

        poller.addOneTimeCompletion { _ in
            secondCount += 1
        }
        poller.poll()

        XCTAssertEqual(firstCount, 1)
        XCTAssertEqual(secondCount, 1)
    }
}
