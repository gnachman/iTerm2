//
//  CockpitCloseTests.swift
//  iTerm2
//

import XCTest
@testable import iTerm2SharedARC

final class CockpitCloseTests: XCTestCase {
    /// Shell > Close (Cmd-W) sends closeCurrentSession:. It is enabled for a
    /// key window only when that window's controller responds to it (see
    /// PseudoTerminal's validateMenuItem:), so the cockpit must implement it.
    func testCockpitHandlesCloseCurrentSession() {
        let controller: NSObject = CockpitWindowController.shared
        XCTAssertTrue(controller.responds(to: NSSelectorFromString("closeCurrentSession:")))
    }
}
