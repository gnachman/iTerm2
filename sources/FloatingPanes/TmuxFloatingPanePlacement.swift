//
//  TmuxFloatingPanePlacement.swift
//  iTerm2SharedARC
//
//  Places a tmux floating pane, whose position and size the server owns, over the tiled panes.
//
//  There is no global mapping from tmux cells to points: each tiled pane adds margins and chrome,
//  and a divider is a point wide where tmux uses a whole cell. So a float is anchored locally. Its
//  first content cell goes exactly over the same cell of the tiled pane that contains it, and when
//  no tiled pane does (a divider cell, a negative offset, past the last pane), over the nearest
//  tiled pane's grid extended by whole cells. A window with only floats uses a plain grid from the
//  container's origin. The float's chrome sits around its content and may hang outside the tab,
//  where it is clipped: tmux owns the content rectangle.
//

import Foundation

/// A tiled pane's place in tmux's grid and where its first cell is on screen.
@objc(iTermTmuxFloatAnchor)
final class TmuxFloatAnchor: NSObject {
    /// The pane's cell rectangle in the window, in tmux's cells.
    let cells: FloatingPaneCellRect

    /// The top left of the pane's first cell, in visual coordinates (top left origin, y down) of
    /// the floats' container.
    let origin: CGPoint

    let cellSize: CGSize

    @objc init(column: Int, row: Int, columns: Int, rows: Int, origin: CGPoint, cellSize: CGSize) {
        cells = FloatingPaneCellRect(column: column, row: row, columns: columns, rows: rows)
        self.origin = origin
        self.cellSize = cellSize
    }
}

struct FloatingPaneCellRect: Equatable {
    var column: Int
    var row: Int
    var columns: Int
    var rows: Int

    func contains(column c: Int, row r: Int) -> Bool {
        return c >= column && c < column + columns && r >= row && r < row + rows
    }

    /// How many cells (column, row) is outside this rectangle, 0 if inside.
    func distance(column c: Int, row r: Int) -> Int {
        let dx = c < column ? column - c : (c >= column + columns ? c - (column + columns - 1) : 0)
        let dy = r < row ? row - r : (r >= row + rows ? r - (row + rows - 1) : 0)
        return dx + dy
    }
}

enum TmuxFloatingPanePlacement {
    /// Where tmux cell (column, row) is on screen, in visual container coordinates.
    static func point(column: Int,
                      row: Int,
                      anchors: [TmuxFloatAnchor],
                      fallbackOrigin: CGPoint,
                      fallbackCellSize: CGSize) -> CGPoint {
        let anchor = anchors.first { $0.cells.contains(column: column, row: row) } ??
            anchors.min { $0.cells.distance(column: column, row: row) < $1.cells.distance(column: column, row: row) }
        guard let anchor else {
            // Only floats: a plain grid where a tiled pane filling the tab would put its cells.
            return CGPoint(x: fallbackOrigin.x + CGFloat(column) * fallbackCellSize.width,
                           y: fallbackOrigin.y + CGFloat(row) * fallbackCellSize.height)
        }
        return CGPoint(x: anchor.origin.x + CGFloat(column - anchor.cells.column) * anchor.cellSize.width,
                       y: anchor.origin.y + CGFloat(row - anchor.cells.row) * anchor.cellSize.height)
    }
}

@objc(iTermTmuxFloatingPanePlacer)
final class TmuxFloatingPanePlacer: NSObject {
    /// Gives the float tmux's grid and puts its first content cell over tmux cell (column, row).
    @objc(placeFloatingPane:session:column:row:columns:rows:anchors:)
    static func place(_ pane: iTermFloatingPaneView,
                      session: PTYSession,
                      column: Int,
                      row: Int,
                      columns: Int,
                      rows: Int,
                      anchors: [TmuxFloatAnchor]) {
        guard let container = pane.superview,
              let textview = session.textview,
              let metrics = FloatingPaneLayout.metrics(for: session) else {
            return
        }
        let grid = FloatingPaneGrid(columns: max(1, columns), rows: max(1, rows))
        let target = TmuxFloatingPanePlacement.point(column: column,
                                                     row: row,
                                                     anchors: anchors,
                                                     fallbackOrigin: CGPoint(x: CGFloat(iTermPreferences.sideMargins()),
                                                                             y: CGFloat(iTermPreferences.topBottomMargins())),
                                                     fallbackCellSize: metrics.cellSize)
        // Put the frame anywhere with the right size, then see where the first cell landed and
        // shift by the difference. The content's offset in the frame depends on the title bar,
        // margins and outline, which are easier to measure than to add up.
        let size = metrics.frameSize(for: grid)
        let current = FloatingPaneLayout.visualOutlineFrame(of: pane).origin
        FloatingPaneLayout.apply(FloatingPanePlacement(frame: CGRect(origin: current, size: size), grid: grid),
                                 to: pane,
                                 session: session)
        pane.layoutSubtreeIfNeeded()
        let gridOrigin = visual(textview.gridOrigin(in: container), in: container)
        let origin = CGPoint(x: current.x + target.x - gridOrigin.x,
                             y: current.y + target.y - gridOrigin.y)
        DLog("Place tmux float \(session) at cell \(column),\(row) \(grid): target=\(target) frame origin=\(origin)")
        FloatingPaneLayout.apply(FloatingPanePlacement(frame: CGRect(origin: origin, size: size), grid: grid),
                                 to: pane,
                                 session: session)
        pane.desiredGrid = nil
    }

    /// The anchor for a tiled pane: its cells and where its first cell is in the container.
    @objc(anchorForSession:column:row:columns:rows:container:)
    static func anchor(for session: PTYSession,
                       column: Int,
                       row: Int,
                       columns: Int,
                       rows: Int,
                       container: NSView) -> TmuxFloatAnchor? {
        guard let textview = session.textview else {
            return nil
        }
        return TmuxFloatAnchor(column: column,
                               row: row,
                               columns: columns,
                               rows: rows,
                               origin: visual(textview.gridOrigin(in: container), in: container),
                               cellSize: CGSize(width: textview.charWidth, height: textview.lineHeight))
    }

    private static func visual(_ point: NSPoint, in container: NSView) -> CGPoint {
        return container.isFlipped ? point : CGPoint(x: point.x, y: container.bounds.height - point.y)
    }
}
