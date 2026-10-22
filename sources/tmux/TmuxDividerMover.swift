//
//  TmuxDividerMover.swift
//  iTerm2SharedARC
//
//  Builds a tmux layout, for use with select-layout, that matches what the window showed at the
//  end of a divider drag.
//
//  While a divider is dragged, the window resizes the two subviews beside it, and a subview that is
//  itself split in the same direction spreads the change over its children in proportion to their
//  sizes. tmux's resize-pane does neither of those things exactly: it moves the divider that belongs
//  to the pane it is sent to, which is not always the dragged one, and it spreads changes one cell
//  at a time. Sending the whole layout makes tmux do what the window previewed.
//
//  The layout comes from the window's last tmux layout, with the sizes under the two subviews
//  beside the dragged divider replaced by the sizes their panes showed, rounded to whole cells.
//  Everything else keeps tmux's sizes, so rounding can't nudge unrelated dividers.
//

import Foundation

@objc(iTermTmuxDividerMover)
class TmuxDividerMover: NSObject {
    fileprivate indirect enum Node {
        case leaf(width: Int32, height: Int32, pane: Int32)
        case split(verticalDividers: Bool, children: [Node])
    }

    // tmux's PANE_MINIMUM.
    fileprivate static let minimumPaneSize: Int32 = 1

    // Returns a layout string for select-layout that is |parseTree| with the sizes around one
    // divider changed to match what was shown, or nil if no such layout can be made. If nothing
    // moved by a whole cell, the result is the layout tmux already has.
    //
    // parseTree: the window's layout as TmuxLayoutParser produced it, with leaf sizes corrected for
    //   pane-border-status (that correction is undone here).
    // panes: the window panes under the split that owns the divider. They identify the split.
    // verticalDividers: whether that split's children are side by side.
    // dividerIndex: which of the split's dividers moved, 0 being the leftmost or topmost.
    // measuredExtents: maps window pane to how many cells it showed across the dividers (its width
    //   for vertical dividers, its height for horizontal ones), with the fraction kept. It must have
    //   every pane beside the divider.
    @objc(layoutStringForParseTree:movingDivider:ofSplitWithPanes:verticalDividers:measuredExtents:paneBorderStatus:)
    static func layoutString(parseTree: NSDictionary,
                             dividerIndex: Int,
                             panes: [NSNumber],
                             verticalDividers: Bool,
                             measuredExtents: [NSNumber: NSNumber],
                             paneBorderStatus: iTermTmuxPaneBorderStatus) -> String? {
        if let floats = parseTree[kLayoutDictFloatingPanesKey] as? NSArray, floats.count > 0 {
            DLog("Not moving a divider with select-layout in a window with floating panes")
            return nil
        }
        guard let root = node(parseTree) else {
            return nil
        }
        let paneSet = Set(panes.map { $0.int32Value })
        var measured = [Int32: Double]()
        // A pane with a size that isn't a number counts as unmeasured.
        for (pane, extent) in measuredExtents where extent.doubleValue.isFinite {
            measured[pane.int32Value] = extent.doubleValue
        }
        let geometry = Geometry(verticalDividers: verticalDividers, measured: measured)
        guard let moved = geometry.moving(divider: dividerIndex, ofSplitWithPanes: paneSet, in: root) else {
            DLog("Could not move divider \(dividerIndex) of split with panes \(paneSet) to match \(measured)")
            return nil
        }
        let builder = iTermTmuxLayoutBuilder(rootNode: builderNode(moved))
        builder.adjust(for: paneBorderStatus)
        return builder.layoutString
    }
}

// MARK: - Parse tree conversion

private extension TmuxDividerMover {
    static func int32(_ value: Any?) -> Int32? {
        if let number = value as? NSNumber {
            return number.int32Value
        }
        if let string = value as? NSString {
            return string.intValue
        }
        return nil
    }

