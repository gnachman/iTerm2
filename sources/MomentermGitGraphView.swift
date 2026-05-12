//
//  MomentermGitGraphView.swift
//  iTerm2
//
//  Sourcetree-style commit graph view. Renders the nodes + edges produced
//  by MomentermGitGraphLayouter using NSBezierPath. The view scrolls
//  horizontally inside MomentermGitGraphVC's NSScrollView; height is
//  driven by the row count.
//

import AppKit

final class MomentermGitGraphView: NSView {

    var layout: MomentermGitGraphLayout = .empty {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    /// Optional handler for "Copy hash" / "Show summary" — invoked on right-click.
    var onContextMenu: ((MomentermGitCommit, NSEvent) -> Void)?

    private let laneSpacing: CGFloat = 16
    private let rowHeight: CGFloat = 22
    private let nodeRadius: CGFloat = 4
    private let summaryLeftPadding: CGFloat = 12
    private let leftInset: CGFloat = 12
    private let topInset: CGFloat = 6

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        let lanesWidth = CGFloat(max(0, layout.maxColumn + 1)) * laneSpacing
        let summaryReserve: CGFloat = 360  // arbitrary; lets long summaries breathe
        return NSSize(width: leftInset + lanesWidth + summaryLeftPadding + summaryReserve,
                      height: topInset * 2 + CGFloat(max(1, layout.nodes.count)) * rowHeight)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        guard !layout.nodes.isEmpty else {
            drawEmptyState()
            return
        }

        // Edges first so nodes sit on top.
        drawEdges()
        drawNodes()
        drawSummaries()
    }

    private func drawEmptyState() {
        let msg = "(no commits — not a git repository or git not on PATH)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        let size = (msg as NSString).size(withAttributes: attrs)
        let point = NSPoint(x: (bounds.width - size.width) / 2.0,
                            y: (bounds.height - size.height) / 2.0)
        (msg as NSString).draw(at: point, withAttributes: attrs)
    }

    private func drawEdges() {
        let path = NSBezierPath()
        path.lineWidth = 1.4
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        for edge in layout.edges {
            let from = pointFor(column: edge.from.column, row: edge.from.row)
            let to = pointFor(column: edge.to.column, row: edge.to.row)
            if from.x == to.x {
                path.move(to: from)
                path.line(to: to)
            } else {
                // Bezier curve so merges/branches look smooth.
                let dy = abs(to.y - from.y)
                let cp1 = NSPoint(x: from.x, y: from.y + dy * 0.5)
                let cp2 = NSPoint(x: to.x, y: to.y - dy * 0.5)
                path.move(to: from)
                path.curve(to: to, controlPoint1: cp1, controlPoint2: cp2)
            }
        }
        NSColor.tertiaryLabelColor.setStroke()
        path.stroke()
    }

    private func drawNodes() {
        for node in layout.nodes {
            let center = pointFor(column: node.column, row: node.row)
            let rect = NSRect(x: center.x - nodeRadius, y: center.y - nodeRadius,
                              width: nodeRadius * 2, height: nodeRadius * 2)
            let fill: NSColor
            let stroke: NSColor
            if node.commit.hasHEAD {
                fill = .controlAccentColor
                stroke = NSColor.controlAccentColor.shadow(withLevel: 0.25) ?? .controlAccentColor
            } else if !node.commit.refs.isEmpty {
                fill = .systemYellow
                stroke = .systemOrange
            } else {
                fill = .secondaryLabelColor
                stroke = .secondaryLabelColor
            }
            let path = NSBezierPath(ovalIn: rect)
            fill.setFill()
            path.fill()
            stroke.setStroke()
            path.lineWidth = 1.0
            path.stroke()
        }
    }

    private func drawSummaries() {
        let summaryX = leftInset + CGFloat(layout.maxColumn + 1) * laneSpacing + summaryLeftPadding
        let summaryFont = NSFont.systemFont(ofSize: 11)
        let refFont = NSFont.systemFont(ofSize: 10, weight: .medium)
        for node in layout.nodes {
            let center = pointFor(column: node.column, row: node.row)
            var x = summaryX

            // Refs first (branch/tag pills).
            for ref in node.commit.refs.prefix(4) {
                let color = ref.contains("HEAD") ? NSColor.controlAccentColor : NSColor.systemYellow
                let pillText = ref.replacingOccurrences(of: "HEAD -> ", with: "")
                x += drawPill(text: pillText, at: NSPoint(x: x, y: center.y - 8),
                              font: refFont, fillColor: color.withAlphaComponent(0.18),
                              textColor: color)
                x += 4
            }

            // sha + summary.
            let sha = node.commit.shortSha + "  "
            let shaAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
            let shaSize = (sha as NSString).size(withAttributes: shaAttrs)
            (sha as NSString).draw(at: NSPoint(x: x, y: center.y - 7), withAttributes: shaAttrs)
            x += shaSize.width

            let summaryAttrs: [NSAttributedString.Key: Any] = [
                .font: summaryFont,
                .foregroundColor: NSColor.labelColor,
            ]
            let remaining = max(0, bounds.width - x - 8)
            let truncated = truncate(node.commit.summary, font: summaryFont, maxWidth: remaining)
            (truncated as NSString).draw(at: NSPoint(x: x, y: center.y - 7), withAttributes: summaryAttrs)
        }
    }

    @discardableResult
    private func drawPill(text: String, at point: NSPoint, font: NSFont,
                          fillColor: NSColor, textColor: NSColor) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let size = (text as NSString).size(withAttributes: attrs)
        let rect = NSRect(x: point.x, y: point.y, width: size.width + 10, height: size.height + 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        fillColor.setFill()
        path.fill()
        (text as NSString).draw(at: NSPoint(x: rect.minX + 5, y: rect.minY + 1), withAttributes: attrs)
        return rect.width
    }

    private func truncate(_ text: String, font: NSFont, maxWidth: CGFloat) -> String {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let size = (text as NSString).size(withAttributes: attrs)
        if size.width <= maxWidth { return text }
        let ellipsis = "…"
        var lo = 0
        var hi = text.count
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            let candidate = String(text.prefix(mid)) + ellipsis
            let w = (candidate as NSString).size(withAttributes: attrs).width
            if w <= maxWidth { lo = mid } else { hi = mid - 1 }
        }
        return String(text.prefix(lo)) + ellipsis
    }

    private func pointFor(column: Int, row: Int) -> NSPoint {
        let x = leftInset + CGFloat(column) * laneSpacing + laneSpacing / 2.0
        let y = topInset + CGFloat(row) * rowHeight + rowHeight / 2.0
        return NSPoint(x: x, y: y)
    }

    // MARK: - Hit testing

    override func rightMouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if let node = node(at: pt), let handler = onContextMenu {
            handler(node.commit, event)
            return
        }
        super.rightMouseDown(with: event)
    }

    private func node(at point: NSPoint) -> MomentermGitGraphLayout.Node? {
        let rowIndex = Int((point.y - topInset) / rowHeight)
        if rowIndex < 0 || rowIndex >= layout.nodes.count { return nil }
        let node = layout.nodes[rowIndex]
        let center = pointFor(column: node.column, row: rowIndex)
        let dx = point.x - center.x
        let dy = point.y - center.y
        if dx * dx + dy * dy <= (nodeRadius * 4) * (nodeRadius * 4) { return node }
        // Hit the summary area on the right.
        let summaryX = leftInset + CGFloat(layout.maxColumn + 1) * laneSpacing
        if point.x >= summaryX { return node }
        return nil
    }
}
