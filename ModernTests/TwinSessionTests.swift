//
//  TwinSessionTests.swift
//  iTerm2
//
//  Does a twin session, started from a copy of a live session's state and then given
//  the same bytes, stay identical to it? And does it keep quiet?
//

import XCTest
@testable import iTerm2SharedARC

final class TwinSessionTests: XCTestCase {
    private var parents: [iTermHeadlessWindowController] = []
    private let readQueue = DispatchQueue(label: "com.iterm2.TwinSessionTests.read")

    override func tearDown() {
        parents = []
        super.tearDown()
    }

    // MARK: - Fidelity

    func testTwinOfShellSessionStaysIdentical() throws {
        try checkTwinStaysIdentical(recording: try committedRecording("shell"))
    }

    func testTwinOfVimSessionStaysIdentical() throws {
        try checkTwinStaysIdentical(recording: try committedRecording("vim"))
    }

    // A twin that starts while the live session's parser holds the first bytes of an escape
    // sequence, a UTF-8 character, and an OSC string.
    func testTwinStartedInTheMiddleOfASequenceStaysIdentical() throws {
        let sequences: [[UInt8]] = [
            Array("\u{1b}[1;38;2;10;200;30mgreen\u{1b}[0m".utf8),
            Array("日本語".utf8),
            Array("\u{1b}]0;a window title\u{7}after".utf8),
            Array("\u{1b}[?1049h\u{1b}[5;10Halt\u{1b}[?1049l".utf8),
            Array("\u{1b}P+q544e\u{1b}\\tail".utf8),
        ]
        for sequence in sequences {
            let recording = Data(Array("before\r\n".utf8) + sequence + Array("\r\nend".utf8))
            for split in 0...recording.count {
                try checkTwin(recording: recording, startingAt: split, chunkSeed: UInt64(split))
            }
        }
    }

    // MARK: - Side effects

    func testTwinDoesNotPerformSideEffects() throws {
        let live = try makeSession()
        let twin = try makeSession()
        try start(twin, of: live)
        let pasteboardChangeCount = NSPasteboard.general.changeCount

        let bytes = "bell\u{7}" +
            "\u{1b}]9;a notification\u{7}" +
            "\u{1b}]52;c;dHdpbg==\u{7}" +
            "\u{1b}[c" +
            "\u{1b}[6n" +
            "\u{1b}]1337;RequestAttention=yes\u{7}" +
            "\u{1b}]1337;StealFocus\u{7}" +
            "done"
        // Straight into the twin, so that nothing in this test performs them for real.
        read(Data(bytes.utf8), into: twin, chunkSeed: nil)
        settle(live, twin)

        let suppressed = twin.twinSuppressedSideEffects
        XCTAssertEqual(suppressed.count(for: "bell"), 1)
        XCTAssertEqual(suppressed.count(for: "notification"), 1)
        XCTAssertEqual(suppressed.count(for: "clipboard"), 1)
        XCTAssertEqual(suppressed.count(for: "report"), 2)
        XCTAssertEqual(suppressed.count(for: "attention"), 1)
        XCTAssertEqual(suppressed.count(for: "focus"), 1)
        XCTAssertEqual(live.twinSuppressedSideEffects.count, 0)
        XCTAssertEqual(NSPasteboard.general.changeCount, pasteboardChangeCount)
        XCTAssertTrue(twin.screen.compactLineDump().hasPrefix("belldone"))
    }

    // Send/receive mode makes a session show what is typed into it, so the test can see where
    // the text went without a program.
    func testTextTypedInTwinGoesToLiveSession() throws {
        let live = try makeSession()
        let twin = try makeSession()
        read(Data("\u{1b}[12l".utf8), into: live, chunkSeed: nil)
        settle(live)
        try start(twin, of: live)

        twin.writeTask("typed")
        settle(live, twin)

        XCTAssertTrue(live.screen.compactLineDump().hasPrefix("typed"),
                      "The live session did not get the text: \(live.screen.compactLineDump())")
    }

    func testTextTypedInReadOnlyTwinIsDropped() throws {
        let defaults = iTermUserDefaults.userDefaults()
        let key = PTYSessionTwinsAreReadOnlyUserDefaultsKey
        let saved = defaults.object(forKey: key)
        defaults.set(true, forKey: key)
        defer {
            defaults.set(saved, forKey: key)
        }
        let live = try makeSession()
        let twin = try makeSession()
        read(Data("\u{1b}[12l".utf8), into: live, chunkSeed: nil)
        settle(live)
        try start(twin, of: live)

        twin.writeTask("typed")
        settle(live, twin)

        XCTAssertFalse(live.screen.compactLineDump().hasPrefix("typed"))
    }

