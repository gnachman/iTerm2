//
//  SessionArchivePropertyListTests.swift
//  iTerm2
//
//  Created by George Nachman on 10/15/26.
//

import XCTest
@testable import iTerm2SharedARC

// Session archives are written as property lists, which only allow string
// dictionary keys and a few value types. Hyperlinks (NSNumber-keyed) and bidi
// info (NSValue) used to break them, and the failure produced an empty archive
// while reporting success, both from Save Archive of Current Session and when
// a session with archiving turned on was closed. Issue 13143.
@MainActor
final class SessionArchivePropertyListTests: XCTestCase {
    private let url = URL(string: "https://example.com/archived")!
    private var directory: URL!
    // Keeps the session's parent alive for the duration of a test.
    private var parent: iTermHeadlessWindowController?

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionArchivePropertyListTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        parent = nil
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeSession() throws -> PTYSession {
        var profile = try XCTUnwrap(ProfileModel.sharedInstance()?.defaultBookmark())
        profile[KEY_ARCHIVEDIR] = directory.path
        let session = try XCTUnwrap(PTYSession(synthetic: true))
        session.profile = profile
        let frameSize = NSSize(width: 800, height: 400)
        let parent = iTermHeadlessWindowController(frame: NSRect(origin: .zero, size: frameSize))
        self.parent = parent
        session.setScreenSize(frameSize, parent: parent)
        session.setPreferencesFromAddressBookEntry(profile)
        session.setSize(VT100GridSizeMake(80, 25))
        return session
    }

    // A session with a hyperlink on part of a line that has scrolled into
    // the line buffer and another on the visible grid, so both encoders are
    // exercised.
    private func makeSessionWithHyperlinks() throws -> PTYSession {
        let session = try makeSession()
        let link = "before \u{1b}]8;;\(url.absoluteString)\u{1b}\\LINK\u{1b}]8;;\u{1b}\\ after\r\n"
        let filler = String(repeating: "filler\r\n", count: 40)
        feed(session, link + filler + link)
        XCTAssertGreaterThan(session.screen.numberOfScrollbackLines(), 0,
                             "Precondition: the first link should be in scrollback")
        return session
    }

    // Runs the bytes through the real parser and executes the tokens on the
    // terminal synchronously.
    private func feed(_ session: PTYSession, _ string: String) {
        let bytes = Array(string.utf8)
        session.screen.performBlock(joinedThreads: { _, mutableState, _ in
            // A real session enables the terminal when its task starts.
            mutableState.terminalEnabled = true
            guard let terminal = mutableState.terminal else {
                XCTFail("No terminal")
                return
            }
            let parser = VT100Parser()
            parser.encoding = String.Encoding.utf8.rawValue
            bytes.withUnsafeBufferPointer { buf in
                parser.putStreamData(buf.baseAddress, length: Int32(buf.count))
            }
            var vector = CVector()
            CVectorCreate(&vector, 100)
            _ = parser.addParsedTokens(to: &vector)
            for i in 0..<CVectorCount(&vector) {
                terminal.execute(CVectorGetObject(&vector, i) as! VT100Token)
            }
            CVectorDestroy(&vector)
        })
        session.screen.waitForQueuedTokensForTesting()
    }

    // Counts the external attributes anywhere in a property list whose URL is
    // the one the test printed. Doesn't depend on the arrangement's layout.
    private func countHyperlinks(in object: Any) -> Int {
        if let array = object as? [Any] {
            return array.reduce(0) { $0 + countHyperlinks(in: $1) }
        }
        guard let dict = object as? [AnyHashable: Any] else {
            return 0
        }
        let here = (iTermExternalAttribute(dictionary: dict)?.url?.url == url) ? 1 : 0
        return dict.values.reduce(here) { $0 + countHyperlinks(in: $1) }
    }

    private func assertArchiveContainsHyperlinks(at path: String,
                                                 file: StaticString = #filePath,
                                                 line: UInt = #line) throws {
        // This is how Archives > Restore Archive reads the file.
        let archive = try XCTUnwrap(NSDictionary(contentsOfFile: path),
                                    "Archive is missing or unreadable",
                                    file: file, line: line)
        // One link from the line buffer, one from the grid. Each cell of a
        // link may be encoded separately, so only require at least two.
        XCTAssertGreaterThanOrEqual(countHyperlinks(in: archive), 2, file: file, line: line)
    }

    // Session > Save Archive of Current Session…
    func testSavingArchiveOfSessionWithHyperlinksWritesFile() throws {
        let session = try makeSessionWithHyperlinks()
        let path = directory.appendingPathComponent("manual.itermarchive").path

        XCTAssertTrue(session.saveArchive(to: iTermSavePanelItem(filename: path, host: .localhost),
                                          term: nil))
        try assertArchiveContainsHyperlinks(at: path)
    }

    // The profile setting that archives a session when it closes.
    func testAutomaticArchiveOfSessionWithHyperlinksWritesFile() throws {
        let session = try makeSessionWithHyperlinks()

        let path = try XCTUnwrap(session.saveArchive(), "No archive was written")
        XCTAssertTrue(path.hasPrefix(directory.path))
        try assertArchiveContainsHyperlinks(at: path)
    }

    // Right-to-left text, with bidi support on, scrolled into the line buffer
    // and on the visible grid.
    func testArchiveOfSessionWithRightToLeftTextWritesFile() throws {
        let savedBidi = iTermPreferences.bool(forKey: kPreferenceKeyBidi)
        setBidiPreference(true)
        defer { setBidiPreference(savedBidi) }

        let session = try makeSession()
        let rtl = "abc (\u{05D0}\u{05D1}\u{05D2}) def\r\n"
        feed(session, rtl + String(repeating: "filler\r\n", count: 40) + rtl)
        XCTAssertGreaterThan(session.screen.numberOfScrollbackLines(), 0, "Precondition")
        let path = directory.appendingPathComponent("rtl.itermarchive").path

        XCTAssertTrue(session.saveArchive(to: iTermSavePanelItem(filename: path, host: .localhost),
                                          term: nil))
        XCTAssertNotNil(NSDictionary(contentsOfFile: path), "Archive is missing or unreadable")
    }

    // When the arrangement can't be serialized, saving must report failure
    // and leave no file behind instead of writing an empty archive.
    func testArchiveThatCannotBeSerializedReportsFailure() throws {
        let session = try makeSession()
        // A script can store any value in a user variable. A URL isn't a
        // property-list type.
        session.genericScope.setValue(NSURL(string: "https://example.com")!,
                                        forVariableNamed: "user.notAPropertyList")
        let path = directory.appendingPathComponent("bad.itermarchive").path

        XCTAssertFalse(session.saveArchive(to: iTermSavePanelItem(filename: path, host: .localhost),
                                           term: nil))
        XCTAssertNil(session.saveArchive())
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
    }

    // Setting a preference refreshes its cached value synchronously.
    private func setBidiPreference(_ enabled: Bool) {
        iTermPreferences.setBool(enabled, forKey: kPreferenceKeyBidi)
        XCTAssertEqual(iTermPreferences.bidiEnabled(), enabled, "Precondition")
    }
}
