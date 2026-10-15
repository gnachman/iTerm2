//
//  SSHEndBannerTests.swift
//  iTerm2
//

import XCTest
@testable import iTerm2SharedARC

/// F-329: the banner for several ended ssh sessions read “2 ssh sessions ended..”.
final class SSHEndBannerTests: XCTestCase {
    func testBannerPunctuation() {
        let harness = TerminalTestHarness()
        harness.screen.performBlock(joinedThreads: { _, mutableState, _ in
            XCTAssertEqual(mutableState.sshEndBannerTerminatingCount(2, newLocation: nil),
                           "2 ssh sessions ended.")
            XCTAssertEqual(mutableState.sshEndBannerTerminatingCount(2, newLocation: "host"),
                           "2 ssh sessions ended — now at host.")
            XCTAssertEqual(mutableState.sshEndBannerTerminatingCount(1, newLocation: nil),
                           "ssh exited.")
        })
    }
}
