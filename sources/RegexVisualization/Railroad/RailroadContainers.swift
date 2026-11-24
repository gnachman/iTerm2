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

/// Children connected from top to bottom. Port of `Stack`.
struct RailroadStack: RailroadNode {
    static let spacing = 10
    static let padding = Railroad.arcRadius * 2

    var children: [any RailroadNode]
    var attributes: [String: String] = [:]

    private var sidePadding: Int { children.count > 1 ? Self.padding : 0 }

    private func paddedHeight(_ child: any RailroadNode, next: any RailroadNode) -> Int {
        child.entryHeight
            + max(child.heightBelowEntry + Self.spacing, Railroad.arcRadius * 2)
            + Railroad.arcRadius
            + max(0, Railroad.arcRadius - next.entryHeight)
    }

    var entryHeight: Int { children.first?.entryHeight ?? 0 }
    var height: Int {
        zip(children, children.dropFirst()).reduce(0) {
            $0 + paddedHeight($1.0, next: $1.1)
        } + (children.last?.height ?? 0)
    }
    var width: Int {
        let lastWidth = children.last?.width ?? 0
        let needsExtra = children.dropLast().contains { $0.width >= lastWidth }
        return sidePadding + children.maxWidth + sidePadding + (needsExtra ? Railroad.arcRadius : 0)
    }

    func render(_ out: RailroadRenderer, x: Int, y: Int, hDir: RailroadHDir) {
        let radius = Railroad.arcRadius
        let leftPadding = sidePadding
        let entry = entryHeight
        let totalHeight = height
        let totalWidth = width
        out.group(class: "stack", attributes: attributes) {
            out.path(RailroadPathData(hDir)
                .moveTo(x, y + entry)
                .horizontal(leftPadding))

            var runningY = y
            for (child, next) in zip(children, children.dropFirst()) {
                out.path(RailroadPathData(hDir)
                    .moveTo(x + leftPadding + child.width, runningY + child.entryHeight)
                    .arc(radius, .westToSouth)
                    .vertical(max(0, child.heightBelowEntry + Self.spacing - radius * 2))
                    .arc(radius, .northToWest)
                    .horizontal(-child.width)
                    .arc(radius, .eastToSouth)
                    .vertical(max(0, next.entryHeight - radius))
                    .vertical(max(0, (Self.spacing - radius * 2) / 2 + (Self.spacing - radius * 2) % 2))
                    .arc(radius, .northToEast))
                child.render(out, x: x + leftPadding, y: runningY, hDir: hDir)
                runningY += paddedHeight(child, next: next)
            }

            if let last = children.last {
                if children.count > 1 {
                    let railY = runningY - y + last.entryHeight
                    out.path(RailroadPathData(hDir)
                        .moveTo(x + leftPadding + last.width, runningY + last.entryHeight)
                        .horizontalWithClearance(totalWidth - last.width - leftPadding - radius * 2,
                                                 above: railY, below: totalHeight - railY)
                        .arc(radius, .westToNorth)
                        .vertical(-totalHeight + last.heightBelowEntry + radius * 2 + entry)
                        .arc(radius, .southToEast))
                }
                last.render(out, x: x + leftPadding, y: runningY, hDir: hDir)
            }
        }
    }
}

/// Alternatives arranged vertically. Port of `Choice`.
struct RailroadChoice: RailroadNode {
    static let spacing = 10

    var children: [any RailroadNode]
    var attributes: [String: String] = [:]

    private var innerPadding: Int { children.count > 1 ? Railroad.arcRadius * 2 : 0 }

    private func paddedHeight(_ child: any RailroadNode) -> Int {
        max(Railroad.arcRadius, child.entryHeight) + child.heightBelowEntry + Self.spacing
    }

    var entryHeight: Int { children.first?.entryHeight ?? 0 }
    var height: Int {
        guard let first = children.first else { return 0 }
        if children.count == 1 { return first.height }
        return entryHeight + max(Railroad.arcRadius, Self.spacing + first.heightBelowEntry)
            + children.dropFirst().reduce(0) { $0 + paddedHeight($1) } - Self.spacing
    }
    var width: Int { innerPadding + children.maxWidth + innerPadding }

    func render(_ out: RailroadRenderer, x: Int, y: Int, hDir: RailroadHDir) {
        let radius = Railroad.arcRadius
        let padding = innerPadding
        let maxChildWidth = children.maxWidth
        let firstWidth = children.first?.width ?? 0
        let entry = entryHeight
        let totalHeight = height
        let totalWidth = width
        out.group(class: "choice", attributes: attributes) {
            out.path(RailroadPathData(hDir)
                .moveTo(x, y + entry)
                .horizontal(padding)
                .moveRel(firstWidth, 0)
                .horizontalWithClearance(totalWidth - padding - firstWidth,
                                         above: entry, below: totalHeight - entry))

            if let first = children.first {
                first.render(out, x: x + padding, y: y, hDir: hDir)
            }

            if children.count > 1 {
                let first = children[0]
                out.path(RailroadPathData(hDir)
                    .moveTo(x, y + entry)
                    .arc(radius, .westToSouth)
                    .vertical(max(0, first.heightBelowEntry + Self.spacing - radius))
                    .moveRel(totalWidth - radius * 2, 0)
                    .vertical(-max(0, first.heightBelowEntry + Self.spacing - radius))
                    .arc(radius, .southToEast))

                let baseY = y + entry + max(radius, Self.spacing + first.heightBelowEntry)
                var runningY = baseY
                for child in children.dropFirst().dropLast() {
                    let padded = paddedHeight(child)
                    let zz = max(0, child.entryHeight - radius)
                    let z = padded - zz
                    out.path(RailroadPathData(hDir)
                        .moveTo(x + radius, runningY + zz)
                        .vertical(z)
                        .moveRel(totalWidth - radius * 2, 0)
                        .vertical(-z))
                    runningY += z + zz
                }

                runningY = baseY
                for child in children.dropFirst() {
                    let railY = runningY - y + max(radius, child.entryHeight)
                    out.path(RailroadPathData(hDir)
                        .moveTo(x + radius, runningY)
                        .vertical(max(0, child.entryHeight - radius))
                        .arc(radius, .northToEast)
                        .moveRel(child.width, 0)
                        .horizontalWithClearance(maxChildWidth - child.width,
                                                 above: railY, below: totalHeight - railY)
                        .arc(radius, .westToNorth)
                        .vertical(-max(0, child.entryHeight - radius)))
                    child.render(out, x: x + radius * 2,
                                 y: runningY + max(0, radius - child.entryHeight), hDir: hDir)
                    runningY += paddedHeight(child)
                }
            }
        }
    }
}
