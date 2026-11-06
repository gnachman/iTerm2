//
//  ClippingIdentifierTests.swift
//  ModernTests
//
//  Each clipping has a unique ID, which it2 session add-clipping prints so an
//  agent can later remove that clipping with it2 session delete-clipping.
//

import XCTest
@testable import iTerm2SharedARC

final class ClippingIdentifierTests: XCTestCase {
    func testEachClippingGetsADistinctIdentifier() {
        let a = PTYSessionClipping(type: "t", title: "A", detail: "a")
        let b = PTYSessionClipping(type: "t", title: "A", detail: "a")
        XCTAssertFalse(a.identifier.isEmpty)
        XCTAssertNotEqual(a.identifier, b.identifier)
    }

    func testIdentifierSurvivesARoundTripThroughTheArrangement() throws {
        let original = PTYSessionClipping(type: "t", title: "T", detail: "D")
        let restored = try XCTUnwrap(PTYSessionClipping(dictionary: original.dictionaryValue))
        XCTAssertEqual(restored.identifier, original.identifier)
        XCTAssertEqual(restored.type, "t")
        XCTAssertEqual(restored.title, "T")
        XCTAssertEqual(restored.detail, "D")
    }

    // Arrangements saved before clippings had IDs still restore, with fresh IDs.
    func testLegacyDictionaryWithoutIdentifierGetsOne() throws {
        let restored = try XCTUnwrap(PTYSessionClipping(dictionary: ["type": "t", "title": "T", "detail": "D"]))
        XCTAssertFalse(restored.identifier.isEmpty)
    }

    func testAddClippingReturnsTheNewClippingsIdentifier() throws {
        let session = try XCTUnwrap(PTYSession(synthetic: false))
        let id = session.addClipping(type: "t", title: "T", detail: "D")
        XCTAssertEqual(session.clippings.map(\.identifier), [id])
    }

    func testDeleteClippingRemovesOnlyTheNamedClipping() throws {
        let session = try XCTUnwrap(PTYSession(synthetic: false))
        let first = session.addClipping(type: "t", title: "1", detail: "")
        let second = session.addClipping(type: "t", title: "2", detail: "")
        let third = session.addClipping(type: "t", title: "3", detail: "")
        XCTAssertTrue(session.deleteClipping(identifier: second))
        XCTAssertEqual(session.clippings.map(\.identifier), [first, third])
    }

    func testDeletingAnUnknownIdentifierChangesNothing() throws {
        let session = try XCTUnwrap(PTYSession(synthetic: false))
        let id = session.addClipping(type: "t", title: "T", detail: "D")
        XCTAssertFalse(session.deleteClipping(identifier: "no-such-clipping"))
        XCTAssertEqual(session.clippings.map(\.identifier), [id])
    }

    // Archived clippings are history; only the live list is edited.
    func testArchivedClippingsAreNotDeleted() throws {
        let session = try XCTUnwrap(PTYSession(synthetic: false))
        let id = session.addClipping(type: "t", title: "T", detail: "D")
        session.archiveClippings()
        XCTAssertFalse(session.deleteClipping(identifier: id))
        XCTAssertEqual(session.clippingsArchive.map { $0.map(\.identifier) }, [[id]])
    }
}
