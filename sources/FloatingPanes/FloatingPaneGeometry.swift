//
//  FloatingPaneGeometry.swift
//  iTerm2SharedARC
//
//  Geometry for floating panes, with no views, so it can be tested exhaustively.
//
//  Coordinates are "visual": the origin is the top left of the tab's container and y grows
//  downward, whatever the container's flippedness. FloatingPaneGeometry.toVisual and fromVisual
//  convert.
//
//  A float's grid (columns by rows) is canonical and its frame is derived from it. Only an edge
//  drag goes from a frame to a grid, snapped to whole cells.
//

import AppKit

struct FloatingPaneGrid: Equatable, CustomStringConvertible {
    var columns: Int
    var rows: Int

    /// The smallest grid a float may have. It only prevents a degenerate frame.
    static let minimum = FloatingPaneGrid(columns: 2, rows: 2)

    var description: String {
        return "\(columns)x\(rows)"
    }

    func clamped(min lower: FloatingPaneGrid, max upper: FloatingPaneGrid) -> FloatingPaneGrid {
        return FloatingPaneGrid(columns: Swift.min(Swift.max(columns, lower.columns), Swift.max(upper.columns, lower.columns)),
                                rows: Swift.min(Swift.max(rows, lower.rows), Swift.max(upper.rows, lower.rows)))
    }
}

/// Converts between a float's grid and its frame.
struct FloatingPaneMetrics: Equatable {
    /// The size of one cell in points.
    var cellSize: CGSize

    /// Everything in a float's frame that is not cells: margins, scroller, title bar, status bar,
    /// and the outline on both sides.
    var chrome: CGSize

    func frameSize(for grid: FloatingPaneGrid) -> CGSize {
        return CGSize(width: CGFloat(grid.columns) * cellSize.width + chrome.width,
                      height: CGFloat(grid.rows) * cellSize.height + chrome.height)
    }

    /// The largest grid whose frame fits in `size`. Not clamped to the minimum.
    func grid(fitting size: CGSize) -> FloatingPaneGrid {
        let columns = Int(((size.width - chrome.width) / cellSize.width).rounded(.down))
        let rows = Int(((size.height - chrome.height) / cellSize.height).rounded(.down))
        return FloatingPaneGrid(columns: Swift.max(0, columns), rows: Swift.max(0, rows))
    }

    var minimumFrameSize: CGSize {
        return frameSize(for: .minimum)
    }
}

/// Which edges of a float an edge drag moves. In visual coordinates, top is minY.
struct FloatingPaneEdges: OptionSet, Equatable {
    let rawValue: Int
    static let left = FloatingPaneEdges(rawValue: 1 << 0)
    static let right = FloatingPaneEdges(rawValue: 1 << 1)
    static let top = FloatingPaneEdges(rawValue: 1 << 2)
    static let bottom = FloatingPaneEdges(rawValue: 1 << 3)
}

/// A float's placement: its frame in visual coordinates and its grid.
struct FloatingPanePlacement: Equatable, CustomStringConvertible {
    var frame: CGRect
    var grid: FloatingPaneGrid

    var description: String {
        return "\(grid) at \(NSStringFromRect(frame))"
    }
}

enum FloatingPaneGeometry {
    /// A new float is this fraction of the container's size in each dimension, rounded down to
    /// whole cells.
    static let initialFraction: CGFloat = 0.8

    // MARK: - Coordinates