    static func node(_ dict: NSDictionary) -> Node? {
        guard let rawType = int32(dict[kLayoutDictNodeType]),
              let type = LayoutNodeType(rawValue: Int(rawType)) else {
            return nil
        }
        switch type {
        case .leafLayoutNode:
            guard let width = int32(dict[kLayoutDictWidthKey]),
                  let height = int32(dict[kLayoutDictHeightKey]),
                  let pane = int32(dict[kLayoutDictWindowPaneKey]) else {
                return nil
            }
            return .leaf(width: width, height: height, pane: pane)
        case .hSplitLayoutNode, .vSplitLayoutNode:
            guard let childDicts = dict[kLayoutDictChildrenKey] as? [NSDictionary],
                  !childDicts.isEmpty else {
                return nil
            }
            var children = [Node]()
            for childDict in childDicts {
                guard let child = node(childDict) else {
                    return nil
                }
                children.append(child)
            }
            if children.count == 1 {
                // The parser wraps a lone pane in a split. tmux has no such node.
                return children[0]
            }
            return .split(verticalDividers: type == .vSplitLayoutNode, children: children)
        @unknown default:
            return nil
        }
    }

    static func builderNode(_ node: Node) -> iTermTmuxLayoutBuilderNode {
        switch node {
        case let .leaf(width, height, pane):
            return iTermTmuxLayoutBuilderLeafNode(sessionOf: VT100GridSize(width: width, height: height),
                                                  windowPane: pane)
        case let .split(verticalDividers, children):
            let result = iTermTmuxLayoutBuilderInteriorNode(verticalDividers: verticalDividers)
            for child in children {
                result.add(builderNode(child))
            }
            return result
        }
    }
}

// MARK: - Moving a divider

// Sizes here are measured across the dragged divider's direction: widths for vertical dividers,
// heights for horizontal ones. The other dimension never changes.
private struct Geometry {
    typealias Node = TmuxDividerMover.Node

    var verticalDividers: Bool
    var measured: [Int32: Double]

    static func panes(in node: Node) -> Set<Int32> {
        switch node {
        case let .leaf(_, _, pane):
            return [pane]
        case let .split(_, children):
            return children.reduce(into: Set<Int32>()) { $0.formUnion(panes(in: $1)) }
        }
    }

    // Returns |node| with the divider's neighbors resized to what was shown, or nil if the split
    // isn't in |node| or no valid layout matches.
    func moving(divider: Int, ofSplitWithPanes paneSet: Set<Int32>, in node: Node) -> Node? {
        guard case let .split(nodeVerticalDividers, children) = node else {
            return nil
        }
        if nodeVerticalDividers == verticalDividers && Geometry.panes(in: node) == paneSet {
            guard divider >= 0, divider < children.count - 1 else {
                return nil
            }
            let before = children[divider]
            let after = children[divider + 1]
            guard let measuredBefore = measuredExtent(before),
                  let measuredAfter = measuredExtent(after) else {
                return nil
            }
            // The two neighbors share their space; the rest of the split doesn't change. Scaling
            // the shown sizes to that space absorbs any slack the window had beyond tmux's size.
            let total = extent(before) + extent(after)
            let minimumBefore = minimumExtent(before)
            let minimumAfter = minimumExtent(after)
            guard minimumBefore + minimumAfter <= total else {
                return nil
            }
            let shown = max(0, measuredBefore) + max(0, measuredAfter)
            let ideal = shown > 0 ? max(0, measuredBefore) * Double(total) / shown : Double(extent(before))
            // Sizes too big to add up overflow to infinity.
            guard ideal.isFinite else {
                return nil
            }
            let newBefore = min(max(Int32(ideal.rounded()), minimumBefore), total - minimumAfter)
            guard let resizedBefore = resizing(before, to: newBefore),
                  let resizedAfter = resizing(after, to: total - newBefore) else {
                return nil
            }
            var newChildren = children
            newChildren[divider] = resizedBefore
            newChildren[divider + 1] = resizedAfter
            return .split(verticalDividers: nodeVerticalDividers, children: newChildren)
        }
        for (i, child) in children.enumerated() {
            if let movedChild = moving(divider: divider, ofSplitWithPanes: paneSet, in: child) {
                var newChildren = children
                newChildren[i] = movedChild
                return .split(verticalDividers: nodeVerticalDividers, children: newChildren)
            }
        }
        return nil
    }

    // tmux's size of |node|. Dividers are a cell.
    func extent(_ node: Node) -> Int32 {
        switch node {
        case let .leaf(width, height, _):
            return verticalDividers ? width : height
        case let .split(nodeVerticalDividers, children):
            if nodeVerticalDividers == verticalDividers {
                return children.reduce(Int32(children.count - 1)) { $0 + extent($1) }
            }
            return extent(children[0])
        }
    }

