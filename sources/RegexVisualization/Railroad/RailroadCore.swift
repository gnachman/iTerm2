//
//  RailroadCore.swift
//  iTerm2
//
//  Swift port of the railroad crate 0.3.12 (https://github.com/lukaslueg/railroad),
//  Copyright (c) 2018 Lukas Lueg, MIT License. See ThirdParty/Licenses.txt.
//
//  This file holds the pieces every node shares: the Node protocol, the SVG
//  writer (notactuallysvg.rs), path data, and the leaf nodes from lib.rs.
//  The output must stay byte-identical to the Rust library; the reference
//  diagrams in tests/railroad/svg check that.
//

import Foundation

enum Railroad {
    static let arcRadius = 12

    /// Column width of a label, plus 5%. Port of `text_width` in lib.rs.
    static func textWidth(_ s: String) -> Int {
        let w = RailroadTextWidth.columns(s)
        return w + w / 20
    }
}

// MARK: - Direction and arcs

enum RailroadHDir {
    case ltr
    case rtl

    var inverted: RailroadHDir {
        switch self {
        case .ltr: return .rtl
        case .rtl: return .ltr
        }
    }
}

enum RailroadArc {
    case eastToNorth
    case eastToSouth
    case northToEast
    case northToWest
    case southToEast
    case southToWest
    case westToNorth
    case westToSouth
}

// MARK: - Node

protocol RailroadNode {
    /// Distance from the top of the node to the line that enters and leaves it.
    var entryHeight: Int { get }
    var height: Int { get }
    var width: Int { get }
    func render(_ out: RailroadRenderer, x: Int, y: Int, hDir: RailroadHDir)
}

extension RailroadNode {
    var heightBelowEntry: Int { height - entryHeight }
}

extension Array where Element == any RailroadNode {
    var maxEntryHeight: Int { map(\.entryHeight).max() ?? 0 }
    var maxHeight: Int { map(\.height).max() ?? 0 }
    var maxHeightBelowEntry: Int { map(\.heightBelowEntry).max() ?? 0 }
    var maxWidth: Int { map(\.width).max() ?? 0 }
    var totalWidth: Int { map(\.width).reduce(0, +) }
    var totalHeight: Int { map(\.height).reduce(0, +) }
}

// MARK: - SVG writer

/// Streams SVG text. Port of `svg::Renderer` and `svg::StartTag`.
final class RailroadRenderer {
    private(set) var output = ""

    final class StartTag {
        private let renderer: RailroadRenderer
        private var attributes: [(String, String)] = []

        fileprivate init(renderer: RailroadRenderer) {
            self.renderer = renderer
        }

        /// Setting a key twice keeps its first position and the last value.
        func attr(_ key: String, _ value: String) {
            if let i = attributes.firstIndex(where: { $0.0 == key }) {
                attributes[i].1 = value
            } else {
                attributes.append((key, value))
            }
        }

        func attr(_ key: String, _ value: Int) {
            attr(key, String(value))
        }

        /// Attributes from a dictionary, sorted by key.
        func attrs(_ dict: [String: String]) {
            for key in dict.keys.sorted() {
                attr(key, dict[key]!)
            }
        }

        private func writeAttributes() {
            for (key, value) in attributes {
                renderer.output += " "
                renderer.output += RailroadRenderer.escapeMinimal(key)
                renderer.output += "=\""
                renderer.output += RailroadRenderer.escapeMinimal(value)
                renderer.output += "\""
            }
        }

        func finish() {
            writeAttributes()
            renderer.output += ">\n"
        }

        func finishEmpty() {
            writeAttributes()
            renderer.output += "/>\n"
        }
    }

    func startElement(_ name: String) -> StartTag {
        output += "<"
        output += name
        return StartTag(renderer: self)
    }

    func endElement(_ name: String) {
        output += "</"
        output += name
        output += ">\n"
    }

    func writeText(_ text: String) {
        output += Self.escapeMinimal(text)
    }

    func writeRaw(_ text: String) {
        output += text
    }

    func path(_ path: RailroadPathData, class cls: String? = nil) {
        let tag = startElement("path")
        tag.attr("d", path.text)
        if let cls {
            tag.attr("class", cls)
        }
        tag.finishEmpty()
    }

    func textElement(_ name: String, _ text: String, configure: (StartTag) -> Void) {
        let tag = startElement(name)
        configure(tag)
        tag.finish()
        writeText(text)
        endElement(name)
    }

    // Shared drawing helpers (the RenderBackend calls in lib.rs).

    func rect(x: Int, y: Int, width: Int, height: Int, radius: Int? = nil) {
        let tag = startElement("rect")
        tag.attr("x", x)
        tag.attr("y", y)
        tag.attr("height", height)
        tag.attr("width", width)
        if let radius {
            tag.attr("rx", radius)
            tag.attr("ry", radius)
        }
        tag.finishEmpty()
    }