    /// Converts a rect in a container's own coordinates to visual coordinates.
    static func toVisual(_ rect: CGRect, containerHeight: CGFloat, containerIsFlipped: Bool) -> CGRect {
        if containerIsFlipped {
            return rect
        }
        return CGRect(x: rect.minX, y: containerHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Converts a rect in visual coordinates to a container's own coordinates.
    static func fromVisual(_ rect: CGRect, containerHeight: CGFloat, containerIsFlipped: Bool) -> CGRect {
        // The conversion is its own inverse.
        return toVisual(rect, containerHeight: containerHeight, containerIsFlipped: containerIsFlipped)
    }

    // MARK: - Creation

    /// The largest grid that fits in the container, at least the minimum.
    static func maximumGrid(container: CGSize, metrics: FloatingPaneMetrics) -> FloatingPaneGrid {
        return metrics.grid(fitting: container).clamped(min: .minimum, max: metrics.grid(fitting: container))
    }

    /// A new float: 80% of the container, rounded down to whole cells, centered.
    static func initialPlacement(container: CGSize, metrics: FloatingPaneMetrics) -> FloatingPanePlacement {
        let target = CGSize(width: container.width * initialFraction,
                            height: container.height * initialFraction)
        let grid = metrics.grid(fitting: target).clamped(min: .minimum,
                                                         max: maximumGrid(container: container, metrics: metrics))
        let size = metrics.frameSize(for: grid)
        let origin = CGPoint(x: ((container.width - size.width) / 2).rounded(.down),
                             y: ((container.height - size.height) / 2).rounded(.down))
        return FloatingPanePlacement(frame: clamp(CGRect(origin: origin, size: size), in: container),
                                     grid: grid)
    }

    // MARK: - Clamping

    /// Moves `frame` the least distance that puts it inside the container. If it is larger than
    /// the container, its top left goes to the container's top left so the title bar stays
    /// reachable.
    static func clamp(_ frame: CGRect, in container: CGSize) -> CGRect {
        var result = frame
        result.origin.x = min(result.origin.x, container.width - result.width)
        result.origin.y = min(result.origin.y, container.height - result.height)
        result.origin.x = max(0, result.origin.x)
        result.origin.y = max(0, result.origin.y)
        return result
    }

    // MARK: - Moving

    /// A move by `delta` from `start`, clamped to the container. The grid does not change.
    static func move(_ start: CGRect, by delta: CGSize, in container: CGSize) -> CGRect {
        return clamp(start.offsetBy(dx: delta.width, dy: delta.height), in: container)
    }

    // MARK: - Resizing

    /// An edge or corner drag. `delta` is how far the pointer has moved since the drag began, in
    /// visual coordinates. The result is snapped to whole cells, at least the minimum grid, and no
    /// larger than fits between the fixed edges and the container's edges.
    static func resize(_ start: FloatingPanePlacement,
                       edges: FloatingPaneEdges,
                       by delta: CGSize,
                       in container: CGSize,
                       metrics: FloatingPaneMetrics) -> FloatingPanePlacement {
        var desired = start.frame
        if edges.contains(.left) {
            desired.origin.x += delta.width
            desired.size.width -= delta.width
        } else if edges.contains(.right) {
            desired.size.width += delta.width
        }
        if edges.contains(.top) {
            desired.origin.y += delta.height
            desired.size.height -= delta.height
        } else if edges.contains(.bottom) {
            desired.size.height += delta.height
        }

        // The most room each axis has, holding the opposite edge fixed.
        let room = CGSize(width: edges.contains(.left) ? start.frame.maxX : container.width - start.frame.minX,
                          height: edges.contains(.top) ? start.frame.maxY : container.height - start.frame.minY)
        let maxGrid = metrics.grid(fitting: room)
        var grid = metrics.grid(fitting: desired.size).clamped(min: .minimum, max: maxGrid)
        if !edges.contains(.left) && !edges.contains(.right) {
            grid.columns = start.grid.columns
        }
        if !edges.contains(.top) && !edges.contains(.bottom) {
            grid.rows = start.grid.rows
        }
        let size = metrics.frameSize(for: grid)
        let origin = CGPoint(x: edges.contains(.left) ? start.frame.maxX - size.width : start.frame.minX,
                             y: edges.contains(.top) ? start.frame.maxY - size.height : start.frame.minY)
        return FloatingPanePlacement(frame: CGRect(origin: origin, size: size), grid: grid)
    }

    /// Grows or shrinks the grid by whole cells, keeping the top left fixed where there is room.
    /// Used by the keyboard resize commands.
    static func resize(_ start: FloatingPanePlacement,
                       byColumns columns: Int,
                       rows: Int,
                       in container: CGSize,
                       metrics: FloatingPaneMetrics) -> FloatingPanePlacement {
        let maxGrid = maximumGrid(container: container, metrics: metrics)
        let grid = FloatingPaneGrid(columns: start.grid.columns + columns,
                                    rows: start.grid.rows + rows).clamped(min: .minimum, max: maxGrid)
        let frame = CGRect(origin: start.frame.origin, size: metrics.frameSize(for: grid))
        return FloatingPanePlacement(frame: clamp(frame, in: container), grid: grid)
    }

    // MARK: - Container changes

    /// Places a float after its container changes size or its metrics change (for example, a font
    /// change). The grid is kept: `desiredGrid` if it was shrunk earlier, else the current grid. It
    /// shrinks only when the container is too small, and the caller should remember the desired
    /// grid so it comes back when there is room. A float touching the right or bottom edge stays
    /// there; otherwise its top left stays put. Finally it is clamped.
    static func placement(after start: FloatingPanePlacement,
                          desiredGrid: FloatingPaneGrid?,
                          oldContainer: CGSize,
                          newContainer: CGSize,
                          metrics: FloatingPaneMetrics) -> FloatingPanePlacement {
        let wanted = desiredGrid ?? start.grid
        let grid = wanted.clamped(min: .minimum, max: maximumGrid(container: newContainer, metrics: metrics))
        let size = metrics.frameSize(for: grid)
        let (touchesRight, touchesBottom) = anchoredEdges(of: start.frame, in: oldContainer)
        let origin = CGPoint(x: touchesRight ? newContainer.width - size.width : start.frame.minX,
                             y: touchesBottom ? newContainer.height - size.height : start.frame.minY)
        return FloatingPanePlacement(frame: clamp(CGRect(origin: origin, size: size), in: newContainer),
                                     grid: grid)
    }

    /// Whether a frame touches its container's right and bottom edges, so it stays against them
    /// when the container changes size.
    static func anchoredEdges(of frame: CGRect, in container: CGSize) -> (right: Bool, bottom: Bool) {
        let tolerance: CGFloat = 0.5
        return (abs(frame.maxX - container.width) < tolerance,
                abs(frame.maxY - container.height) < tolerance)
    }

    /// The position to remember after `placement(after:...)`, per axis: where the float was if
    /// clamping moved it, so it goes back there when there is room again, else nil. Clamping can
    /// push a float against an edge; without this it would then count as anchored there.
    static func desiredOrigin(start: CGRect,
                              result: CGRect,
                              oldContainer: CGSize) -> (x: CGFloat?, y: CGFloat?) {
        let (right, bottom) = anchoredEdges(of: start, in: oldContainer)
        return (x: (right || result.minX == start.minX) ? nil : start.minX,
                y: (bottom || result.minY == start.minY) ? nil : start.minY)
    }

    /// The desired grid to remember after `placement(after:...)`: the wanted grid if the float had
    /// to shrink, else nil.
    static func desiredGrid(wanted: FloatingPaneGrid, actual: FloatingPaneGrid) -> FloatingPaneGrid? {
        return wanted == actual ? nil : wanted
    }
}
