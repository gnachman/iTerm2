//
//  RemoteCommandParkPredicateTests.swift
//  iTerm2 ModernTests
//
//  Permission.parksOnApproval is the ONE mapping shared by the real approval gate
//  (ChatClient.processRemoteCommandRequest) and ChatAgent's park prediction (which
//  decides whether parking cleared the phone's typing). Pinning it here keeps the
//  two from drifting: a .ask command parks even when the content-safety heuristic
//  says safe, and .always parks only when the safety check flagged it.
//

import XCTest
@testable import iTerm2SharedARC

final class RemoteCommandParkPredicateTests: XCTestCase {
    private typealias Permission = RemoteCommandExecutor.Permission

    func testAskAlwaysParksRegardlessOfSafe() {
        XCTAssertTrue(Permission.ask.parksOnApproval(safe: nil))
        XCTAssertTrue(Permission.ask.parksOnApproval(safe: true))
        XCTAssertTrue(Permission.ask.parksOnApproval(safe: false))
    }

    func testAlwaysParksOnlyWhenUnsafe() {
        XCTAssertFalse(Permission.always.parksOnApproval(safe: nil))
        XCTAssertFalse(Permission.always.parksOnApproval(safe: true))
        XCTAssertTrue(Permission.always.parksOnApproval(safe: false),
                      "an Always-allowed command flagged unsafe still parks on the user")
    }

    func testNeverNeverParks() {
        XCTAssertFalse(Permission.never.parksOnApproval(safe: nil))
        XCTAssertFalse(Permission.never.parksOnApproval(safe: true))
        XCTAssertFalse(Permission.never.parksOnApproval(safe: false))
    }
}
