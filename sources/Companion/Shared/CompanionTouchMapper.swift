//
//  CompanionTouchMapper.swift
//  iTerm2
//
//  Maps a touch in the live video view to an absolute terminal point, so the
//  phone can express a selection the host understands. The view shows the encoded
//  image aspect-fit (letterboxed and centered, never distorted -- see
//  CompanionVideoView's .resizeAspect), so the transform is: undo the letterbox
//  and scale to get an encoded-image pixel, subtract the margin and divide by the
//  cell size to get (column, row), then add liveTop to get the absolute line.
//
//  Pure and UI-free (operates on CGPoint/CGSize) so it is unit-tested directly;
//  the phone supplies the current view size and touch location.
//

import CoreGraphics
import Foundation

struct CompanionTouchMapper {
    /// Encoded frame dimensions (the units of cellGeometry).
    let imageSize: CGSize
    let cellGeometry: CompanionCellGeometry
    let columns: Int
    let rows: Int
    /// Absolute line of the top visible row for the frame being touched.
    let liveTop: Int64

    /// Map a touch at `viewPoint` in a view of `viewSize` to an absolute terminal
    /// point, clamped to the grid. Degenerate geometry returns the top-left cell.
    func selectionPoint(viewPoint: CGPoint, viewSize: CGSize) -> CompanionSelectionPoint {
        guard imageSize.width > 0, imageSize.height > 0,
              cellGeometry.cellWidth > 0, cellGeometry.cellHeight > 0,
              viewSize.width > 0, viewSize.height > 0,
              columns > 0, rows > 0 else {
            return CompanionSelectionPoint(absLine: liveTop, column: 0)
        }
        // Aspect-fit: scale by the smaller ratio, center the result.
        let scale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let offsetX = (viewSize.width - imageSize.width * scale) / 2
        let offsetY = (viewSize.height - imageSize.height * scale) / 2
        // View point -> encoded image pixel.
        let px = (viewPoint.x - offsetX) / scale
        let py = (viewPoint.y - offsetY) / scale
        let col = Int(((px - cellGeometry.leftMargin) / cellGeometry.cellWidth).rounded(.down))
        let row = Int(((py - cellGeometry.topMargin) / cellGeometry.cellHeight).rounded(.down))
        let clampedCol = min(max(col, 0), columns - 1)
        let clampedRow = min(max(row, 0), rows - 1)
        return CompanionSelectionPoint(absLine: liveTop + Int64(clampedRow), column: clampedCol)
    }

    /// The center of a cell in encoded-image pixels. The magnifier centers here
    /// (the cell the selection is at) rather than the raw finger, so the magnified
    /// caret lines up with the selection instead of sitting at a sub-cell offset.
    func cellCenterImagePoint(column: Int, absLine: Int64) -> CGPoint {
        let x = cellGeometry.leftMargin + (Double(column) + 0.5) * cellGeometry.cellWidth
        let y = cellGeometry.topMargin + (Double(absLine - liveTop) + 0.5) * cellGeometry.cellHeight
        return CGPoint(x: x, y: y)
    }

    /// The continuous (unquantized, unclamped) encoded-image pixel under a touch.
    func imagePoint(viewPoint: CGPoint, viewSize: CGSize) -> CGPoint? {
        guard imageSize.width > 0, imageSize.height > 0,
              viewSize.width > 0, viewSize.height > 0 else {
            return nil
        }
        let scale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let offsetX = (viewSize.width - imageSize.width * scale) / 2
        let offsetY = (viewSize.height - imageSize.height * scale) / 2
        return CGPoint(x: (viewPoint.x - offsetX) / scale, y: (viewPoint.y - offsetY) / scale)
    }

    /// The inverse: the view-space point of a grid corner, for placing selection
    /// handles. `rightEdge`/`bottomEdge` move the point to the cell's right/bottom
    /// (the end handle sits at the bottom-right of the last selected cell, the
    /// start handle at the top-left of the first). Returns nil for degenerate
    /// geometry.
    func viewPoint(column: Int, absLine: Int64, rightEdge: Bool, bottomEdge: Bool,
                   viewSize: CGSize) -> CGPoint? {
        guard imageSize.width > 0, imageSize.height > 0,
              viewSize.width > 0, viewSize.height > 0 else {
            return nil
        }
        let scale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let offsetX = (viewSize.width - imageSize.width * scale) / 2
        let offsetY = (viewSize.height - imageSize.height * scale) / 2
        let row = Double(absLine - liveTop)
        let imageX = cellGeometry.leftMargin + (Double(column) + (rightEdge ? 1 : 0)) * cellGeometry.cellWidth
        let imageY = cellGeometry.topMargin + (row + (bottomEdge ? 1 : 0)) * cellGeometry.cellHeight
        return CGPoint(x: imageX * scale + offsetX, y: imageY * scale + offsetY)
    }
}
