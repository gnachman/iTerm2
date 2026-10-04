//
//  FindIndicatorClipTests.swift
//  ModernTests
//
//  The find indicator draws a clip of the matched text. TextClipDrawing.drawClip copies each
//  line at the current grid width and blanks the cells before the match with
//  -[ScreenCharArray copyByZeroingVisibleRange:] over 0..<range.start.x. The range is
//  computed when the match is selected but used later, in a dispatch_async, so if the
//  session got narrower in between, start.x is past the end of the line and the zeroing
//  writes past the end of a malloced buffer. Heap corruption crash reports have zeroed
//  free-block headers that match this write.
//

import XCTest
@testable import iTerm2SharedARC

// A ScreenCharArray whose copies are backed by a buffer the test owns, with guard cells after
// the copy's last cell, so a write past the end of the copy is observable instead of corrupting
// the heap.
private final class GuardedCopyScreenCharArray: ScreenCharArray {
    static let guardCount = 8
    static let guardCode: unichar = 0x47  // "G"

    var storage: UnsafeMutablePointer<screen_char_t>?

    // -[ScreenCharArray copyByZeroingRange:] copies with -copy, which calls -copyWithZone:.
    // ScreenCharArray's header doesn't declare it, so replace it by selector.
    @objc(copyWithZone:)
    func guardedCopy(with zone: NSZone?) -> Any {
        let count = Int(length) + Self.guardCount
        let buffer = UnsafeMutablePointer<screen_char_t>.allocate(capacity: count)
        buffer.initialize(repeating: screen_char_t(), count: count)
        for i in 0..<count {
            buffer[i].code = i < Int(length) ? line[i].code : Self.guardCode
        }
        storage = buffer
        return ScreenCharArray(line: buffer, length: length, continuation: continuation)
    }

    // Guard cells that were overwritten.
    var clobberedGuardCells: [Int] {
        guard let storage else {
            return []
        }
        return (0..<Self.guardCount).filter {
            storage[Int(length) + $0].code != Self.guardCode
        }
    }

    deinit {
        storage?.deallocate()
    }
}

// Records the find indicator requests that reach the session, with the screen width when each
// arrives, instead of drawing them.
private final class FindIndicatorSpySession: PTYSession {
    struct Request {
        var range: VT100GridWindowedRange
        var screenWidth: Int32
    }
    var requests = [Request]()

    override func textViewShowFindIndicator(_ range: VT100GridWindowedRange) {
        requests.append(Request(range: range, screenWidth: screen.width()))
    }
}

final class FindIndicatorClipTests: XCTestCase {
    private func screenChars(_ string: String) -> [screen_char_t] {
        var buffer = [screen_char_t](repeating: screen_char_t(), count: string.utf16.count * 3)
        let count = buffer.withUnsafeMutableBufferPointer { umbp -> Int in
            var len = Int32(umbp.count)
            StringToScreenChars(string, umbp.baseAddress!, screen_char_t(), screen_char_t(), &len,
                                false, nil, nil, iTermUnicodeNormalization.none, 9, false, nil)
            return Int(len)
        }
        return Array(buffer[0..<count])
    }

    private func guardedLine(_ string: String, rtl: Bool = false) -> GuardedCopyScreenCharArray {
        let chars = screenChars(string)
        return chars.withUnsafeBufferPointer { ubp in
            let bidi: BidiDisplayInfoObjc? = rtl
                ? BidiDisplayInfoObjc(ScreenCharArray(copyOfLine: ubp.baseAddress!,
                                                      length: Int32(ubp.count),
                                                      continuation: screen_char_t()))
                : nil
            return GuardedCopyScreenCharArray(copyOfLine: ubp.baseAddress!,
                                              length: Int32(ubp.count),
                                              continuation: screen_char_t(),
                                              bidiInfo: bidi)
        }
    }

    // MARK: - Zeroing past the end of the line

