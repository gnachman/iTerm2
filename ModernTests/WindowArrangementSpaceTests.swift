//
//  WindowArrangementSpaceTests.swift
//  ModernTests
//
//  A saved window arrangement remembers which Space each window was on, and
//  restoring it puts the window back there (gitlab issue 10087).
//

import XCTest
@testable import iTerm2SharedARC

final class WindowArrangementSpaceTests: XCTestCase {
    private var fixture: TerminalWindowTestFixture?
    private var restored: PseudoTerminal?

    override func setUpWithError() throws {
        try super.setUpWithError()
        try OnscreenTestGate.skipUnlessEnabled()
        try XCTSkipUnless(SpaceProbe.isAvailable, "This macOS lacks the Spaces functions")
        try XCTSkipUnless(SpaceProbe.desktopIDs().count >= 2, "Needs at least two desktops")
        fixture = TerminalWindowTestFixture()
        // The window server puts a new window on a Space only after the app
        // gets back to its runloop, so wait for that before reading it.
        let window = try XCTUnwrap(fixture?.terminal.window)
        let deadline = Date(timeIntervalSinceNow: 5)
        while SpaceProbe.spaceIDs(of: window).count != 1 && Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        XCTAssertEqual(SpaceProbe.spaceIDs(of: window).count, 1, "Precondition: the window is on one Space")
    }

    override func tearDown() {
        restored?.window?.close()
        restored = nil
        fixture?.close()
        fixture = nil
        super.tearDown()
    }

    @MainActor
    func testArrangementRecordsTheSpaceOfTheWindow() throws {
        let terminal = try XCTUnwrap(fixture?.terminal)
        let arrangement = try XCTUnwrap(terminal.arrangement())
        let space = try XCTUnwrap(arrangement[TERMINAL_ARRANGEMENT_SPACE] as? [String: Any])
        let uuid = try XCTUnwrap(space["UUID"] as? String)
        let current = try XCTUnwrap(SpaceProbe.spaceIDs(of: try XCTUnwrap(terminal.window)).first)
        XCTAssertEqual(uuid, SpaceProbe.uuid(ofSpace: current))
    }

    @MainActor
    func testRestoringAnArrangementReturnsTheWindowToItsSpace() throws {
        let terminal = try XCTUnwrap(fixture?.terminal)
        let window = try XCTUnwrap(terminal.window)
        let original = try XCTUnwrap(SpaceProbe.spaceIDs(of: window).first)
        let other = try XCTUnwrap(SpaceProbe.desktopIDs().first { $0 != original })

        // Save the window while it is on another Space, then bring it back here
        // so that only the restore can put the copy there.
        SpaceProbe.move(window, toSpace: other)
        XCTAssertEqual(SpaceProbe.spaceIDs(of: window), [other], "Precondition: the move worked")
        let arrangement = try XCTUnwrap(terminal.arrangement())
        SpaceProbe.move(window, toSpace: original)

        restored = PseudoTerminal(arrangement: arrangement, named: nil, forceOpeningHotKeyWindow: true)
        let copy = try XCTUnwrap(restored?.window)
        iTermController.sharedInstance()?.addTerminalWindow(try XCTUnwrap(restored))

        // The move happens on the next turn of the main runloop.
        let deadline = Date(timeIntervalSinceNow: 5)
        while SpaceProbe.spaceIDs(of: copy) != [other] && Date() < deadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        XCTAssertEqual(SpaceProbe.spaceIDs(of: copy), [other])
    }

    @MainActor
    func testArrangementWithAMissingSpaceLeavesTheWindowAlone() throws {
        let terminal = try XCTUnwrap(fixture?.terminal)
        let window = try XCTUnwrap(terminal.window)
        let before = SpaceProbe.spaceIDs(of: window)
        iTermWindowSpace.move(window, toSpaceFromArrangementValue: ["UUID": "no-such-space"])
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        XCTAssertEqual(SpaceProbe.spaceIDs(of: window), before)
    }
}

/// Reads and changes Spaces with the same private functions the app uses, so the
/// tests check the effect on the window server rather than the app’s bookkeeping.
private enum SpaceProbe {
    private typealias CopyDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias CopySpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias MoveWindows = @convention(c) (Int32, CFArray, UInt64) -> Void
    private typealias MainConnection = @convention(c) () -> Int32

    private static func function<T>(_ name: String, as type: T.Type) -> T? {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else {
            return nil
        }
        return unsafeBitCast(symbol, to: type)
    }

    private static let copyDisplaySpaces = function("CGSCopyManagedDisplaySpaces", as: CopyDisplaySpaces.self)
    private static let copySpacesForWindows = function("CGSCopySpacesForWindows", as: CopySpacesForWindows.self)
    private static let moveWindows = function("CGSMoveWindowsToManagedSpace", as: MoveWindows.self)
    private static let mainConnection = function("CGSMainConnectionID", as: MainConnection.self)

    static var isAvailable: Bool {
        return copyDisplaySpaces != nil && copySpacesForWindows != nil && moveWindows != nil && mainConnection != nil
    }

    private static var desktops: [[String: Any]] {
        guard let copyDisplaySpaces, let mainConnection,
              let displays = copyDisplaySpaces(mainConnection())?.takeRetainedValue() as? [[String: Any]] else {
            return []
        }
        return displays
            .flatMap { ($0["Spaces"] as? [[String: Any]]) ?? [] }
            .filter { ($0["type"] as? Int) == 0 }
    }

    static func desktopIDs() -> [UInt64] {
        return desktops.compactMap { ($0["ManagedSpaceID"] as? NSNumber)?.uint64Value }
    }

    static func uuid(ofSpace id: UInt64) -> String? {
        return desktops.first { ($0["ManagedSpaceID"] as? NSNumber)?.uint64Value == id }?["uuid"] as? String
    }

    static func spaceIDs(of window: NSWindow) -> [UInt64] {
        guard let copySpacesForWindows, let mainConnection,
              let ids = copySpacesForWindows(mainConnection(), 7, [window.windowNumber] as CFArray)?
                .takeRetainedValue() as? [NSNumber] else {
            return []
        }
        return ids.map { $0.uint64Value }
    }

    static func move(_ window: NSWindow, toSpace id: UInt64) {
        guard let moveWindows, let mainConnection else {
            return
        }
        moveWindows(mainConnection(), [window.windowNumber] as CFArray, id)
    }
}
