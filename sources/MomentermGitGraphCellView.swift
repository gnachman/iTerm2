//
//  MomentermGitGraphCellView.swift
//  iTerm2
//
//  Cell view used inside the Git Graph window's NSTableView for the leftmost
//  "Graph" column. It draws the dot for the row's commit and the slice of
//  every lane line that passes through this row, so the table renders the
//  DAG with one cell per commit.
//
//  Slice rules per row r:
//    - dot at (laneCenter(commit.column), cellCenter)
//    - if edge starts at this row: vertical from center to bottom in commit's lane
//    - if edge ends at this row: bezier from (from.col, top) to (to.col=commit.col, center)
//    - if edge passes through (from.row < r < to.row): vertical from top to bottom in from.col
//

import AppKit

final class MomentermGitGraphCellView: NSView {

    var layout: MomentermGitGraphLayout = .empty {
        didSet { needsDisplay = true }
    }
    var rowIndex: Int = -1 {
        didSet { needsDisplay = true }
    }

    private let laneSpacing: CGFloat = 14
    private let nodeRadius: CGFloat = 4
    private let leftInset: CGFloat = 8

    override var isFlipped: Bool { true }  // top-down coordinates so y grows downward

    override func draw(_ dirtyRect: NSRect) {
        guard rowIndex >= 0, rowIndex < layout.nodes.count else { return }
        let node = layout.nodes[rowIndex]
        let h = bounds.height
        let cellTop: CGFloat = 0
        let cellBottom: CGFloat = h
        let cellMid: CGFloat = h * 0.5

        // 1. Edges that touch this row.
        let edges = NSBezierPath()
        edges.lineWidth = 1.4
        edges.lineCapStyle = .round

        for edge in layout.edges {
            let fr = edge.from.row
            let tr = edge.to.row
            // Edges always go from a newer commit (smaller row) to its parent (larger row).
            // Ignore unrelated edges.
            if rowIndex < fr || rowIndex > tr { continue }
            if fr == tr { continue }

            let fx = laneCenter(column: edge.from.column)
            let tx = laneCenter(column: edge.to.column)

            if rowIndex == fr {
                // Edge starts here: vertical from this commit's center to bottom in its own lane.
                edges.move(to: NSPoint(x: fx, y: cellMid))
                edges.line(to: NSPoint(x: fx, y: cellBottom))
            } else if rowIndex == tr {
                // Edge ends here: from (origin lane, top) to (parent lane = this commit's lane, center).
                edges.move(to: NSPoint(x: fx, y: cellTop))
                if abs(fx - tx) < 0.5 {
                    edges.line(to: NSPoint(x: tx, y: cellMid))
                } else {
                    let cy1 = (cellTop + cellMid) * 0.5
                    edges.curve(to: NSPoint(x: tx, y: cellMid),
                                controlPoint1: NSPoint(x: fx, y: cy1),
                                controlPoint2: NSPoint(x: tx, y: cy1))
                }
            } else {
                // Pass-through: straight vertical line through this cell in the origin's lane.
                edges.move(to: NSPoint(x: fx, y: cellTop))
                edges.line(to: NSPoint(x: fx, y: cellBottom))
            }
        }

        NSColor.tertiaryLabelColor.setStroke()
        edges.stroke()

        // 2. Node dot for this row.
        let nodeX = laneCenter(column: node.column)
        let dotRect = NSRect(x: nodeX - nodeRadius, y: cellMid - nodeRadius,
                             width: nodeRadius * 2, height: nodeRadius * 2)
        let dot = NSBezierPath(ovalIn: dotRect)
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
        fill.setFill()
        dot.fill()
        stroke.setStroke()
        dot.lineWidth = 1.0
        dot.stroke()
    }

    private func laneCenter(column: Int) -> CGFloat {
        return leftInset + CGFloat(column) * laneSpacing + laneSpacing * 0.5
    }
}