    // drawClip zeroes 0..<start.x. With a stale range start.x can exceed the line's length.
    func testZeroingRangePastEndOfLineDoesNotWritePastBuffer() {
        let line = guardedLine("abcdefghij")
        _ = line.copy(byZeroingRange: NSRange(location: 0, length: 14))
        XCTAssertEqual(line.clobberedGuardCells, [])
    }

    func testZeroingVisibleRangePastEndOfLineDoesNotWritePastBuffer() {
        let line = guardedLine("abcdefghij")
        _ = line.copy(byZeroingVisibleRange: NSRange(location: 0, length: 14))
        XCTAssertEqual(line.clobberedGuardCells, [])
    }

    // The bidi path maps each visual column to a logical one. A visual column past the end of
    // the line maps to itself, so it writes past the buffer the same way.
    func testZeroingVisibleRangePastEndOfBidiLineDoesNotWritePastBuffer() {
        let line = guardedLine("\u{05D0}\u{05D1}\u{05D2}\u{05D3}\u{05D4}\u{05D5}\u{05D6}\u{05D7}\u{05D8}\u{05D9}", rtl: true)
        XCTAssertNotNil(line.bidiInfo, "Precondition: the line should have bidi info")
        _ = line.copy(byZeroingVisibleRange: NSRange(location: 0, length: 14))
        XCTAssertEqual(line.clobberedGuardCells, [])
    }

    // MARK: - Stale range

    // Selecting a match schedules the find indicator asynchronously with the range computed at
    // selection time. If the session gets narrower before it runs, the indicator must not be
    // drawn with a range that extends past the new width.
    private func makeSession(width: Int32) throws -> (FindIndicatorSpySession, iTermHeadlessWindowController) {
        let profile = try XCTUnwrap(ProfileModel.sharedInstance()?.defaultBookmark())
        let session = try XCTUnwrap(FindIndicatorSpySession(synthetic: true))
        session.profile = profile
        let frameSize = NSSize(width: 800, height: 400)
        let parent = iTermHeadlessWindowController(frame: NSRect(origin: .zero, size: frameSize))
        session.setScreenSize(frameSize, parent: parent)
        session.setPreferencesFromAddressBookEntry(profile)
        resize(session, width: width)
        return (session, parent)
    }

    private func resize(_ session: PTYSession, width: Int32) {
        session.setSize(VT100GridSizeMake(width, 25))
        session.screen.performBlock(joinedThreads: { _, _, _ in })
        XCTAssertEqual(session.screen.width(), width, "Precondition")
    }

    private func selectMatch(_ session: PTYSession, _ range: VT100GridCoordRange) throws {
        let textview = try XCTUnwrap(session.textview)
        textview.find(onPageSelect: range,
                      logicalWindow: VT100GridRangeMake(0, 0),
                      wrapped: false)
    }

    // Main queue blocks run in order, so this returns after anything already enqueued.
    private func drainMainQueue() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async {
            drained.fulfill()
        }
        wait(for: [drained], timeout: 10)
    }

    func testFindIndicatorIsShownWhenWidthIsUnchanged() throws {
        let (session, parent) = try makeSession(width: 80)
        try selectMatch(session, VT100GridCoordRangeMake(70, 0, 75, 0))
        drainMainQueue()
        XCTAssertEqual(session.requests.count, 1)
        XCTAssertEqual(session.requests.first?.range.coordRange.start.x, 70)
        _ = parent
    }

    func testFindIndicatorRangeIsNotStaleAfterSessionNarrows() throws {
        let (session, parent) = try makeSession(width: 80)
        try selectMatch(session, VT100GridCoordRangeMake(70, 0, 75, 0))

        // The window resizes before the main queue gets to the indicator.
        resize(session, width: 40)
        drainMainQueue()

        for request in session.requests {
            XCTAssertLessThanOrEqual(request.range.coordRange.start.x, request.screenWidth,
                                     "Find indicator requested for \(VT100GridWindowedRangeDescription(request.range)) on a screen \(request.screenWidth) wide")
        }
        _ = parent
    }
}