    func testWindowMenuHasTwinItems() throws {
        let windowMenu = try XCTUnwrap(NSApp.windowsMenu)
        let twinMenu = try XCTUnwrap(windowMenu.items.first { $0.identifier?.rawValue == "Twin" }?.submenu)
        let actions = twinMenu.items.compactMap { $0.action.map { NSStringFromSelector($0) } }
        XCTAssertEqual(actions, ["openTwinOfCurrentWindow:", "toggleTwinsAreReadOnly:"])
    }

    func testTwinStopsWhenItsSourceTerminates() throws {
        let live = try makeSession()
        let twin = try makeSession()
        try start(twin, of: live)
        XCTAssertTrue(live.twin === twin)
        live.terminate()
        XCTAssertNil(live.twin)
        XCTAssertNil(twin.twinSource)
    }

    // MARK: - Checks

    // Starts a twin at many points of the recording. The points are a spread over the whole
    // recording plus every byte offset of a few short runs, so several land inside sequences.
    private func checkTwinStaysIdentical(recording: Data) throws {
        var generator = Generator(seed: UInt64(recording.count))
        var splits = Set<Int>([0, recording.count])
        for _ in 0..<12 {
            splits.insert(generator.next(upTo: recording.count))
        }
        for _ in 0..<3 {
            let start = generator.next(upTo: recording.count - 16)
            splits.formUnion(start..<(start + 16))
        }
        for split in splits.sorted() {
            try checkTwin(recording: recording, startingAt: split, chunkSeed: UInt64(split))
        }

        // A live session with a twin must show what a session without one shows.
        let reference = try makeSession()
        read(recording, into: reference, chunkSeed: 1)
        let live = try makeSession()
        let twin = try makeSession()
        try start(twin, of: live)
        read(recording, into: live, chunkSeed: 2)
        settle(reference, live, twin)
        assertIdentical(reference, live, context: "session without a twin and session with one")
    }

    private func checkTwin(recording: Data, startingAt split: Int, chunkSeed: UInt64) throws {
        let live = try makeSession()
        let twin = try makeSession()
        read(recording.prefix(split), into: live, chunkSeed: chunkSeed)
        // Tokens may still be queued in the live session here, as in real use.
        try start(twin, of: live)
        assertIdentical(live, twin, context: "right after the twin started at byte \(split)")
        read(recording.suffix(from: recording.startIndex + split), into: live, chunkSeed: chunkSeed &+ 1)
        settle(live, twin)
        assertIdentical(live, twin, context: "twin started at byte \(split) of \(recording.count)")
    }

    private func assertIdentical(_ expected: PTYSession,
                                 _ actual: PTYSession,
                                 context: String,
                                 file: StaticString = #filePath,
                                 line: UInt = #line) {
        settle(expected, actual)
        let expectedScreen: VT100Screen = expected.screen
        let actualScreen: VT100Screen = actual.screen
        XCTAssertEqual(actualScreen.compactLineDumpWithHistoryAndContinuationMarks(),
                       expectedScreen.compactLineDumpWithHistoryAndContinuationMarks(),
                       "Text differs: \(context)", file: file, line: line)
        XCTAssertEqual(actualScreen.numberOfLines(), expectedScreen.numberOfLines(),
                       "Line count differs: \(context)", file: file, line: line)
        XCTAssertEqual(actualScreen.cursorX(), expectedScreen.cursorX(),
                       "Cursor column differs: \(context)", file: file, line: line)
        XCTAssertEqual(actualScreen.cursorY(), expectedScreen.cursorY(),
                       "Cursor row differs: \(context)", file: file, line: line)
        let count = min(actualScreen.numberOfLines(), expectedScreen.numberOfLines())
        var differingLines = [Int32]()
        for i in 0..<count {
            let a = actualScreen.screenCharArray(forLine: i)
            let e = expectedScreen.screenCharArray(forLine: i)
            if !a.isEqual(to: e) {
                differingLines.append(i)
            }
        }
        XCTAssertEqual(differingLines, [],
                       "Cells (text, colors or attributes) differ on these lines: \(context)",
                       file: file, line: line)

        let expectedState = screenState(of: expected)
        let actualState = screenState(of: actual)
        for key in ["Terminal State", "Tab Stops", "Showing Primary Grid", "Cursor Visible",
                    "Line Drawing Modes", "Protected Mode"] {
            let e = expectedState[key]
            var a = actualState[key]
            var e2 = e
            if key == "Tab Stops" {
                a = (a as? [NSNumber]).map { NSSet(array: $0) }
                e2 = (e as? [NSNumber]).map { NSSet(array: $0) }
            }
            if !((a as AnyObject?)?.isEqual(e2) ?? (e2 == nil)) {
                XCTFail("\(key) differs: \(context)\n\(describeDifference(e2, a))", file: file, line: line)
            }
        }
    }

