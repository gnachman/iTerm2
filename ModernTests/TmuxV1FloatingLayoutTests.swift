//
//  TmuxV1FloatingLayoutTests.swift
//  ModernTests
//
//  tmux 3.7 has floating panes but no JSON layouts. Its v1 layouts list the floats front to back
//  in a suffix and also leave each one in the tiled tree. The samples were captured from tmux 3.7c.
//

import XCTest
@testable import iTerm2SharedARC

final class TmuxV1FloatingLayoutTests: XCTestCase {
    private var parser: TmuxLayoutParser { TmuxLayoutParser.sharedInstance() }

    /// %0 beside %1 over %2, with floats %3 and %4; %4 is in front.
    private let mixed = "ef18,100x30,0,0{50x30,0,0,0,49x30,51,0[49x15,51,0,1,49x14,51,16,2],30x8,4,2,3,20x5,50,20,4}<20x5,50,20,4,30x8,4,2,3>"

    /// The same window after the tiled panes were killed.
    private let floatsOnly = "ffeb,100x30,0,0{30x8,4,2,3,20x5,50,20,4}<30x8,4,2,3,20x5,50,20,4>"

    private func children(_ node: NSDictionary?) -> [NSDictionary] {
        return node?[kLayoutDictChildrenKey as Any] as? [NSDictionary] ?? []
    }

    private func type(_ node: NSDictionary?) -> Int? {
        return (node?[kLayoutDictNodeType as Any] as? NSNumber)?.intValue
    }

    private func floats(_ tree: NSDictionary?) -> [NSDictionary] {
        return tree?[kLayoutDictFloatingPanesKey as Any] as? [NSDictionary] ?? []
    }

    private func int(_ node: NSDictionary, _ key: String) -> Int32? {
        return (node[key] as? NSString)?.intValue ?? (node[key] as? NSNumber)?.int32Value
    }

    func testFloatsLeaveTheTiledTree() {
        guard let tree = parser.parsedLayout(from: mixed) else {
            XCTFail("Did not parse")
            return
        }
        XCTAssertEqual(int(tree, kLayoutDictWidthKey), 100)
        XCTAssertEqual(int(tree, kLayoutDictHeightKey), 30)
        XCTAssertEqual(type(tree), LayoutNodeType.vSplitLayoutNode.rawValue)
        let tiled = children(tree)
        XCTAssertEqual(tiled.count, 2, "only %0 and the stack of %1 and %2 are tiled")
        XCTAssertEqual(int(tiled[0], kLayoutDictWindowPaneKey), 0)
        XCTAssertEqual(children(tiled[1]).map { int($0, kLayoutDictWindowPaneKey) }, [1, 2])
        XCTAssertEqual(parser.windowPanes(inParseTree: tree as? [AnyHashable: Any]) as? [NSNumber],
                       [0, 1, 2, 3, 4].map { NSNumber(value: $0) },
                       "the floats are still panes of the window")
    }

    func testFloatsAreListedBackToFrontWithTheirCells() {
        guard let tree = parser.parsedLayout(from: mixed) else {
            XCTFail("Did not parse")
            return
        }
        let floating = floats(tree)
        XCTAssertEqual(floating.map { int($0, kLayoutDictWindowPaneKey) }, [3, 4], "back to front")
        XCTAssertEqual(floating.map { ($0[kLayoutDictZIndexKey as Any] as? NSNumber)?.intValue }, [1, 0])
        XCTAssertEqual(int(floating[1], kLayoutDictWidthKey), 20)
        XCTAssertEqual(int(floating[1], kLayoutDictHeightKey), 5)
        XCTAssertEqual(int(floating[1], kLayoutDictXOffsetKey), 50)
        XCTAssertEqual(int(floating[1], kLayoutDictYOffsetKey), 20)
    }

    func testAWindowWithOnlyFloatsHasAnEmptyRootOfTheWindowsSize() {
        guard let tree = parser.parsedLayout(from: floatsOnly) else {
            XCTFail("Did not parse")
            return
        }
        XCTAssertEqual(children(tree).count, 0)
        XCTAssertEqual(int(tree, kLayoutDictWidthKey), 100)
        XCTAssertEqual(int(tree, kLayoutDictHeightKey), 30)
        XCTAssertEqual(floats(tree).map { int($0, kLayoutDictWindowPaneKey) }, [4, 3])
    }

    func testOneTiledPaneLeftIsWrappedInARootSplit() {
        let layout = "abcd,100x30,0,0{50x30,0,0,0,30x8,4,2,3}<30x8,4,2,3>"
        guard let tree = parser.parsedLayout(from: layout) else {
            XCTFail("Did not parse")
            return
        }
        XCTAssertEqual(type(tree), LayoutNodeType.vSplitLayoutNode.rawValue)
        XCTAssertEqual(children(tree).map { int($0, kLayoutDictWindowPaneKey) }, [0])
        XCTAssertEqual(int(tree, kLayoutDictWidthKey), 100)
        XCTAssertEqual(floats(tree).map { int($0, kLayoutDictWindowPaneKey) }, [3])
    }

    func testANegativeOffsetIsAccepted() {
        let layout = "abcd,100x30,0,0{50x30,0,0,0,30x8,-4,-2,3}<30x8,-4,-2,3>"
        guard let tree = parser.parsedLayout(from: layout) else {
            XCTFail("Did not parse")
            return
        }
        XCTAssertEqual(floats(tree).map { int($0, kLayoutDictXOffsetKey) }, [-4])
    }

    func testAMalformedSuffixIsRejected() {
        XCTAssertNil(parser.parsedLayout(from: "abcd,100x30,0,0{50x30,0,0,0,30x8,4,2,3}<30x8,4,2"))
        XCTAssertNil(parser.parsedLayout(from: "abcd,100x30,0,0{50x30,0,0,0,30x8,4,2,3}<>"))
    }

    func testALayoutWithoutFloatsIsUnchanged() {
        guard let tree = parser.parsedLayout(from: "b25d,100x30,0,0{50x30,0,0,0,49x30,51,0,1}") else {
            XCTFail("Did not parse")
            return
        }
        XCTAssertEqual(children(tree).count, 2)
        XCTAssertNil(tree[kLayoutDictFloatingPanesKey as Any])
    }
}
