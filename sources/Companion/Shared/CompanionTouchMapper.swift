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
}
