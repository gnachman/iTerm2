//
//  ScreenLineBufferNullabilityTests.swift
//  ModernTests
//
//  Documents the nullability claims in sources/VT100Screen, sources/LineBuffer
//  and iTermMetadata.h that the nullability sanitizer found false (unit H2 of
//  docs/swift-migration/nullability-triage.md). The code accepts or produces
//  nil by design; these tests pin what Swift sees.
//
//  A class-typed nil that Swift held as non-optional reads as nil once stored
//  in an optional, so the run-time checks below would also pass against the
//  old claims. The conditional bindings are what pin the claims: `if let` and
//  `guard let` compile only on an optional, and passing nil compiles only to an
//  optional parameter.
//

import XCTest
@testable import iTerm2SharedARC

final class LineBufferNullabilityTests: XCTestCase {
    // -[iTermLineBlockArray lastBlock] and -firstBlock return lastObject and
    // firstObject, nil for an empty array.
    func testEmptyBlockArrayHasNoFirstOrLastBlock() {
        let blocks = iTermLineBlockArray()
        if let block = blocks.lastBlock {
            XCTFail("Unexpected last block \(block)")
        }
        if let block = blocks.firstBlock {
            XCTFail("Unexpected first block \(block)")
        }
    }

    func testBlockArrayWithABlockHasIt() throws {
        let blocks = iTermLineBlockArray()
        let block = LineBlock(rawBufferSize: 16, absoluteBlockNumber: 0)
        blocks.addBlock(block)
        XCTAssertTrue(try XCTUnwrap(blocks.lastBlock) === block)
        XCTAssertTrue(try XCTUnwrap(blocks.firstBlock) === block)
    }

    // -[LineBlockMetadataArray setLastExternalAttributeIndex:] only stores the
    // index, so nil clears it.
    func testSettingANilExternalAttributeIndexClearsIt() {
        let array = LineBlockMetadataArray(capacity: 1, useDWCCache: false)
        array.increaseCapacity(to: 1)
        array.append(iTermMetadataMakeImmutable(iTermMetadataDefault()), continuation: screen_char_t())
        array.setLast(iTermExternalAttributeIndex())
        XCTAssertNotNil(iTermImmutableMetadataGetExternalAttributesIndex(array.immutableLineMetadata(at: 0)))

        let none: iTermExternalAttributeIndex? = nil
        array.setLast(none)
        XCTAssertNil(iTermImmutableMetadataGetExternalAttributesIndex(array.immutableLineMetadata(at: 0)))
    }

    // iTermMetadataInitFromArray() begins with array.count < 2 and then
    // initializes defaults, which a saved line without metadata relies on.
    func testMetadataFromNoArrayIsTheDefault() {
        var metadata = iTermMetadataDefault()
        metadata.timestamp = 123
        let array: [Any]? = nil
        iTermMetadataInitFromArray(&metadata, array)
        XCTAssertEqual(metadata.timestamp, 0)
        XCTAssertEqual(metadata.lineAttribute, .singleWidth)
        XCTAssertNil(iTermMetadataGetExternalAttributesIndex(metadata))
        iTermMetadataRelease(metadata)
    }
}

final class ScreenNullabilityTests: XCTestCase {
    // A screen without a delegate makes every joined block pass nil to
    // -[VT100ScreenDelegate screenRestoreState:] (the unclear triage row
    // VT100ScreenDelegate.h:524), which the nullability sanitizer reports. A
    // fake delegate avoids that, as in PTYTextViewTextReplacementCountTests.
    private var session: FakeSession!

    private func makeScreen() -> VT100Screen {
        session = FakeSession()
        let screen = VT100Screen()
        session.screen = screen
        screen.delegate = session
        return screen
    }

    // -[VT100Screen namedMarks] returns the main-thread state's named marks,
    // nil until a named mark has been synchronized to it.
    func testNamedMarksOfANewScreenAreNil() {
        let screen = makeScreen()
        if let marks = screen.namedMarks() {
            XCTFail("Unexpected named marks \(marks)")
        }
    }

