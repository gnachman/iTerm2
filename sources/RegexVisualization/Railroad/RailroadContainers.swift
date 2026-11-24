//
//  RailroadContainers.swift
//  iTerm2
//
//  Swift port of nodes/containers.rs from the railroad crate 0.3.12
//  (https://github.com/lukaslueg/railroad), Copyright (c) 2018 Lukas Lueg,
//  MIT License.
//

import Foundation

/// Children side by side, joined by short lines. Port of `Sequence`.
struct RailroadSequence: RailroadNode {
    static let spacing = 10

    var children: [any RailroadNode]
    var attributes: [String: String] = [:]

    var entryHeight: Int { children.maxEntryHeight }
    var height: Int { children.maxEntryHeight + children.maxHeightBelowEntry }
    var width: Int {
        let total = children.totalWidth
        return children.count > 1 ? total + (children.count - 1) * Self.spacing : total
    }

    func render(_ out: RailroadRenderer, x: Int, y: Int, hDir: RailroadHDir) {
        let entry = entryHeight
        out.group(class: "sequence", attributes: attributes) {
            var runningX = 0
            for child in children {
                child.render(out, x: x + runningX, y: y + entry - child.entryHeight, hDir: hDir)
                runningX += child.width + Self.spacing
            }
            runningX = x
            for child in children.dropLast() {
                out.path(RailroadPathData(hDir)
                    .moveTo(runningX + child.width, y + entry)
                    .horizontal(Self.spacing))
                runningX += child.width + Self.spacing
            }
        }
    }
}

// PORT-STUB: Stack (containers.rs `Stack`).
struct RailroadStack: RailroadNode {
    var children: [any RailroadNode]
    var attributes: [String: String] = [:]
    var entryHeight: Int { fatalError("not ported yet") }
    var height: Int { fatalError("not ported yet") }
    var width: Int { fatalError("not ported yet") }
    func render(_ out: RailroadRenderer, x: Int, y: Int, hDir: RailroadHDir) { fatalError("not ported yet") }
}

// PORT-STUB: Choice (containers.rs `Choice`).
struct RailroadChoice: RailroadNode {
    var children: [any RailroadNode]
    var attributes: [String: String] = [:]
    var entryHeight: Int { fatalError("not ported yet") }
    var height: Int { fatalError("not ported yet") }
    var width: Int { fatalError("not ported yet") }
    func render(_ out: RailroadRenderer, x: Int, y: Int, hDir: RailroadHDir) { fatalError("not ported yet") }
}
