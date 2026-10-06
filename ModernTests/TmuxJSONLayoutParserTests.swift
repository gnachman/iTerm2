//
//  TmuxJSONLayoutParserTests.swift
//  ModernTests
//
//  JSON (v2) tmux layouts, as tmux next-3.9 sends them to a control client that opted in with
//  `refresh-client -f new-layouts`. The samples below were captured from that tmux.
//

import XCTest
@testable import iTerm2SharedARC

final class TmuxJSONLayoutParserTests: XCTestCase {
    private var parser: TmuxLayoutParser { TmuxLayoutParser.sharedInstance() }

    /// Three tiled panes and two floats, which tmux puts in the node of the active tiled pane.
    private let mixed = #"{"V":2,"L":{"t":"h","w":120,"h":40,"x":0,"y":0,"c":[{"t":"p","w":60,"h":40,"x":0,"y":0,"l":3,"i":0,"I":"%0"},{"t":"v","w":59,"h":40,"x":61,"y":0,"c":[{"t":"p","w":59,"h":20,"x":61,"y":0,"l":2,"i":1,"I":"%1"},{"t":"p","w":59,"h":19,"x":61,"y":21,"l":1,"i":2,"I":"%2"},{"t":"p","w":60,"h":10,"x":4,"y":2,"l":0,"i":3,"z":1,"I":"%3"},{"t":"p","w":60,"h":10,"x":8,"y":4,"a":true,"i":4,"z":0,"I":"%4"}]}]}}"#

    /// The same window after the tiled panes were killed.
    private let floatsOnly = #"{"V":2,"L":{"t":"v","w":120,"h":40,"x":0,"y":0,"c":[{"t":"p","w":60,"h":10,"x":4,"y":2,"l":0,"i":0,"z":1,"I":"%3"},{"t":"p","w":60,"h":10,"x":8,"y":4,"a":true,"i":1,"z":0,"I":"%4"}]}}"#

    /// One float left: the root itself floats.
    private let floatingRoot = #"{"V":2,"L":{"t":"p","w":60,"h":10,"x":8,"y":4,"a":true,"i":0,"z":0,"I":"%4"}}"#

    private let singlePane = #"{"V":2,"L":{"t":"p","w":80,"h":24,"x":0,"y":0,"a":true,"i":0,"I":"%7"}}"#

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

    func testMixedLayoutSplitsTiledAndFloatingPanes() {
        guard let tree = parser.parsedLayout(from: mixed) else {
            XCTFail("Did not parse")
            return
        }
        // The v node keeps only its tiled panes, so the floats do not change the tiled tree.
        XCTAssertEqual(type(tree), LayoutNodeType.vSplitLayoutNode.rawValue, "h means side by side")
        XCTAssertEqual(int(tree, kLayoutDictWidthKey), 120)
        XCTAssertEqual(int(tree, kLayoutDictHeightKey), 40)
        let tiled = children(tree)
        XCTAssertEqual(tiled.count, 2)
        XCTAssertEqual(type(tiled[1]), LayoutNodeType.hSplitLayoutNode.rawValue, "v means stacked")
        XCTAssertEqual(children(tiled[1]).count, 2)

        let floating = floats(tree)
        XCTAssertEqual(floating.map { int($0, kLayoutDictWindowPaneKey) }, [3, 4], "back to front")
        XCTAssertEqual(floating.map { ($0[kLayoutDictZIndexKey as Any] as? NSNumber)?.intValue }, [1, 0])
        XCTAssertEqual(int(floating[1], kLayoutDictXOffsetKey), 8)
        XCTAssertEqual(int(floating[1], kLayoutDictYOffsetKey), 4)
        XCTAssertEqual(int(floating[1], kLayoutDictWidthKey), 60)
        XCTAssertEqual(int(floating[1], kLayoutDictHeightKey), 10)

        XCTAssertEqual(parser.windowPanes(inParseTree: tree as? [AnyHashable: Any]) as? [NSNumber], [0, 1, 2, 3, 4],
                       "tiled panes, then floats")
    }

    func testFloatsOnlyWindowHasNoTiledChildren() {
        guard let tree = parser.parsedLayout(from: floatsOnly) else {
            XCTFail("Did not parse")
            return
        }
        XCTAssertTrue(children(tree).isEmpty)
        XCTAssertEqual(int(tree, kLayoutDictWidthKey), 120, "the window size comes from the node")
        XCTAssertEqual(floats(tree).map { int($0, kLayoutDictWindowPaneKey) }, [3, 4])
    }

    func testAFloatingRootGivesNoWindowSize() {
        guard let tree = parser.parsedLayout(from: floatingRoot) else {
            XCTFail("Did not parse")
            return
        }
        XCTAssertTrue(children(tree).isEmpty)
        XCTAssertNil(tree[kLayoutDictWidthKey as Any], "a float's size is not the window's")
        XCTAssertEqual(floats(tree).map { int($0, kLayoutDictWindowPaneKey) }, [4])
    }

