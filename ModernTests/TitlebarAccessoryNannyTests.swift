//
//  TitlebarAccessoryNannyTests.swift
//  ModernTests
//
//  -[NSWindow titlebarAccessoryViewControllers] throws for a window without .titled
//  (“titlebarAccessoryViewControllers not supported for this window style”). On exiting Lion
//  fullscreen, PseudoTerminal restores the saved style mask, which can lack .titled (seen with tmux
//  integration windows), and then calls forceReaddAll(), which crashed. The nanny must leave
//  untitled windows alone. ObjCTry turns the Objective-C exception into a Swift error.
//

import AppKit
import XCTest
@testable import iTerm2SharedARC

final class TitlebarAccessoryNannyTests: XCTestCase {
    private var windowController: NSWindowController!
    private var nanny: iTermTitlebarAccessoryNanny!

    override func setUp() {
        super.setUp()
        // No .titled, like the windows in the crash reports (styleMask=4).
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                              styleMask: [.miniaturizable],
                              backing: .buffered,
                              defer: true)
        window.isReleasedWhenClosed = false
        windowController = NSWindowController(window: window)
        nanny = iTermTitlebarAccessoryNanny()
        nanny.windowController = windowController
    }

    override func tearDown() {
        windowController.window?.close()
        windowController = nil
        nanny = nil
        super.tearDown()
    }

    func testPrecondition() {
        XCTAssertThrowsError(try ObjCTry { _ = self.windowController.window!.titlebarAccessoryViewControllers },
                             "AppKit no longer throws for untitled windows")
    }

    func testForceReaddAllOnUntitledWindowDoesNotThrow() {
        XCTAssertNoThrow(try ObjCTry { self.nanny.forceReaddAll() })
    }

    func testAddAndUpdateOnUntitledWindowDoesNotThrow() {
        let vc = NSTitlebarAccessoryViewController()
        vc.view = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 20))
        XCTAssertNoThrow(try ObjCTry { self.nanny.add(viewController: vc) })
        XCTAssertNoThrow(try ObjCTry { self.nanny.updateIfNeeded() })
        XCTAssertNoThrow(try ObjCTry { self.nanny.forceReaddAll() })
    }

    // A titled window still gets its accessories.
    func testAddAndUpdateOnTitledWindowAddsAccessory() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                              styleMask: [.titled, .miniaturizable],
                              backing: .buffered,
                              defer: true)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let titledController = NSWindowController(window: window)
        let titledNanny = iTermTitlebarAccessoryNanny()
        titledNanny.windowController = titledController
        let vc = NSTitlebarAccessoryViewController()
        vc.view = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 20))
        try ObjCTry { titledNanny.add(viewController: vc) }
        titledNanny.updateIfNeeded()
        XCTAssertTrue(window.titlebarAccessoryViewControllers.contains(vc))
        XCTAssertTrue(titledNanny.has(viewController: vc))
    }

    private func makeAccessory() -> NSTitlebarAccessoryViewController {
        let vc = NSTitlebarAccessoryViewController()
        vc.view = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 20))
        return vc
    }

    // An update skipped while the window had no title bar must not swallow later ones. Requests
    // only trigger an update when needsUpdate goes from false to true, so leaving it set after the
    // skip made every later add or min-height change a no-op.
    func testAddAfterRegainingTitleBarInstallsEveryAccessory() throws {
        let window = try XCTUnwrap(windowController.window)
        let early = makeAccessory()
        try ObjCTry { self.nanny.add(viewController: early) }

        window.styleMask.insert(.titled)
        let late = makeAccessory()
        try ObjCTry { self.nanny.add(viewController: late) }

        XCTAssertTrue(window.titlebarAccessoryViewControllers.contains(early))
        XCTAssertTrue(window.titlebarAccessoryViewControllers.contains(late))
    }

    func testMinHeightUpdateAfterRegainingTitleBarInstallsAccessory() throws {
        let window = try XCTUnwrap(windowController.window)
        let vc = makeAccessory()
        try ObjCTry { self.nanny.add(viewController: vc) }

        window.styleMask.insert(.titled)
        _ = nanny.updateMinHeight(viewController: vc,
                                  minHeight: 20,
                                  frame: NSRect(x: 0, y: 0, width: 100, height: 20))

        XCTAssertTrue(window.titlebarAccessoryViewControllers.contains(vc))
    }
}