    func circle(cx: Int, cy: Int, radius: Double, opacity: String) {
        let tag = startElement("circle")
        tag.attr("cx", cx)
        tag.attr("cy", cy)
        tag.attr("r", Self.format(radius))
        tag.attr("fill-opacity", opacity)
        tag.finishEmpty()
    }

    func text(x: Int, y: Int, _ text: String, class cls: String? = nil) {
        textElement("text", text) { tag in
            if let cls {
                tag.attr("class", cls)
            }
            tag.attr("x", x)
            tag.attr("y", y)
        }
    }

    /// `<g class=...>` around whatever `body` writes.
    func group(class cls: String, attributes: [String: String] = [:], body: () -> Void) {
        let tag = startElement("g")
        tag.attrs(attributes)
        tag.attr("class", cls)
        tag.finish()
        body()
        endElement("g")
    }

    /// `<g transform=...>` around a child drawn at the origin.
    func transformed(_ child: any RailroadNode, transform: String, hDir: RailroadHDir) {
        let tag = startElement("g")
        tag.attr("transform", transform)
        tag.finish()
        child.render(self, x: 0, y: 0, hDir: hDir)
        endElement("g")
    }

    /// The box with a centered label that Terminal and NonTerminal draw.
    func textBox(x: Int, y: Int, width: Int, height: Int, entryHeight: Int, label: String, rounded: Bool) {
        rect(x: x, y: y, width: width, height: height, radius: rounded ? 10 : nil)
        text(x: x + width / 2, y: y + entryHeight + 5, label)
    }

    /// Rust's `{}` formatting of an f64: no trailing ".0" for whole numbers.
    static func format(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int(value))
        }
        return String(value)
    }

    static func escapeMinimal(_ s: String) -> String {
        guard s.contains(where: { "\"&<>'".contains($0) }) else {
            return s
        }
        var result = ""
        result.reserveCapacity(s.utf8.count)
        for c in s {
            switch c {
            case "\"": result += "&quot;"
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "'": result += "&#x27;"
            default: result.append(c)
            }
        }
        return result
    }
}

// MARK: - Path data

/// Port of `svg::PathData`: builds the `d` attribute of a path.
struct RailroadPathData {
    static let padding = 5

    private(set) var text = ""
    let hDir: RailroadHDir

    init(_ hDir: RailroadHDir) {
        self.hDir = hDir
    }

    func moveTo(_ x: Int, _ y: Int) -> Self { appending(" M \(x) \(y)") }
    func moveRel(_ x: Int, _ y: Int) -> Self { appending(" m \(x) \(y)") }
    func lineRel(_ x: Int, _ y: Int) -> Self { appending(" l \(x) \(y)") }
    func close() -> Self { appending(" z") }

    func cubicRel(_ x1: Int, _ y1: Int, _ x2: Int, _ y2: Int, _ x: Int, _ y: Int) -> Self {
        appending(" c \(x1) \(y1) \(x2) \(y2) \(x) \(y)")
    }

    /// A horizontal line, with an arrow head halfway along stretches longer than 50.
    func horizontal(_ h: Int) -> Self {
        let p = appending(" h \(h)")
        let pad = Self.padding
        switch (h > 50, h < -50, hDir) {
        case (true, _, .ltr):
            return p.moveRel(-(h / 2 - 3), 0).lineRel(-pad, -pad).moveRel(0, pad * 2).lineRel(pad, -pad).moveRel(h / 2 - 3, 0)
        case (true, _, .rtl):
            return p.moveRel(-(h / 2 + 3), 0).lineRel(pad, -pad).moveRel(0, pad * 2).lineRel(-pad, -pad).moveRel(h / 2 + 3, 0)
        case (_, true, .ltr):
            return p.moveRel(-(h / 2 - 3), 0).lineRel(pad, -pad).moveRel(0, pad * 2).lineRel(-pad, -pad).moveRel(h / 2 - 3, 0)
        case (_, true, .rtl):
            return p.moveRel(-(h / 2 + 3), 0).lineRel(-pad, -pad).moveRel(0, pad * 2).lineRel(pad, -pad).moveRel(h / 2 + 3, 0)
        default:
            return p
        }
    }

    /// Like `horizontal`, but drops the arrow when there is no room for it.
    func horizontalWithClearance(_ h: Int, above: Int, below: Int) -> Self {
        if above >= Self.padding && below >= Self.padding {
            return horizontal(h)
        }
        return lineRel(h, 0)
    }

    /// A vertical line, with an arrow head halfway along stretches longer than 50.
    func vertical(_ h: Int) -> Self {
        let p = appending(" v \(h)")
        if (-50...50).contains(h) {
            return p
        }
        let pointsDown = (h > 0) == (hDir == .ltr)
        let arrowY = pointsDown ? -Self.padding : Self.padding
        return p.moveRel(0, -(h / 2 - 3))
            .lineRel(-Self.padding, arrowY)
            .moveRel(Self.padding * 2, 0)
            .lineRel(-Self.padding, -arrowY)
            .moveRel(0, h / 2 - 3)
    }

