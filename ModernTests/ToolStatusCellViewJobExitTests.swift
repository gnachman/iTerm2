//
//  ToolStatusCellViewJobExitTests.swift
//  ModernTests
//
//  QA finding F-065: a Session Status row's name label kept the name of
//  the job that was running when the row was last configured (for
//  example “sleep”) after the job exited, while the tab title showed
//  “-zsh”. The row is configured only when the session's status
//  changes, so between configurations the label must follow the
//  session's “name” variable on its own. Fixed by 5b2327dd0.
//

import XCTest
@testable import iTerm2SharedARC

final class ToolStatusCellViewJobExitTests: XCTestCase, iTermObject {
    private var scopes = [iTermVariableScope]()
    private var frames = [iTermVariables]()

    func objectMethodRegistry() -> iTermBuiltInFunctions? { nil }
    func objectScope() -> iTermVariableScope? { scopes.first }

    override func tearDown() {
        scopes.removeAll()
        frames.removeAll()
        super.tearDown()
    }

    private func makeSessionScope(id: String, name: String) -> iTermVariableScope {
        let scope = iTermVariableScope()
        let variables = iTermVariables(context: [.session], owner: self)
        scope.add(variables, toScopeNamed: nil)
        scope.setValue(id, forVariableNamed: iTermVariableKeySessionID)
        scope.setValue(name, forVariableNamed: iTermVariableKeySessionName)
        scopes.append(scope)
        frames.append(variables)
        return scope
    }

    // Configures the row inside its own autorelease pool, as a table
    // reload in the app does, so nothing left in the test method's pool
    // keeps the first evaluation's observers alive.
    private func configure(_ cell: ToolStatusCellView, scope: iTermVariableScope, status: String) {
        autoreleasepool {
            cell.configure(scope: scope,
                           dotImage: nil,
                           peerLabel: nil,
                           shortcut: nil,
                           statusText: status,
                           statusColor: nil,
                           detail: nil,
                           armed: false)
        }
    }

    // The predicate is the update itself, not a delay; the timeout only
    // bounds a failure.
    private func waitUntil(_ cell: ToolStatusCellView,
                           shows value: String,
                           file: StaticString = #filePath,
                           line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in cell.nameLabel.stringValue == value },
            object: nil)
        let result = XCTWaiter().wait(for: [expectation], timeout: 10)
        XCTAssertEqual(result, .completed,
                       "Row shows “\(cell.nameLabel.stringValue)”, expected “\(value)”",
                       file: file, line: line)
    }

    // Waits for the label's evaluator to observe the session's “name”
    // variable, so the change that follows cannot race an evaluation
    // that is still in flight.
    private func waitUntilObservingName(_ cell: ToolStatusCellView,
                                        file: StaticString = #filePath,
                                        line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                (cell.nameLabel.swiftyString?.refs ?? []).contains { $0.path == iTermVariableKeySessionName }
            },
            object: nil)
        let result = XCTWaiter().wait(for: [expectation], timeout: 10)
        XCTAssertEqual(result, .completed,
                       "Label observes only \((cell.nameLabel.swiftyString?.refs ?? []).map(\.path))",
                       file: file, line: line)
    }

    // The status changes while “sleep” runs, which configures the row.
    // When the job exits the session's name goes back to “-zsh” with no
    // further status change, so no reconfigure happens.
    func test_jobExitWithoutStatusChangeUpdatesTheRow() {
        let scope = makeSessionScope(id: "S1", name: "sleep")
        let cell = ToolStatusCellView(frame: NSRect(x: 0, y: 0, width: 200, height: 44))
        configure(cell, scope: scope, status: "yy")
        waitUntil(cell, shows: "sleep")
        waitUntilObservingName(cell)

        scope.setValue("-zsh", forVariableNamed: iTermVariableKeySessionName)
        waitUntil(cell, shows: "-zsh")
    }

    // A reload that reconfigures the row with the same scope reuses the
    // label's evaluator; a later job exit must still reach the label.
    func test_jobExitAfterReconfigureUpdatesTheRow() {
        let scope = makeSessionScope(id: "S1", name: "-zsh")
        let cell = ToolStatusCellView(frame: NSRect(x: 0, y: 0, width: 200, height: 44))
        configure(cell, scope: scope, status: "idle")
        waitUntil(cell, shows: "-zsh")
        waitUntilObservingName(cell)

        scope.setValue("sleep", forVariableNamed: iTermVariableKeySessionName)
        configure(cell, scope: scope, status: "yy")
        waitUntil(cell, shows: "sleep")
        waitUntilObservingName(cell)

        scope.setValue("-zsh", forVariableNamed: iTermVariableKeySessionName)
        waitUntil(cell, shows: "-zsh")
    }
}