    private func describeDifference(_ expected: Any?, _ actual: Any?) -> String {
        guard let e = expected as? [String: Any], let a = actual as? [String: Any] else {
            return "live: \(String(describing: expected))\ntwin: \(String(describing: actual))"
        }
        var lines = [String]()
        for key in Set(e.keys).union(a.keys).sorted() {
            let ev = e[key] as AnyObject?
            let av = a[key] as AnyObject?
            if !(ev?.isEqual(av) ?? (av == nil)) {
                lines.append("  \(key): live=\(String(describing: ev)) twin=\(String(describing: av))")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func screenState(of session: PTYSession) -> [String: Any] {
        let encoder = iTermMutableDictionaryEncoderAdapter.encoder()
        var linesDropped = Int32(0)
        session.screen.encodeContents(encoder, linesDropped: &linesDropped, unlimited: true)
        return encoder.mutableDictionary["Screen State"] as? [String: Any] ?? [:]
    }

    // MARK: - Sessions

    private var repositoryRoot: URL {
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func committedRecording(_ name: String) throws -> Data {
        let url = repositoryRoot.appendingPathComponent("ModernTests/Resources/TwinSessionFixtures/\(name).bin")
        return try Data(contentsOf: url)
    }

    private func makeSession() throws -> PTYSession {
        var profile = try XCTUnwrap(ProfileModel.sharedInstance()?.defaultBookmark())
        // The test host must not beep or post notifications.
        profile[KEY_SILENCE_BELL] = true
        profile[KEY_FLASHING_BELL] = false
        profile[KEY_VISUAL_BELL] = false
        profile[KEY_SEND_BELL_ALERT] = false
        profile[KEY_SEND_TERMINAL_GENERATED_ALERT] = false
        let session = try XCTUnwrap(PTYSession(synthetic: true))
        session.profile = profile
        let frameSize = NSSize(width: 800, height: 500)
        let parent = iTermHeadlessWindowController(frame: NSRect(origin: .zero, size: frameSize))
        parents.append(parent)
        session.setScreenSize(frameSize, parent: parent)
        session.setPreferencesFromAddressBookEntry(profile)
        session.setSize(VT100GridSizeMake(80, 24))
        session.screen.terminalEnabled = true
        return session
    }

    private func start(_ twin: PTYSession,
                       of live: PTYSession,
                       file: StaticString = #filePath,
                       line: UInt = #line) throws {
        let started = expectation(description: "twin started")
        var succeeded = false
        live.startTwin(twin) { ok in
            succeeded = ok
            started.fulfill()
        }
        wait(for: [started], timeout: 30)
        XCTAssertTrue(succeeded, "The twin did not start", file: file, line: line)
    }

    // Gives the session the bytes the way a program's output arrives: off the main queue, through
    // the session's read entry point, in pieces. With a seed the pieces are 1 to 64 bytes long.
    private func read(_ bytes: Data, into session: PTYSession, chunkSeed: UInt64?) {
        guard !bytes.isEmpty else {
            return
        }
        let finished = expectation(description: "read")
        let buffer = [UInt8](bytes)
        readQueue.async {
            var generator = chunkSeed.map { Generator(seed: $0) }
            var offset = 0
            while offset < buffer.count {
                let wanted = generator?.next(upTo: 64) ?? buffer.count
                let length = min(wanted + 1, buffer.count - offset)
                var piece = buffer[offset..<(offset + length)].map { CChar(bitPattern: $0) }
                session.threadedReadTask(&piece, length: Int32(length))
                offset += length
            }
            finished.fulfill()
        }
        wait(for: [finished], timeout: 60)
    }

    // The twin parses on its own queue, so first wait until it has taken every byte.
    private func settle(_ sessions: PTYSession...) {
        let deadline = Date(timeIntervalSinceNow: 60)
        while sessions.contains(where: { $0.twinPendingByteCount > 0 }) && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.001))
        }
        for session in sessions {
            XCTAssertEqual(session.twinPendingByteCount, 0, "The twin did not take all the bytes")
            session.screen.waitForQueuedTokensForTesting()
        }
    }
}

// A fixed sequence of numbers, so every run uses the same split points and piece sizes.
private struct Generator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E3779B97F4A7C15
    }

    mutating func next(upTo bound: Int) -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        guard bound > 0 else {
            return 0
        }
        return Int((state >> 33) % UInt64(bound))
    }
}
