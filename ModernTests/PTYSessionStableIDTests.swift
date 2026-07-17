//
//  PTYSessionStableIDTests.swift
//  iTerm2 ModernTests
//
//  PTYSession.stableID is the reload-durable identity. Unlike guid, which
//  replaceTerminatedShellWithNewInstance rotates on every in-place shell restart
//  (via setGuid:), stableID is minted once and never changes for the life of the
//  object. These tests pin that invariant.
//

import XCTest
@testable import iTerm2SharedARC

final class PTYSessionStableIDTests: XCTestCase {
    func testFreshSessionHasValidStableIDDistinctFromGuid() {
        let s = PTYSession(synthetic: false)!
        XCTAssertTrue(StableSessionID.isValid(s.stableID), "stableID \(s.stableID) not valid")
        XCTAssertNotEqual(s.stableID, s.guid)
    }

    func testDistinctSessionsHaveDistinctStableIDs() {
        let a = PTYSession(synthetic: false)!
        let b = PTYSession(synthetic: false)!
        XCTAssertNotEqual(a.stableID, b.stableID)
    }

    func testStableIDSurvivesGuidRotation() {
        let s = PTYSession(synthetic: false)!
        let originalStableID = s.stableID
        let originalGuid = s.guid
        // Reload rotates the guid through setGuid:. Drive that setter (readwrite
        // in the private header) to prove stableID is untouched by the rotation.
        s.setValue(UUID().uuidString, forKey: "guid")
        XCTAssertNotEqual(s.guid, originalGuid, "guid should have rotated")
        XCTAssertEqual(s.stableID, originalStableID, "stableID must survive the rotation")
    }

    func testStableIDRoundTripsThroughArrangement() {
        let session = PTYSession(synthetic: false)!
        let encoder = iTermMutableDictionaryEncoderAdapter.encoder()
        session.encodeArrangement(withContents: false, encoder: encoder)
        let dict = encoder.mutableDictionary as? [AnyHashable: Any] ?? [:]
        // Encoded under the stable-id key, and the decode-side extractor reads it
        // back (canonical) - so a restored session adopts the same id.
        XCTAssertEqual(dict["Session Stable ID"] as? String, session.stableID)
        XCTAssertEqual(PTYSession.stableID(inArrangement: dict), session.stableID)
    }

    func testStableIDInArrangementMissingOrMalformed() {
        // A pre-feature arrangement (no key) or a corrupted value yields nil, so
        // the restored session keeps its freshly-minted stableID.
        XCTAssertNil(PTYSession.stableID(inArrangement: [:]))
        XCTAssertNil(PTYSession.stableID(inArrangement: ["Session Stable ID": "not-a-stable-id"]))
    }

    func testStableIDInArrangementIgnoresNonStringValue() {
        // A type-corrupted plist (a number or array under the key) must not trap
        // the ObjC->Swift bridge into canonical()'s nonnull String parameter; it
        // falls back to nil so restore keeps the freshly-minted id.
        XCTAssertNil(PTYSession.stableID(inArrangement: ["Session Stable ID": 42]))
        XCTAssertNil(PTYSession.stableID(inArrangement: ["Session Stable ID": ["array"]]))
    }

    func testReferenceLookupHandlesEdgeInputsWithoutCrashing() {
        guard let controller = iTermController.sharedInstance() else {
            XCTFail("no shared controller")
            return
        }
        // Empty, garbage, and a well-formed-but-unregistered id must all resolve
        // to nil without trapping (the dispatcher fronts a nil-tolerant lookup).
        XCTAssertNil(controller.anySession(forReference: ""))
        XCTAssertNil(controller.anySession(forReference: "not-a-real-id"))
        XCTAssertNil(controller.anySession(forReference: StableSessionID.generate()))
        XCTAssertNil(controller.anySession(withStableID: "garbage"))
    }
}
