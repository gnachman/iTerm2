//
//  CockpitSheetLevelGuardTests.swift
//  ModernTests
//
//  QA finding F-249: the floating Cockpit panel covered sheets on terminal
//  windows (such as the Broadcast Input confirmation), hiding their
//  buttons. While another window shows a sheet the panel drops to the
//  normal level, and it floats again once no sheet remains.
//

import AppKit
import XCTest
@testable import iTerm2SharedARC

@MainActor
final class CockpitSheetLevelGuardTests: XCTestCase {
    private var center: NotificationCenter!
    private var panel: NSPanel!
    private var parent: NSWindow!
    private var otherParent: NSWindow!
    private var windowsWithSheets: [NSWindow] = []
    private var levelGuard: CockpitSheetLevelGuard!

    override func setUp() {
        super.setUp()
        center = NotificationCenter()
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                        styleMask: [.titled, .utilityWindow],
                        backing: .buffered,
                        defer: true)
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        parent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                          styleMask: [.titled],
                          backing: .buffered,
                          defer: true)
        parent.isReleasedWhenClosed = false
        otherParent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                               styleMask: [.titled],
                               backing: .buffered,
                               defer: true)
        otherParent.isReleasedWhenClosed = false
        windowsWithSheets = []
        levelGuard = CockpitSheetLevelGuard(panel: panel,
                                            notificationCenter: center,
                                            windowsWithSheets: { [unowned self] excluding in
            self.windowsWithSheets.filter { $0 !== excluding }
        })
    }

    override func tearDown() {
        levelGuard = nil
        panel = nil
        parent = nil
        otherParent = nil
        center = nil
        super.tearDown()
    }

    private func begin(_ window: NSWindow) {
        windowsWithSheets.append(window)
        center.post(name: NSWindow.willBeginSheetNotification, object: window)
    }

    private func end(_ window: NSWindow) {
        center.post(name: NSWindow.didEndSheetNotification, object: window)
        windowsWithSheets.removeAll { $0 === window }
    }

    func testSheetOnAnotherWindowLowersPanelUntilItEnds() {
        begin(parent)
        XCTAssertEqual(panel.level, .normal)
        end(parent)
        XCTAssertEqual(panel.level, .floating)
    }

    func testPanelStaysLoweredWhileAnotherSheetRemains() {
        begin(parent)
        begin(otherParent)
        end(parent)
        XCTAssertEqual(panel.level, .normal)
        end(otherParent)
        XCTAssertEqual(panel.level, .floating)
    }

    func testWindowClosingWithSheetUpRestoresPanel() {
        begin(parent)
        // The window closes without reporting the sheet's end.
        windowsWithSheets.removeAll { $0 === parent }
        center.post(name: NSWindow.willCloseNotification, object: parent)
        let restored = expectation(description: "restored")
        DispatchQueue.main.async {
            restored.fulfill()
        }
        wait(for: [restored], timeout: 10)
        XCTAssertEqual(panel.level, .floating)
    }

    func testSheetOnThePanelItselfDoesNotLowerIt() {
        center.post(name: NSWindow.willBeginSheetNotification, object: panel)
        XCTAssertEqual(panel.level, .floating)
    }
}
