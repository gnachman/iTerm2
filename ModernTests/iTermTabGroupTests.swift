//
//  iTermTabGroupTests.swift
//  iTerm2XCTests
//
//  Created by George Nachman on 8/7/26.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermTabGroupTests: XCTestCase {
    // MARK: - iTermTabGroup arrangement round-trip

    func testArrangementRoundTripsIdentifierNameAndColor() {
        let color = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1.0)
        let group = iTermTabGroup(uniqueIdentifier: "grp-1",
                                  name: "phpvms",
                                  color: color)
        let restored = iTermTabGroup(arrangement: group.arrangement)
        XCTAssertNotNil(restored)
        XCTAssertEqual(restored?.uniqueIdentifier, "grp-1")
        XCTAssertEqual(restored?.name, "phpvms")
        // Compare via the dictionary encoding rather than NSColor
        // equality, which is sensitive to color space identity.
        XCTAssertEqual(restored?.color.dictionaryValue as NSDictionary?,
                       color.dictionaryValue as NSDictionary)
    }

    func testInitFromArrangementFailsWithoutIdentifier() {
        let arr: [String: Any] = ["name": "x",
                                  "color": NSColor.red.dictionaryValue]
        XCTAssertNil(iTermTabGroup(arrangement: arr))
    }

    func testInitFromArrangementFailsWithoutName() {
        let arr: [String: Any] = ["id": "grp-1",
                                  "color": NSColor.red.dictionaryValue]
        XCTAssertNil(iTermTabGroup(arrangement: arr))
    }

    func testInitFromArrangementFallsBackToGrayWhenColorMissing() {
        let arr: [String: Any] = ["id": "grp-1", "name": "x"]
        let group = iTermTabGroup(arrangement: arr)
        XCTAssertNotNil(group)
        XCTAssertEqual(group?.color, .gray)
    }

    func testConvenienceInitMintsUniqueIdentifiers() {
        let a = iTermTabGroup(name: "a", color: .red)
        let b = iTermTabGroup(name: "b", color: .blue)
        XCTAssertFalse(a.uniqueIdentifier.isEmpty)
        XCTAssertNotEqual(a.uniqueIdentifier, b.uniqueIdentifier)
    }

    // MARK: - iTermTabGroupRegistry

    func testRegistryAddLookupRemove() {
        let registry = iTermTabGroupRegistry()
        XCTAssertTrue(registry.isEmpty)
        let group = iTermTabGroup(uniqueIdentifier: "g1", name: "n", color: .red)
        registry.add(group)
        XCTAssertFalse(registry.isEmpty)
        XCTAssertTrue(registry.group(withID: "g1") === group)
        XCTAssertNil(registry.group(withID: "missing"))
        registry.removeGroup(withID: "g1")
        XCTAssertNil(registry.group(withID: "g1"))
        XCTAssertTrue(registry.isEmpty)
    }

    func testRegistryPruneKeepsOnlyInUseGroups() {
        let registry = iTermTabGroupRegistry()
        registry.add(iTermTabGroup(uniqueIdentifier: "keep", name: "k", color: .red))
        registry.add(iTermTabGroup(uniqueIdentifier: "drop", name: "d", color: .blue))
        registry.pruneGroups(keepingIDs: ["keep"])
        XCTAssertNotNil(registry.group(withID: "keep"))
        XCTAssertNil(registry.group(withID: "drop"))
    }

    func testRegistryArrangementRoundTrip() {
        let registry = iTermTabGroupRegistry()
        registry.add(iTermTabGroup(uniqueIdentifier: "g1", name: "one",
                                   color: NSColor(srgbRed: 0.1, green: 0.2, blue: 0.3, alpha: 1)))
        registry.add(iTermTabGroup(uniqueIdentifier: "g2", name: "two",
                                   color: NSColor(srgbRed: 0.4, green: 0.5, blue: 0.6, alpha: 1)))
        let arrangement = registry.arrangement
        XCTAssertEqual(arrangement.count, 2)

        let restored = iTermTabGroupRegistry()
        restored.load(arrangement: arrangement)
        XCTAssertEqual(restored.allGroups.count, 2)
        XCTAssertEqual(restored.group(withID: "g1")?.name, "one")
        XCTAssertEqual(restored.group(withID: "g2")?.name, "two")
    }
}
