//
//  RailroadWrappers.swift
//  iTerm2
//
//  Swift port of nodes/wrappers.rs and nodes/grids.rs from the railroad
//  crate 0.3.12 (https://github.com/lukaslueg/railroad),
//  Copyright (c) 2018 Lukas Lueg, MIT License.
//

import Foundation

// PORT-STUB: Optional (wrappers.rs `Optional`).
struct RailroadOptional: RailroadNode {
    var inner: any RailroadNode
    var attributes: [String: String] = [:]
    var entryHeight: Int { fatalError("not ported yet") }
    var height: Int { fatalError("not ported yet") }
    var width: Int { fatalError("not ported yet") }
    func render(_ out: RailroadRenderer, x: Int, y: Int, hDir: RailroadHDir) { fatalError("not ported yet") }
}

// PORT-STUB: Repeat (wrappers.rs `Repeat`).
struct RailroadRepeat: RailroadNode {
    var inner: any RailroadNode
    var `repeat`: any RailroadNode
    var attributes: [String: String] = [:]
    var entryHeight: Int { fatalError("not ported yet") }
    var height: Int { fatalError("not ported yet") }
    var width: Int { fatalError("not ported yet") }
    func render(_ out: RailroadRenderer, x: Int, y: Int, hDir: RailroadHDir) { fatalError("not ported yet") }
}

// PORT-STUB: LabeledBox (wrappers.rs `LabeledBox`).
struct RailroadLabeledBox: RailroadNode {
    var inner: any RailroadNode
    var label: any RailroadNode
    var attributes: [String: String] = [:]
    var entryHeight: Int { fatalError("not ported yet") }
    var height: Int { fatalError("not ported yet") }
    var width: Int { fatalError("not ported yet") }
    func render(_ out: RailroadRenderer, x: Int, y: Int, hDir: RailroadHDir) { fatalError("not ported yet") }
}

// PORT-STUB: VerticalGrid (grids.rs `VerticalGrid`).
struct RailroadVerticalGrid: RailroadNode {
    var children: [any RailroadNode]
    var attributes: [String: String] = [:]
    var entryHeight: Int { fatalError("not ported yet") }
    var height: Int { fatalError("not ported yet") }
    var width: Int { fatalError("not ported yet") }
    func render(_ out: RailroadRenderer, x: Int, y: Int, hDir: RailroadHDir) { fatalError("not ported yet") }
}
