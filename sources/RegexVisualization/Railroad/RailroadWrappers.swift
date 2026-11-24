//
//  RailroadWrappers.swift
//  iTerm2
//
//  Swift port of nodes/wrappers.rs and nodes/grids.rs from the railroad
//  crate 0.3.12 (https://github.com/lukaslueg/railroad),
//  Copyright (c) 2018 Lukas Lueg, MIT License.
//

import Foundation

/// A child with an upper bypass path. Port of `Optional`.
struct RailroadOptional: RailroadNode {
    var inner: any RailroadNode
    var attributes: [String: String] = [:]

    var entryHeight: Int {
        RailroadPathData.padding + Railroad.arcRadius + max(Railroad.arcRadius, inner.entryHeight)
    }
    var height: Int { entryHeight + inner.heightBelowEntry }
    var width: Int { Railroad.arcRadius * 2 + inner.width + Railroad.arcRadius * 2 }

    func render(_ out: RailroadRenderer, x: Int, y: Int, hDir: RailroadHDir) {
        let radius = Railroad.arcRadius
        out.group(class: "optional", attributes: attributes) {
            out.path(RailroadPathData(hDir)
                .moveTo(x, y + entryHeight)
                .horizontal(radius * 2)
                .moveRel(-radius * 2, 0)
                .arc(radius, .westToNorth)
                .vertical(min(0, -inner.entryHeight + radius))
                .arc(radius, .southToEast)
                .horizontal(inner.width)
                .arc(radius, .westToSouth)
                .vertical(max(0, inner.entryHeight - radius))
                .arc(radius, .northToEast)
                .horizontal(-radius * 2))
            inner.render(out, x: x + radius * 2, y: y + entryHeight - inner.entryHeight, hDir: hDir)
        }
    }
}

/// A forward child and a return child in the opposite direction. Port of `Repeat`.
struct RailroadRepeat: RailroadNode {
    static let spacing = 10

    var inner: any RailroadNode
    var `repeat`: any RailroadNode
    var attributes: [String: String] = [:]

    private var heightBetweenEntries: Int {
        max(Railroad.arcRadius * 2, inner.heightBelowEntry + Self.spacing + `repeat`.entryHeight)
    }
    var entryHeight: Int { RailroadPathData.padding + inner.entryHeight }
    var height: Int {
        entryHeight + heightBetweenEntries + `repeat`.heightBelowEntry + RailroadPathData.padding
    }
    var width: Int {
        RailroadPathData.padding * 2 + Railroad.arcRadius + max(`repeat`.width, inner.width) + Railroad.arcRadius
    }

    func render(_ out: RailroadRenderer, x: Int, y: Int, hDir: RailroadHDir) {
        let radius = Railroad.arcRadius
        let padding = RailroadPathData.padding
        let heightBetween = heightBetweenEntries
        out.group(class: "repeat", attributes: attributes) {
            out.path(RailroadPathData(hDir)
                .moveTo(x, y + entryHeight)
                .horizontal(padding)
                .horizontal(radius)
                .moveRel(inner.width, 0)
                .horizontal(max(radius, `repeat`.width - inner.width + radius))
                .horizontal(padding)
                .moveRel(-radius - padding, 0)
                .arc(radius, .westToSouth)
                .vertical(heightBetween - radius * 2)
                .arc(radius, .northToWest)
                .moveRel(-`repeat`.width, 0)
                .horizontal(min(0, `repeat`.width - inner.width))
                .arc(radius, .eastToNorth)
                .vertical(-heightBetween + radius * 2)
                .arc(radius, .southToEast))
            `repeat`.render(out,
                            x: x + width - `repeat`.width - radius - padding,
                            y: y + height - `repeat`.heightBelowEntry - `repeat`.entryHeight - padding,
                            hDir: hDir.inverted)
            inner.render(out, x: x + radius + padding, y: y + padding, hDir: hDir)
        }
    }
}

/// A frame with a label above its child. Port of `LabeledBox`.
struct RailroadLabeledBox: RailroadNode {
    static let spacing = 8
    static let padding = 8

    var inner: any RailroadNode
    var label: any RailroadNode
    var attributes: [String: String] = [:]

    private var labelSpacing: Int { label.height > 0 ? Self.spacing : 0 }
    private var boxPadding: Int {
        label.height + inner.height + label.width + inner.width > 0 ? Self.padding : 0
    }
    var entryHeight: Int { boxPadding + label.height + labelSpacing + inner.entryHeight }
    var height: Int { boxPadding + label.height + labelSpacing + inner.height + boxPadding }
    var width: Int { boxPadding + max(inner.width, label.width) + boxPadding }

    func render(_ out: RailroadRenderer, x: Int, y: Int, hDir: RailroadHDir) {
        let padding = boxPadding
        let spacing = labelSpacing
        out.group(class: "labeledbox", attributes: attributes) {
            out.rect(x: x, y: y, width: width, height: height)
            out.path(RailroadPathData(hDir)
                .moveTo(x, y + entryHeight)
                .horizontal(padding)
                .moveRel(inner.width, 0)
                .horizontal(width - inner.width - padding))
            label.render(out, x: x + padding, y: y + padding, hDir: hDir)
            inner.render(out, x: x + padding, y: y + padding + label.height + spacing, hDir: hDir)
        }
    }
}

/// Unconnected children laid out top to bottom. Port of `VerticalGrid`.
struct RailroadVerticalGrid: RailroadNode {
    static let spacing = Railroad.arcRadius

    var children: [any RailroadNode]
    var attributes: [String: String] = [:]

    var entryHeight: Int { 0 }
    var height: Int { children.totalHeight + (max(1, children.count) - 1) * Self.spacing }
    var width: Int { children.maxWidth }

    func render(_ out: RailroadRenderer, x: Int, y: Int, hDir: RailroadHDir) {
        out.group(class: "verticalgrid", attributes: attributes) {
            var runningY = y
            for child in children {
                child.render(out, x: x, y: runningY, hDir: hDir)
                runningY += child.height + Self.spacing
            }
        }
    }
}
