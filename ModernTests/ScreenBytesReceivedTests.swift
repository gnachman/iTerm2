//
//  ScreenBytesReceivedTests.swift
//  iTerm2 ModernTests
//
//  A session counts the bytes it reads, for the flow control monitor's receive rate, which works
//  whether or not flow control is on.
//

import XCTest
@testable import iTerm2SharedARC

final class ScreenBytesReceivedTests: XCTestCase {
    func testEveryByteReadIsCounted() {
        let harness = TerminalTestHarness()
        XCTAssertEqual(harness.screen.bytesReceived(), 0)
        harness.send(Array("hello".utf8))
        harness.send(Array(" world\r\n".utf8))
        harness.sync()
        XCTAssertEqual(harness.screen.bytesReceived(), 13)
    }
}
