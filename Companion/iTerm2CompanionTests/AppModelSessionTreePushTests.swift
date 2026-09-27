//
//  AppModelSessionTreePushTests.swift
//  iTerm2CompanionTests
//
//  The Mac pushes an unsolicited .sessionTree when sessions/tabs/windows change so
//  the phone's Sessions tab updates live. A solicited fetch is correlated by
//  requestID and resolved by the client's waiter, so only the unsolicited push
//  reaches handle(event:); it must update the model's sessionTree in place.
//

import XCTest
import CompanionProtocol
@testable import iTerm2Companion

@MainActor
final class AppModelSessionTreePushTests: XCTestCase {
    private func tree(sessionName: String) -> CompanionSessionTree {
        CompanionSessionTree(windows: [
            .init(title: "Window", tabs: [
                .init(title: "Tab", panes: [
                    .init(session: CompanionSessionSummary(guid: "g1", name: sessionName, subtitle: ""),
                          peers: [])
                ])
            ])
        ])
    }

    func test_unsolicitedSessionTreeUpdatesModel() {
        let model = AppModel()
        XCTAssertNil(model.sessionTree)
        let pushed = tree(sessionName: "zsh")
        model.testHandleHostEvent(.sessionTree(pushed))
        XCTAssertEqual(model.sessionTree, pushed)
    }

    func test_sessionTreePushReplacesPriorTreeAndClearsError() {
        let model = AppModel()
        model.testHandleHostEvent(.sessionTree(tree(sessionName: "one")))
        model.sessionTreeError = "stale error"
        let newer = tree(sessionName: "two")
        model.testHandleHostEvent(.sessionTree(newer))
        XCTAssertEqual(model.sessionTree, newer)
        XCTAssertNil(model.sessionTreeError, "a good pushed tree clears any prior load error")
    }
}
