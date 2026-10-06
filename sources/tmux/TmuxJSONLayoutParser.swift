//
//  TmuxJSONLayoutParser.swift
//  iTerm2SharedARC
//
//  Parses the JSON (v2) window layouts that tmux sends a control client that opted in with
//  `refresh-client -f new-layouts`, such as
//
//    {"V":2,"L":{"t":"h","w":120,"h":40,"x":0,"y":0,"c":[
//      {"t":"p","w":60,"h":40,"x":0,"y":0,"i":0,"I":"%0"},
//      {"t":"p","w":59,"h":40,"x":61,"y":0,"i":1,"I":"%1"},
//      {"t":"p","w":60,"h":10,"x":4,"y":2,"a":true,"i":2,"z":0,"I":"%2"}]}}
//
//  A cell's "t" is "p" for a pane, "h" for side by side children and "v" for stacked children.
//  A pane with a "z" key floats; z = 0 is the front. Floats are mixed in with tiled siblings, the
//  root can be a float, and a node can hold only floats.
//
//  The result has the dictionary shape TmuxLayoutParser makes from a v1 layout, so existing code
//  reads the tiled part unchanged. Floats are taken out of the tree and listed back to front under
//  kLayoutDictFloatingPanesKey on the root. A node left with one child is replaced by that child,
//  and one left with none is dropped, so a window with only floats has a root with no children.
//  Cells may have zero width or height: tmux can leave a node at 0x0, and that must not end the
//  connection.
//

import Foundation

@objc(iTermTmuxJSONLayoutParser)
final class TmuxJSONLayoutParser: NSObject {
    private struct Malformed: Error {
        let reason: String
    }

    /// Whether the layout is in the JSON format rather than v1, which begins with a checksum.
    @objc(isJSONLayout:)
    static func isJSONLayout(_ layout: String) -> Bool {
        return layout.hasPrefix("{")
    }

    /// The parse tree, or nil if the layout is malformed. The tree is not coalesced.
    @objc(parsedLayoutFromString:)
    static func parsedLayout(from layout: String) -> NSMutableDictionary? {
        do {
            return try parse(layout)
        } catch let error as Malformed {
            DLog("Malformed JSON layout (\(error.reason)): \(layout)")
            return nil
        } catch {
            DLog("Malformed JSON layout (\(error)): \(layout)")
            return nil
        }
    }

    private static func parse(_ layout: String) throws -> NSMutableDictionary {
        guard let data = layout.data(using: .utf8),
              let top = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Malformed(reason: "not an object")
        }
        guard let version = integer(top["V"]), version == 2 else {
            throw Malformed(reason: "unsupported version")
        }
        guard let rootCell = top["L"] as? [String: Any] else {
            throw Malformed(reason: "no root cell")
        }
        var floats = [(z: Int, leaf: NSMutableDictionary)]()
        let tiled = try node(for: rootCell, floats: &floats)

        let root: NSMutableDictionary
        if let tiled, (tiled[kLayoutDictNodeType] as? NSNumber)?.intValue != LayoutNodeType.leafLayoutNode.rawValue {
            root = tiled
        } else {
            // The root is always a splitter, as for v1 layouts. Wrap a lone pane in a do-nothing
            // one, and give a window with only floats one with no children.
            root = NSMutableDictionary()
            root[kLayoutDictNodeType] = NSNumber(value: LayoutNodeType.vSplitLayoutNode.rawValue)
            root[kLayoutDictChildrenKey] = tiled.map { [$0] } ?? []
        }
        let rootIsFloating = rootCell["z"] != nil
        if !rootIsFloating {
            // A floating root's size is the float's, not the window's.
            root[kLayoutDictWidthKey] = NSNumber(value: try dimension(rootCell, "w"))
            root[kLayoutDictHeightKey] = NSNumber(value: try dimension(rootCell, "h"))
        }
        // Back to front.
        root[kLayoutDictFloatingPanesKey] = floats.sorted { $0.z > $1.z }.map { $0.leaf }
        return root
    }

    /// The tiled node for a cell, or nil if it holds only floats. Floats are added to `floats`.
    private static func node(for cell: [String: Any],
                             floats: inout [(z: Int, leaf: NSMutableDictionary)]) throws -> NSMutableDictionary? {
        guard let type = cell["t"] as? String else {
            throw Malformed(reason: "cell has no type")
        }
        switch type {
        case "p":
            let leaf = try self.leaf(for: cell)
            if cell["z"] != nil {
                guard let z = integer(cell["z"]), z >= 0 else {
                    throw Malformed(reason: "bad z-index")
                }
                leaf[kLayoutDictZIndexKey] = NSNumber(value: z)
                floats.append((z: z, leaf: leaf))
                return nil
            }
            return leaf
        case "h", "v":
            guard let cells = cell["c"] as? [[String: Any]], !cells.isEmpty else {
                throw Malformed(reason: "node has no children")
            }
            let children = try cells.compactMap { try node(for: $0, floats: &floats) }
            switch children.count {
            case 0:
                return nil
            case 1:
                return children[0]
            default:
                // "h" lays children out side by side, which v1 writes with braces.
                let nodeType: LayoutNodeType = (type == "h") ? .vSplitLayoutNode : .hSplitLayoutNode
                let result = NSMutableDictionary()
                result[kLayoutDictNodeType] = NSNumber(value: nodeType.rawValue)
                result[kLayoutDictChildrenKey] = NSMutableArray(array: children)
                return result
            }
        default:
            throw Malformed(reason: "unknown cell type \(type)")
        }
    }

    private static func leaf(for cell: [String: Any]) throws -> NSMutableDictionary {
        guard let paneID = cell["I"] as? String,
              paneID.hasPrefix("%"),
              let windowPane = Int(paneID.dropFirst()) else {
            throw Malformed(reason: "pane has no ID")
        }
        let leaf = NSMutableDictionary()
        leaf[kLayoutDictNodeType] = NSNumber(value: LayoutNodeType.leafLayoutNode.rawValue)
        // Strings, as the v1 parser makes them. Readers use -intValue.
        leaf[kLayoutDictWidthKey] = String(try dimension(cell, "w"))
        leaf[kLayoutDictHeightKey] = String(try dimension(cell, "h"))
        leaf[kLayoutDictXOffsetKey] = String(try offset(cell, "x"))
        leaf[kLayoutDictYOffsetKey] = String(try offset(cell, "y"))
        leaf[kLayoutDictWindowPaneKey] = NSNumber(value: windowPane)
        return leaf
    }

    private static func dimension(_ cell: [String: Any], _ key: String) throws -> Int {
        guard let value = integer(cell[key]), value >= 0 else {
            throw Malformed(reason: "bad \(key)")
        }
        return value
    }

    /// Offsets can be negative: tmux leaves floats partly outside the window.
    private static func offset(_ cell: [String: Any], _ key: String) throws -> Int {
        guard let value = integer(cell[key]) else {
            throw Malformed(reason: "bad \(key)")
        }
        return value
    }

    /// An integer from JSON, refusing booleans, which NSJSONSerialization also gives as NSNumber.
    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue == number.doubleValue.rounded() else {
            return nil
        }
        return number.intValue
    }
}