    func testASinglePaneIsWrappedInASplitter() {
        guard let tree = parser.parsedLayout(from: singlePane) else {
            XCTFail("Did not parse")
            return
        }
        XCTAssertEqual(type(tree), LayoutNodeType.vSplitLayoutNode.rawValue)
        XCTAssertEqual(children(tree).count, 1)
        XCTAssertEqual(int(children(tree)[0], kLayoutDictWindowPaneKey), 7)
        XCTAssertEqual(int(tree, kLayoutDictWidthKey), 80)
        XCTAssertTrue(floats(tree).isEmpty)
    }

    func testDepthFirstSearchVisitsFloats() {
        guard let tree = parser.parsedLayout(from: mixed) else {
            XCTFail("Did not parse")
            return
        }
        let found = parser.windowPane(4, inParseTree: tree)
        XCTAssertEqual(found.flatMap { int($0, kLayoutDictZIndexKey) }, 0)
    }

    func testANodeWithOneTiledChildCollapsesAndCoalesces() {
        // An h node holding a tiled pane and a v node of one tiled pane and a float: the v node
        // collapses, leaving two panes side by side.
        let layout = #"{"V":2,"L":{"t":"h","w":100,"h":30,"x":0,"y":0,"c":[{"t":"p","w":50,"h":30,"x":0,"y":0,"i":0,"I":"%1"},{"t":"v","w":49,"h":30,"x":51,"y":0,"c":[{"t":"p","w":49,"h":30,"x":51,"y":0,"i":1,"I":"%2"},{"t":"p","w":20,"h":5,"x":3,"y":3,"i":2,"z":0,"I":"%3"}]}]}}"#
        guard let tree = parser.parsedLayout(from: layout) else {
            XCTFail("Did not parse")
            return
        }
        XCTAssertEqual(children(tree).map { int($0, kLayoutDictWindowPaneKey) }, [1, 2])
    }

    func testZeroSizedCellsAndNegativeOffsetsAreAccepted() {
        let layout = #"{"V":2,"L":{"t":"h","w":80,"h":24,"x":0,"y":0,"c":[{"t":"p","w":80,"h":24,"x":0,"y":0,"i":0,"I":"%1"},{"t":"v","w":0,"h":0,"x":0,"y":0,"c":[{"t":"p","w":20,"h":5,"x":-3,"y":-2,"i":1,"z":0,"I":"%2"},{"t":"p","w":20,"h":5,"x":10,"y":10,"i":2,"z":1,"I":"%3"}]}]}}"#
        guard let tree = parser.parsedLayout(from: layout) else {
            XCTFail("Did not parse")
            return
        }
        XCTAssertEqual(floats(tree).map { int($0, kLayoutDictXOffsetKey) }, [10, -3])
    }

    func testMalformedLayoutsAreRejected() {
        for layout in [#"{"V":3,"L":{"t":"p","w":80,"h":24,"x":0,"y":0,"I":"%1"}}"#,
                       #"{"V":2}"#,
                       #"{"V":2,"L":{"t":"q","w":80,"h":24,"x":0,"y":0,"I":"%1"}}"#,
                       #"{"V":2,"L":{"t":"p","w":80,"h":24,"x":0,"y":0}}"#,
                       #"{"V":2,"L":{"t":"p","w":true,"h":24,"x":0,"y":0,"I":"%1"}}"#,
                       #"{"V":2,"L":{"t":"h","w":80,"h":24,"x":0,"y":0,"c":[]}}"#,
                       #"{"V":2,"L":{"t":"p","w":-1,"h":24,"x":0,"y":0,"I":"%1"}}"#,
                       #"{"V":2,"L":"#] {
            XCTAssertNil(parser.parsedLayout(from: layout), layout)
        }
    }

    func testVersionOneLayoutsStillParse() {
        guard let tree = parser.parsedLayout(from: "b25f,80x24,0,0{40x24,0,0,1,39x24,41,0,2}") else {
            XCTFail("Did not parse")
            return
        }
        XCTAssertEqual(children(tree).count, 2)
        XCTAssertTrue(floats(tree).isEmpty)
    }

    /// With one float left, tmux makes it the layout's root, so the layout lacks the window's size.
    /// The window opener fills it in from list-windows, or the window would be sized to nothing and
    /// the client size it sends would crush the float.
    func testTheWindowOpenerGivesAFloatingRootTheWindowsSize() {
        let opener = TmuxWindowOpener()
        opener.size = NSSize(width: 160, height: 45)
        let selector = NSSelectorFromString("parsedAdjustedLayoutFromString:")
        guard let tree = opener.perform(selector, with: floatingRoot)?.takeUnretainedValue() as? NSDictionary else {
            XCTFail("Did not parse")
            return
        }
        XCTAssertEqual(int(tree, kLayoutDictWidthKey), 160)
        XCTAssertEqual(int(tree, kLayoutDictHeightKey), 45)
        XCTAssertEqual(floats(tree).map { int($0, kLayoutDictWidthKey) }, [60], "the float keeps its own size")
    }
}
