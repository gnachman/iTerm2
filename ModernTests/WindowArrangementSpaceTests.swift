//
//  WindowArrangementSpaceTests.swift
//  ModernTests
//
//  A saved window arrangement remembers which Space each window was on, and
//  restoring it puts the window back there (gitlab issues 5741 and 11895).
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
        let space = try XCTUnwrap(arrangement[iTermWindowSpace.arrangementKey] as? [String: Any])
        let uuid = try XCTUnwrap(space["UUID"] as? String)
        let current = try XCTUnwrap(SpaceProbe.spaceIDs(of: try XCTUnwrap(terminal.window)).first)
        XCTAssertEqual(uuid, SpaceProbe.uuid(ofSpace: current))
    }

    @MainActor
    func testRestoringAnArrangementReturnsTheWindowToItsSpace() throws {
        let terminal = try XCTUnwrap(fixture?.terminal)
        let window = try XCTUnwrap(terminal.window)
        let original = try XCTUnwrap(SpaceProbe.spaceIDs(of: window).first)
        // The app only moves a window to a desktop on the display it is on.
        guard let other = SpaceProbe.otherDesktop(onDisplayOf: original) else {
            throw XCTSkip("Needs a second desktop on the display the test window opens on")
        }

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

/// Which desktop a saved arrangement value refers to. Pure logic, so these run
/// without putting windows on screen.
final class WindowSpaceDesktopChoiceTests: XCTestCase {
    private typealias Desktop = iTermWindowSpace.Desktop

    private let builtIn = "AAAA0000-0000-0000-0000-000000000001"
    private let external = "BBBB0000-0000-0000-0000-000000000002"

    private var desktops: [Desktop] {
        return [
            Desktop(spaceID: 1, uuid: "U1", displayIdentifier: builtIn, index: 0),
            Desktop(spaceID: 2, uuid: "U2", displayIdentifier: builtIn, index: 1),
            Desktop(spaceID: 3, uuid: "U3", displayIdentifier: builtIn, index: 2),
            Desktop(spaceID: 4, uuid: "U4", displayIdentifier: external, index: 0),
            Desktop(spaceID: 5, uuid: "U5", displayIdentifier: external, index: 1),
        ]
    }

    private func choose(_ value: [String: Any]) -> UInt64? {
        return iTermWindowSpace.desktop(forArrangementValue: value, among: desktops)?.spaceID
    }

    func testSavedValueRoundTrips() {
        for desktop in desktops {
            XCTAssertEqual(choose(iTermWindowSpace.arrangementValue(for: desktop)), desktop.spaceID)
        }
    }

    func testUUIDWinsOverPosition() {
        // The desktop was reordered: its UUID now sits in another position.
        XCTAssertEqual(choose(["UUID": "U3", "Display": builtIn, "Index": 0]), 3)
    }

    func testClosedDesktopFallsBackToSamePosition() {
        // Desktop 3 was closed and a new one made in its place.
        XCTAssertEqual(choose(["UUID": "gone", "Display": builtIn, "Index": 2]), 3)
    }

    func testPositionIsPerDisplay() {
        XCTAssertEqual(choose(["UUID": "gone", "Display": external, "Index": 1]), 5)
    }

    func testDisplayMatchIgnoresCase() {
        XCTAssertEqual(choose(["UUID": "gone", "Display": external.lowercased(), "Index": 0]), 4)
    }

    func testTooFewDesktopsMatchesNothing() {
        XCTAssertNil(choose(["UUID": "gone", "Display": external, "Index": 2]))
    }

    func testMissingDisplayMatchesNothing() {
        XCTAssertNil(choose(["UUID": "gone", "Display": "CCCC0000-0000-0000-0000-000000000003", "Index": 0]))
    }

    func testValueWithOnlyAUUID() {
        XCTAssertEqual(choose(["UUID": "U2"]), 2)
        XCTAssertNil(choose(["UUID": "gone"]))
    }

    private func missing(_ value: [String: Any]) -> iTermWindowSpace.MissingDesktop? {
        return iTermWindowSpace.missingDesktop(forArrangementValue: value, among: desktops)
    }

    func testTooFewDesktopsIsReportedAsMissing() {
        XCTAssertEqual(missing(["UUID": "gone", "Display": external, "Index": 3]),
                       iTermWindowSpace.MissingDesktop(displayIdentifier: external, index: 3))
    }

    func testMissingUsesTheConnectedDisplaysSpelling() {
        XCTAssertEqual(missing(["UUID": "gone", "Display": external.lowercased(), "Index": 2])?.displayIdentifier,
                       external)
    }

    func testExistingDesktopIsNotMissing() {
        XCTAssertNil(missing(["UUID": "gone", "Display": builtIn, "Index": 2]))
        XCTAssertNil(missing(["UUID": "U5", "Display": external, "Index": 9]))
    }

    func testDisconnectedDisplayIsNotMissing() {
        // Adding desktops can't help, so there is nothing to ask the user.
        XCTAssertNil(missing(["UUID": "gone", "Display": "CCCC0000-0000-0000-0000-000000000003", "Index": 5]))
    }

    func testValueWithoutPositionIsNotMissing() {
        XCTAssertNil(missing(["UUID": "gone"]))
    }

    func testEmptyUUIDUsesPosition() {
        let first = Desktop(spaceID: 9, uuid: "", displayIdentifier: builtIn, index: 0)
        let value = iTermWindowSpace.arrangementValue(for: first)
        XCTAssertNil(value["UUID"])
        XCTAssertEqual(iTermWindowSpace.desktop(forArrangementValue: value, among: [first])?.spaceID, 9)
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

    /// The ordinary desktops of each display.
    private static var desktopsByDisplay: [[[String: Any]]] {
        guard let copyDisplaySpaces, let mainConnection,
              let displays = copyDisplaySpaces(mainConnection())?.takeRetainedValue() as? [[String: Any]] else {
            return []
        }
        return displays.map { display in
            ((display["Spaces"] as? [[String: Any]]) ?? []).filter { ($0["type"] as? Int) == 0 }
        }
    }

    private static var desktops: [[String: Any]] {
        return desktopsByDisplay.flatMap { $0 }
    }

    private static func id(of desktop: [String: Any]) -> UInt64? {
        return (desktop["ManagedSpaceID"] as? NSNumber)?.uint64Value
    }

    /// Another ordinary desktop on the same display as the given one.
    static func otherDesktop(onDisplayOf space: UInt64) -> UInt64? {
        let ids = desktopsByDisplay
            .map { $0.compactMap { id(of: $0) } }
            .first { $0.contains(space) } ?? []
        return ids.first { $0 != space }
    }

    static func uuid(ofSpace id: UInt64) -> String? {
        return desktops.first { self.id(of: $0) == id }?["uuid"] as? String
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