    // -[VT100ScreenState bidiInfoForLine:] returns nil for a negative line.
    func testBidiInfoForANegativeLineIsNil() {
        let screen = makeScreen()
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            if let info = mutableState.bidiInfo(forLine: -1) {
                XCTFail("Unexpected bidi info \(info)")
            }
        })
    }

    // -[VT100ScreenState rangeOfBlockWithID:] and -blockMarkWithID: look the
    // ID up in a dictionary. A nil ID would reach -[NSDictionary
    // objectForKeyedSubscript:], whose parameter Apple declares nonnull, and
    // the nullability sanitizer would report it, so the optional parameters
    // are pinned at compile time with a non-nil String?.
    func testBlockLookupsTakeAnOptionalID() {
        let screen = makeScreen()
        let blockID: String? = "no-such-block"
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            XCTAssertNil(mutableState.blockMark(withID: blockID))
            let range = mutableState.rangeOfBlock(withID: blockID)
            XCTAssertEqual(range.start.x, -1)
            XCTAssertEqual(range.start.y, -1)
        })
    }

    // -[VT100ScreenMutableState setSize:delegate:] and the five-argument
    // variant only message the delegate and the selection, and the resize
    // tests the delegate before it uses it, so a screen without a delegate
    // resizes.
    func testResizingWithoutADelegateOrSelection() {
        let screen = makeScreen()
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.setSize(VT100GridSizeMake(20, 5), delegate: nil)
            XCTAssertEqual(mutableState.width, 20)
            XCTAssertEqual(mutableState.height, 5)
            mutableState.setSize(VT100GridSizeMake(30, 6),
                                 visibleLines: VT100GridRangeMake(0, 6),
                                 selection: nil,
                                 hasView: false,
                                 delegate: nil)
            XCTAssertEqual(mutableState.width, 30)
            XCTAssertEqual(mutableState.height, 6)
        })
    }

    // -appendScreenChars:... forwards the index to code that already receives
    // nil for text without external attributes.
    func testAppendingScreenCharsWithoutExternalAttributes() {
        let screen = makeScreen()
        screen.performBlock(joinedThreads: { _, mutableState, _ in
            mutableState.setSize(VT100GridSizeMake(10, 3), delegate: nil)
            var continuation = screen_char_t()
            continuation.code = unichar(EOL_HARD)
            var line = screenCharArrayWithDefaultStyle("ab", eol: EOL_HARD)
            let none: iTermExternalAttributeIndexReading? = nil
            mutableState.appendScreenChars(line.line,
                                           length: line.length,
                                           externalAttributeIndex: none,
                                           continuation: continuation,
                                           rtlFound: false,
                                           imageFound: false)
            line = screenCharArrayWithDefaultStyle("cd", eol: EOL_HARD)
            mutableState.appendScreenChars(line.line,
                                           length: line.length,
                                           externalAttributeIndex: none,
                                           continuation: continuation,
                                           rtlFound: false,
                                           imageFound: false,
                                           lineAttribute: .singleWidth)
            XCTAssertEqual(mutableState.currentGrid.screenCharArray(atLine: 0)?.stringValue, "ab")
            XCTAssertEqual(mutableState.currentGrid.screenCharArray(atLine: 1)?.stringValue, "cd")
        })
    }
}

final class ScreenDelegateNullabilityTests: XCTestCase {
    // -[PTYSession screenSSHLocation] describes the SSH conductor's identity,
    // nil for a session that is not in an SSH session. Building a PTYSession
    // here would trip the unrelated sanitizer report at
    // VT100ScreenMutableState.m:7176 (see ScreenNullabilityTests), so this pins
    // the requirement's type instead: a conformer may answer nil, and a reader
    // through the protocol gets an optional.
    private final class NoSSHDelegate: FakeSession {
        override func screenSSHLocation() -> String? {
            return nil
        }
    }

    func testSSHLocationIsOptional() {
        let delegate: VT100ScreenDelegate = NoSSHDelegate()
        if let location = delegate.screenSSHLocation() {
            XCTFail("Unexpected location \(location)")
        }
    }
}
