//
//  KittyDnDMessageTests.swift
//  iTerm2 ModernTests
//
//  Phase 0 of the Kitty drag-and-drop protocol (OSC 72). See
//  docs/kitty-dnd-design.md. These pin the pure wire-layer parse/serialize
//  behavior of a single, complete OSC 72 message.
//

import XCTest
@testable import iTerm2SharedARC

final class KittyDnDMessageTests: XCTestCase {
    // MARK: - Parsing

    func testParsesMetadataOnly() {
        let msg = KittyDnDMessage(oscContent: "t=a")
        XCTAssertNotNil(msg)
        XCTAssertEqual(msg?.type, "a")
        XCTAssertNil(msg?.payload)
    }

    func testParsesMultipleKeys() {
        let msg = KittyDnDMessage(oscContent: "t=m:x=3:y=4:X=10:Y=20:o=3")
        XCTAssertEqual(msg?.type, "m")
        XCTAssertEqual(msg?.intValue("x"), 3)
        XCTAssertEqual(msg?.intValue("y"), 4)
        XCTAssertEqual(msg?.intValue("X"), 10)
        XCTAssertEqual(msg?.intValue("Y"), 20)
        XCTAssertEqual(msg?.intValue("o"), 3)
    }

    func testParsesNegativeInt() {
        let msg = KittyDnDMessage(oscContent: "t=P:x=-1")
        XCTAssertEqual(msg?.intValue("x"), -1)
    }

    // An explicit empty payload section (trailing ";") is distinct from no
    // payload section at all: the protocol uses empty-payload as a completion
    // signal for t=r.
    func testEmptyPayloadSectionIsDistinctFromNone() {
        let none = KittyDnDMessage(oscContent: "t=r:x=1")
        XCTAssertNil(none?.payload)

        let empty = KittyDnDMessage(oscContent: "t=r:x=1;")
        XCTAssertEqual(empty?.payload, Data())
    }

    func testParsesBase64Payload() {
        let msg = KittyDnDMessage(oscContent: "t=r:x=1;YWJj")
        XCTAssertEqual(msg?.payload, Data("abc".utf8))
    }

    func testInvalidBase64PayloadFailsToParse() {
        // "!" is not in the base64 alphabet.
        XCTAssertNil(KittyDnDMessage(oscContent: "t=r:x=1;!!!!"))
    }

    func testUnknownKeysArePreserved() {
        let msg = KittyDnDMessage(oscContent: "t=a:zz=hello")
        XCTAssertEqual(msg?.metadata["zz"], "hello")
    }

    // MARK: - Serialization

    func testSerializeContentDeterministicKeyOrder() {
        // t comes first, remaining keys sorted ascending, so output is stable.
        let msg = KittyDnDMessage(metadata: ["o": "3", "t": "m", "x": "3", "y": "4"])
        XCTAssertEqual(msg.serializedContent(), "t=m:o=3:x=3:y=4")
    }

    func testSerializeWithPayload() {
        let msg = KittyDnDMessage(metadata: ["t": "r", "x": "1"],
                                  payload: Data("abc".utf8))
        XCTAssertEqual(msg.serializedContent(), "t=r:x=1;YWJj")
    }

    func testSerializeWrapsInOSC72AndST() {
        let msg = KittyDnDMessage(metadata: ["t": "a"])
        XCTAssertEqual(msg.serialized(), "\u{1b}]72;t=a\u{1b}\\")
    }

    func testRoundTrip() {
        let original = KittyDnDMessage(metadata: ["t": "r", "x": "2"],
                                       payload: Data([0, 1, 2, 250, 255]))
        let reparsed = KittyDnDMessage(oscContent: original.serializedContent())
        XCTAssertEqual(reparsed, original)
    }

    // MARK: - No-newline invariant (the security argument)

    func testSerializedOutputNeverContainsNewlineOrCarriageReturn() {
        // Payload deliberately contains 0x0a and 0x0d raw bytes; base64 must
        // hide them and the metadata must not introduce any.
        let nasty = Data((0...255).map { UInt8($0) })
        let msg = KittyDnDMessage(metadata: ["t": "r", "x": "1", "m": "0"],
                                  payload: nasty)
        let bytes = Array(msg.serialized().utf8)
        XCTAssertFalse(bytes.contains(0x0a), "serialized output must not contain LF")
        XCTAssertFalse(bytes.contains(0x0d), "serialized output must not contain CR")
    }
}
