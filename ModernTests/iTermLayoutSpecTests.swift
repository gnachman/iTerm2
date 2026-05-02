//
//  iTermLayoutSpecTests.swift
//  ModernTests
//
//  TDD-driven tests for LayoutSpec — the typed-Swift representation of
//  the JSON spec that flows through the layout-application API. Covers
//  parsing and structural validation rules.
//

import XCTest
@testable import iTerm2SharedARC

final class iTermLayoutSpecTests: XCTestCase {

    // MARK: - Parsing: minimal shapes

    func testParseSingleTabWithSessionLeaf() throws {
        let json: [String: Any] = [
            "tabs": [
                [
                    "tab_id": "t1",
                    "root":   ["session_id": "s1"],
                ],
            ],
        ]
        let spec = try LayoutSpec.parse(json)
        XCTAssertEqual(spec.tabs.count, 1)
        XCTAssertEqual(spec.tabs[0].tabID, "t1")
        guard case .session(let guid) = spec.tabs[0].root else {
            XCTFail("expected session leaf")
            return
        }
        XCTAssertEqual(guid, "s1")
    }

    func testParseSplitterWithTwoSessions() throws {
        let json: [String: Any] = [
            "tabs": [
                [
                    "tab_id": "t1",
                    "root": [
                        "vertical": true,
                        "children": [
                            ["session_id": "a"],
                            ["session_id": "b"],
                        ],
                    ],
                ],
            ],
        ]
        let spec = try LayoutSpec.parse(json)
        guard case .splitter(let vertical, let children) = spec.tabs[0].root else {
            XCTFail("expected splitter")
            return
        }
        XCTAssertTrue(vertical)
        XCTAssertEqual(children.count, 2)
    }

    func testParseNewSessionLeaf() throws {
        let json: [String: Any] = [
            "tabs": [
                [
                    "tab_id": "t1",
                    "root": [
                        "vertical": true,
                        "children": [
                            ["session_id": "a"],
                            ["new_session": ["profile": "P1"]],
                        ],
                    ],
                ],
            ],
        ]
        let spec = try LayoutSpec.parse(json)
        guard case .splitter(_, let children) = spec.tabs[0].root else {
            XCTFail("expected splitter"); return
        }
        guard case .newSession(let info) = children[1] else {
            XCTFail("expected new_session leaf"); return
        }
        XCTAssertEqual(info.profileGUID, "P1")
    }

    func testParseNewTabsAndNewWindowsAndCloseLists() throws {
        let json: [String: Any] = [
            "tabs": [
                ["tab_id": "t1", "root": ["session_id": "s1"]],
            ],
            "new_tabs": [
                [
                    "window_id": "w1",
                    "index": 0,
                    "root": ["session_id": "s2"],
                ],
            ],
            "new_windows": [
                [
                    "profile": "P1",
                    "root": ["session_id": "s3"],
                ],
            ],
            "close_sessions": ["s9"],
            "close_tabs": ["t9"],
            "close_windows": ["w9"],
        ]
        let spec = try LayoutSpec.parse(json)
        XCTAssertEqual(spec.newTabs.count, 1)
        XCTAssertEqual(spec.newTabs[0].windowID, "w1")
        XCTAssertEqual(spec.newTabs[0].index, 0)
        XCTAssertEqual(spec.newWindows.count, 1)
        XCTAssertEqual(spec.newWindows[0].profileGUID, "P1")
        XCTAssertEqual(spec.closeSessions, ["s9"])
        XCTAssertEqual(spec.closeTabs, ["t9"])
        XCTAssertEqual(spec.closeWindows, ["w9"])
    }

    // MARK: - Parsing errors

    func testEmptyDictHasNoChanges() throws {
        let spec = try LayoutSpec.parse([:])
        XCTAssertTrue(spec.tabs.isEmpty)
        XCTAssertTrue(spec.newTabs.isEmpty)
        XCTAssertTrue(spec.newWindows.isEmpty)
        XCTAssertTrue(spec.closeSessions.isEmpty)
    }

    func testTabWithoutTabIDFails() {
        let json: [String: Any] = [
            "tabs": [["root": ["session_id": "s1"]]],
        ]
        XCTAssertThrowsError(try LayoutSpec.parse(json))
    }

    func testTabWithoutRootFails() {
        let json: [String: Any] = [
            "tabs": [["tab_id": "t1"]],
        ]
        XCTAssertThrowsError(try LayoutSpec.parse(json))
    }

    func testUnknownLeafKindFails() {
        let json: [String: Any] = [
            "tabs": [
                ["tab_id": "t1", "root": ["unknown_key": "x"]],
            ],
        ]
        XCTAssertThrowsError(try LayoutSpec.parse(json))
    }

    func testNewSessionWithoutProfileFails() {
        let json: [String: Any] = [
            "tabs": [
                ["tab_id": "t1", "root": ["new_session": [:]]],
            ],
        ]
        XCTAssertThrowsError(try LayoutSpec.parse(json))
    }

    func testSplitterMissingChildrenFails() {
        let json: [String: Any] = [
            "tabs": [
                ["tab_id": "t1", "root": ["vertical": true]],
            ],
        ]
        XCTAssertThrowsError(try LayoutSpec.parse(json))
    }
}