    func arc(_ radius: Int, _ kind: RailroadArc) -> Self {
        let (sweep, x, y): (Int, Int, Int)
        switch kind {
        case .eastToNorth: (sweep, x, y) = (1, -radius, -radius)
        case .eastToSouth: (sweep, x, y) = (0, -radius, radius)
        case .northToEast: (sweep, x, y) = (0, radius, radius)
        case .northToWest: (sweep, x, y) = (1, -radius, radius)
        case .southToEast: (sweep, x, y) = (1, radius, -radius)
        case .southToWest: (sweep, x, y) = (0, -radius, -radius)
        case .westToNorth: (sweep, x, y) = (0, radius, -radius)
        case .westToSouth: (sweep, x, y) = (1, radius, radius)
        }
        return appending(" a \(radius) \(radius) 0 0 \(sweep) \(x) \(y)")
    }

    private func appending(_ s: String) -> Self {
        var copy = self
        copy.text += s
        return copy
    }
}

// MARK: - Diagram

/// The outermost `<svg>` element. Port of `Diagram` in lib.rs.
struct RailroadDiagram: RailroadNode {
    static let padding = 10

    var root: any RailroadNode
    var css: String?
    var extraAttributes: [String: String] = [:]

    var entryHeight: Int { 0 }
    var height: Int { Self.padding + root.height + Self.padding }
    var width: Int { Self.padding + root.width + Self.padding }

    func render(_ out: RailroadRenderer, x: Int, y: Int, hDir: RailroadHDir) {
        let tag = out.startElement("svg")
        tag.attrs(extraAttributes)
        tag.attr("xmlns", "http://www.w3.org/2000/svg")
        tag.attr("xmlns:xlink", "http://www.w3.org/1999/xlink")
        tag.attr("class", "railroad")
        tag.attr("viewBox", "0 0 \(width) \(height)")
        tag.finish()
        if let css {
            // Rust writes extra elements with Element's Display: attributes
            // sorted, raw text, closing tag on its own line.
            out.writeRaw("<style type=\"text/css\">\n")
            out.writeRaw(css)
            out.writeRaw("</style>\n")
        }
        let rect = out.startElement("rect")
        rect.attr("width", "100%")
        rect.attr("height", "100%")
        rect.attr("class", "railroad_canvas")
        rect.finishEmpty()
        root.render(out, x: x + Self.padding, y: y + Self.padding, hDir: hDir)
        out.endElement("svg")
    }

    var svg: String {
        let out = RailroadRenderer()
        render(out, x: 0, y: 0, hDir: .ltr)
        return out.output
    }
}

// MARK: - Leaf nodes from lib.rs

struct RailroadEmpty: RailroadNode {
    var entryHeight: Int { 0 }
    var height: Int { 0 }
    var width: Int { 0 }

    func render(_ out: RailroadRenderer, x: Int, y: Int, hDir: RailroadHDir) {
        out.startElement("g").finish()
        out.endElement("g")
    }
}

struct RailroadSimpleStart: RailroadNode {
    var entryHeight: Int { 5 }
    var height: Int { 10 }
    var width: Int { 15 }

    func render(_ out: RailroadRenderer, x: Int, y: Int, hDir: RailroadHDir) {
        out.path(RailroadPathData(hDir)
            .moveTo(x, y + 5)
            .arc(5, .southToEast)
            .arc(5, .westToSouth)
            .arc(5, .northToWest)
            .arc(5, .eastToNorth)
            .moveRel(10, 0)
            .horizontal(5))
    }
}

struct RailroadSimpleEnd: RailroadNode {
    var entryHeight: Int { 5 }
    var height: Int { 10 }
    var width: Int { 15 }

    func render(_ out: RailroadRenderer, x: Int, y: Int, hDir: RailroadHDir) {
        out.path(RailroadPathData(hDir)
            .moveTo(x, y + 5)
            .horizontal(5)
            .arc(5, .southToEast)
            .arc(5, .westToSouth)
            .arc(5, .northToWest)
            .arc(5, .eastToNorth))
    }
}

struct RailroadStart: RailroadNode {
    var entryHeight: Int { 10 }
    var height: Int { 20 }
    var width: Int { 20 }

    func render(_ out: RailroadRenderer, x: Int, y: Int, hDir: RailroadHDir) {
        out.path(RailroadPathData(hDir)
            .moveTo(x, y)
            .vertical(20)
            .moveRel(10, -20)
            .vertical(20)
            .moveRel(-10, -10)
            .horizontal(20))
    }
}

struct RailroadEnd: RailroadNode {
    var entryHeight: Int { 10 }
    var height: Int { 20 }
    var width: Int { 20 }

    func render(_ out: RailroadRenderer, x: Int, y: Int, hDir: RailroadHDir) {
        out.path(RailroadPathData(hDir)
            .moveTo(x, y + 10)
            .horizontal(20)
            .moveRel(-10, -10)
            .vertical(20)
            .moveRel(10, -20)
            .vertical(20))
    }
}
