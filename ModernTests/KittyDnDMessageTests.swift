//
//  KittyDnDMessageTests.swift
//  iTerm2 ModernTests
//
//  Phase 0 of the Kitty drag-and-drop protocol (OSC 72). See
//  docs/kitty-dnd-design.md. These pin the pure wire-layer parse/serialize
//  behavior of a single, complete OSC 72 message, including the split between
//  plain-text payloads (MIME lists) and base64 payloads (file/image data).
//

import XCTest
@testable import iTerm2SharedARC

final class KittyDnDMessageTests: XCTestCase {
    // MARK: - Parsing

    func testParsesMetadataOnly() {
        let msg = KittyDnDMessage(oscContent: "t=a")
        XCTAssertEqual(msg.type, "a")
        XCTAssertNil(msg.rawPayload)
    }

    func testParsesMultipleKeys() {
        let msg = KittyDnDMessage(oscContent: "t=m:x=3:y=4:X=10:Y=20:o=3")
        XCTAssertEqual(msg.type, "m")
        XCTAssertEqual(msg.intValue("x"), 3)
        XCTAssertEqual(msg.intValue("y"), 4)
        XCTAssertEqual(msg.intValue("X"), 10)
        XCTAssertEqual(msg.intValue("Y"), 20)
        XCTAssertEqual(msg.intValue("o"), 3)
    }

    func testParsesNegativeInt() {
        let msg = KittyDnDMessage(oscContent: "t=P:x=-1")
        XCTAssertEqual(msg.intValue("x"), -1)
    }

    // An explicit empty payload section (trailing ";") is distinct from no
    // payload section at all: the protocol uses empty-payload as a completion
    // signal for t=r.
    func testEmptyPayloadSectionIsDistinctFromNone() {
        let none = KittyDnDMessage(oscContent: "t=r:x=1")
        XCTAssertNil(none.rawPayload)
        XCTAssertNil(none.dataPayload)

        let empty = KittyDnDMessage(oscContent: "t=r:x=1;")
        XCTAssertEqual(empty.rawPayload, "")
        XCTAssertEqual(empty.dataPayload, Data())
    }

    // MIME-list payloads are plain text, not base64.
    func testParsesTextPayload() {
        let msg = KittyDnDMessage(oscContent: "t=m;text/plain text/uri-list")
        XCTAssertEqual(msg.textPayload, "text/plain text/uri-list")
    }

    // Data payloads are base64.
    func testParsesBase64DataPayload() {
        let msg = KittyDnDMessage(oscContent: "t=r:x=1;YWJj")
        XCTAssertEqual(msg.rawPayload, "YWJj")
        XCTAssertEqual(msg.dataPayload, Data("abc".utf8))
    }

    // A payload that is not valid base64 still parses (it may be plain text);
    // asking for dataPayload just returns nil.
    func testInvalidBase64DataPayloadDecodesToNil() {
        let msg = KittyDnDMessage(oscContent: "t=r:x=1;!!!!")
        XCTAssertEqual(msg.rawPayload, "!!!!")
        XCTAssertNil(msg.dataPayload)
    }

    func testUnknownKeysArePreserved() {
        let msg = KittyDnDMessage(oscContent: "t=a:zz=hello")
        XCTAssertEqual(msg.metadata["zz"], "hello")
    }

    // MARK: - Serialization

    func testSerializeContentDeterministicKeyOrder() {
        // t comes first, remaining keys sorted ascending, so output is stable.
        let msg = KittyDnDMessage(metadata: ["o": "3", "t": "m", "x": "3", "y": "4"])
        XCTAssertEqual(msg.serializedContent(), "t=m:o=3:x=3:y=4")
    }

    func testSerializeWithTextPayload() {
        let msg = KittyDnDMessage(metadata: ["t": "m"],
                                  textPayload: "text/plain text/uri-list")
        XCTAssertEqual(msg.serializedContent(), "t=m;text/plain text/uri-list")
    }

    func testSerializeWithDataPayload() {
        let msg = KittyDnDMessage(metadata: ["t": "r", "x": "1"],
                                  dataPayload: Data("abc".utf8))
        XCTAssertEqual(msg.serializedContent(), "t=r:x=1;YWJj")
    }

    func testSerializeWrapsInOSC72AndST() {
        let msg = KittyDnDMessage(metadata: ["t": "a"])
        XCTAssertEqual(msg.serialized(), "\u{1b}]72;t=a\u{1b}\\")
    }

    func testRoundTripDataPayload() {
        let original = KittyDnDMessage(metadata: ["t": "r", "x": "2"],
                                       dataPayload: Data([0, 1, 2, 250, 255]))
        let reparsed = KittyDnDMessage(oscContent: original.serializedContent())
        XCTAssertEqual(reparsed, original)
        XCTAssertEqual(reparsed.dataPayload, Data([0, 1, 2, 250, 255]))
    }

    // MARK: - No-newline invariant (the security argument)

    func testSerializedOutputNeverContainsNewlineOrCarriageReturn() {
        // Payload deliberately contains 0x0a and 0x0d raw bytes; base64 must
        // hide them and the metadata must not introduce any.
        let nasty = Data((0...255).map { UInt8($0) })
        let msg = KittyDnDMessage(metadata: ["t": "r", "x": "1", "m": "0"],
                                  dataPayload: nasty)
        let bytes = Array(msg.serialized().utf8)
        XCTAssertFalse(bytes.contains(0x0a), "serialized output must not contain LF")
        XCTAssertFalse(bytes.contains(0x0d), "serialized output must not contain CR")
    }

    func testMetadataValueNewlinesAreStrippedOnSerialize() {
        let msg = KittyDnDMessage(metadata: ["t": "a", "z": "ab\r\ncd"])
        let bytes = Array(msg.serialized().utf8)
        XCTAssertFalse(bytes.contains(0x0a))
        XCTAssertFalse(bytes.contains(0x0d))
        XCTAssertEqual(msg.serializedContent(), "t=a:z=abcd")
    }

    // A plain-text payload (which could in principle contain a newline) must also
    // be stripped so the invariant holds for all inputs.
    func testTextPayloadNewlinesAreStrippedOnSerialize() {
        let msg = KittyDnDMessage(metadata: ["t": "m"], textPayload: "a\r\nb")
        let bytes = Array(msg.serialized().utf8)
        XCTAssertFalse(bytes.contains(0x0a))
        XCTAssertFalse(bytes.contains(0x0d))
    }
}