    // The size |node| was shown at, or nil if a pane under it wasn't measured. Children of a split in
    // the other direction all have the same size in tmux. The one with the most panes across has the
    // least room once each pane's margins are taken out, so its size is the one tmux could show.
    func measuredExtent(_ node: Node) -> Double? {
        switch node {
        case let .leaf(_, _, pane):
            return measured[pane]
        case let .split(nodeVerticalDividers, children):
            var extents = [Double]()
            for child in children {
                guard let childExtent = measuredExtent(child) else {
                    return nil
                }
                extents.append(childExtent)
            }
            if nodeVerticalDividers == verticalDividers {
                return extents.reduce(Double(children.count - 1), +)
            }
            return extents.min()
        }
    }

    func minimumExtent(_ node: Node) -> Int32 {
        switch node {
        case .leaf:
            return TmuxDividerMover.minimumPaneSize
        case let .split(nodeVerticalDividers, children):
            if nodeVerticalDividers == verticalDividers {
                return children.reduce(Int32(children.count - 1)) { $0 + minimumExtent($1) }
            }
            return children.map { minimumExtent($0) }.max() ?? TmuxDividerMover.minimumPaneSize
        }
    }

    // Returns |node| at size |newExtent|. A split in the same direction divides it among its
    // children in proportion to the sizes they were shown at, as the window did.
    func resizing(_ node: Node, to newExtent: Int32) -> Node? {
        switch node {
        case let .leaf(width, height, pane):
            if verticalDividers {
                return .leaf(width: newExtent, height: height, pane: pane)
            }
            return .leaf(width: width, height: newExtent, pane: pane)
        case let .split(nodeVerticalDividers, children):
            if nodeVerticalDividers != verticalDividers {
                var newChildren = [Node]()
                for child in children {
                    guard let newChild = resizing(child, to: newExtent) else {
                        return nil
                    }
                    newChildren.append(newChild)
                }
                return .split(verticalDividers: nodeVerticalDividers, children: newChildren)
            }
            var weights = [Double]()
            for child in children {
                guard let weight = measuredExtent(child) else {
                    return nil
                }
                weights.append(max(0, weight))
            }
            guard let sizes = Geometry.dividing(newExtent - Int32(children.count - 1),
                                                weights: weights,
                                                minimums: children.map { minimumExtent($0) }) else {
                return nil
            }
            var newChildren = [Node]()
            for (child, size) in zip(children, sizes) {
                guard let newChild = resizing(child, to: size) else {
                    return nil
                }
                newChildren.append(newChild)
            }
            return .split(verticalDividers: nodeVerticalDividers, children: newChildren)
        }
    }

    // Splits |total| cells in proportion to |weights|. Each divider goes to the cell nearest its
    // proportional position, then any child below its minimum takes cells from the nearest children
    // that can spare them. Returns nil if the minimums don't fit.
    static func dividing(_ total: Int32, weights: [Double], minimums: [Int32]) -> [Int32]? {
        guard minimums.reduce(0, +) <= total, !weights.isEmpty else {
            return nil
        }
        let weightSum = weights.reduce(0, +)
        let shares = weightSum > 0 ? weights : Array(repeating: 1, count: weights.count)
        let shareSum = weightSum > 0 ? weightSum : Double(weights.count)
        var sizes = [Int32]()
        var accumulated = 0.0
        var previousBoundary: Int32 = 0
        for (i, share) in shares.enumerated() {
            accumulated += share * Double(total) / shareSum
            guard accumulated.isFinite else {
                return nil
            }
            let boundary = i == shares.count - 1 ? total : min(total, Int32(accumulated.rounded()))
            sizes.append(boundary - previousBoundary)
            previousBoundary = boundary
        }
        for i in sizes.indices where sizes[i] < minimums[i] {
            var deficit = minimums[i] - sizes[i]
            sizes[i] = minimums[i]
            let donors = sizes.indices.filter { $0 != i }.sorted { abs($0 - i) < abs($1 - i) }
            for j in donors where deficit > 0 {
                let taken = min(deficit, max(0, sizes[j] - minimums[j]))
                sizes[j] -= taken
                deficit -= taken
            }
        }
        return sizes
    }
}
