//
//  iTermBlurRowBuffer.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/12/26.
//

import AppKit
import CoreImage

/// Buffers rows of pixel data to apply blur effects that require neighboring rows.
/// For blur redactions, we need ceil(blurRadius) rows of context on each side.
@objc(iTermBlurRowBuffer)
class iTermBlurRowBuffer: NSObject {
    private let radius: Int
    private let width: Int
    private let bytesPerRow: Int

    /// Ring buffer of rows
    private var rowBuffer: [[UInt8]]

    /// Index of the next slot to fill in the ring buffer
    private var nextSlot: Int = 0

    /// Number of rows currently in the buffer
    private var rowCount: Int = 0

    /// Total rows processed so far
    private var totalRowsProcessed: Int = 0

    /// Total rows expected
    private let totalRows: Int

    /// Redaction rects in image coordinates (Y=0 at bottom)
    private var redactionRects: [CGRect] = []

    /// The blur radius in points
    private let blurRadius: CGFloat

    /// Cached CIContext for blur rendering
    private lazy var ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Initialize the buffer.
    /// @param blurRadius The blur radius in points
    /// @param width Image width in pixels
    /// @param totalRows Total number of rows in the image
    @objc init(blurRadius: CGFloat, width: Int, totalRows: Int) {
        self.blurRadius = blurRadius
        self.radius = Int(ceil(blurRadius))
        self.width = width
        self.totalRows = totalRows
        self.bytesPerRow = width * 4  // RGBA

        // We need (2 * radius + 1) rows in the buffer to blur the center row
        let bufferSize = 2 * self.radius + 1
        self.rowBuffer = Array(repeating: [UInt8](repeating: 0, count: bytesPerRow),
                               count: bufferSize)
        self.nextSlot = 0
        self.rowCount = 0
        self.totalRowsProcessed = 0

        super.init()
    }

    /// Set the redaction rects. Should be called before adding rows.
    /// @param rects Rects in image coordinates (Y=0 at bottom, in pixels)
    @objc func setRedactionRects(_ rects: [NSValue]) {
        self.redactionRects = rects.map { $0.rectValue }
    }

    /// Add a row of pixel data to the buffer.
    /// @param rowData Pointer to RGBA pixel data for one row
    /// @return The blurred center row if buffer is full, nil otherwise
    @objc func addRow(_ rowData: UnsafePointer<UInt8>) -> Data? {
        // Copy row data into the ring buffer
        let slot = nextSlot
        rowData.withMemoryRebound(to: UInt8.self, capacity: bytesPerRow) { ptr in
            for i in 0..<bytesPerRow {
                rowBuffer[slot][i] = ptr[i]
            }
        }

        nextSlot = (nextSlot + 1) % rowBuffer.count
        rowCount = min(rowCount + 1, rowBuffer.count)
        totalRowsProcessed += 1

        // Check if we have enough rows to emit the center row
        let centerIndex = totalRowsProcessed - radius - 1

        // We can emit a blurred row when we have enough context
        // (or we're at the edges and need to emit with partial context)
        if centerIndex >= 0 && centerIndex < totalRows {
            // Check if we have enough rows buffered
            let haveEnoughContext = rowCount == rowBuffer.count || totalRowsProcessed >= radius + 1
            if haveEnoughContext && centerIndex >= 0 {
                return emitBlurredRow(at: centerIndex)
            }
        }

        return nil
    }

    /// Flush remaining rows from the buffer.
    /// Call this after all input rows have been added.
    /// @return Array of blurred rows for the remaining buffered content
    @objc func flush() -> [Data] {
        var results: [Data] = []

        // Emit remaining rows that haven't been emitted yet
        let startIndex = max(0, totalRowsProcessed - rowCount)

        for i in 0..<rowCount {
            let rowIndex = startIndex + i
            let centerIndex = rowIndex

            // Skip rows we've already emitted
            if centerIndex >= totalRowsProcessed - radius - 1 && centerIndex < totalRows {
                continue  // Already emitted during addRow
            }

            if centerIndex < totalRows {
                if let blurred = emitBlurredRow(at: centerIndex) {
                    results.append(blurred)
                }
            }
        }

        // Handle the last `radius` rows that couldn't be emitted during addRow
        let lastEmitted = totalRowsProcessed - radius - 1
        for centerIndex in (lastEmitted + 1)..<totalRows {
            if let blurred = emitBlurredRow(at: centerIndex) {
                results.append(blurred)
            }
        }

        return results
    }

    /// Emit the blurred row at the given center index
    private func emitBlurredRow(at centerIndex: Int) -> Data? {
        // Get the center row from the buffer
        let slotOffset = totalRowsProcessed - centerIndex - 1
        let centerSlot = (nextSlot - slotOffset - 1 + rowBuffer.count) % rowBuffer.count
        guard centerSlot >= 0 && centerSlot < rowBuffer.count else {
            return nil
        }

        let centerRow = rowBuffer[centerSlot]

        // Check if any redaction rects intersect this row
        let rowY = CGFloat(totalRows - centerIndex - 1)  // Convert to image coords (Y=0 at bottom)

        let intersectingRects = redactionRects.filter { rect in
            rowY >= rect.minY && rowY < rect.maxY
        }

        if intersectingRects.isEmpty {
            // No blur needed, return the row as-is
            return Data(centerRow)
        }

        // Apply blur to the intersecting regions
        // For simplicity, we'll blur the entire row and composite only the redaction areas
        // A more optimized version would only blur the specific regions

        // Create a CGImage from the row
        guard let blurredRowData = applyBlurToRow(centerRow, intersectingRects: intersectingRects) else {
            return Data(centerRow)
        }

        return blurredRowData
    }

    /// Apply blur to specific regions of a row
    private func applyBlurToRow(_ rowData: [UInt8], intersectingRects: [CGRect]) -> Data? {
        // For now, do a simple per-pixel blur approximation
        // This is a box blur which is faster than Gaussian but visually similar for our purposes

        var result = rowData

        for rect in intersectingRects {
            let startX = max(0, Int(rect.minX))
            let endX = min(width, Int(rect.maxX))

            // Apply horizontal box blur to this region
            for x in startX..<endX {
                var r: Int = 0, g: Int = 0, b: Int = 0, a: Int = 0
                var count: Int = 0

                // Sample neighboring pixels
                for dx in -radius...radius {
                    let sx = x + dx
                    if sx >= 0 && sx < width {
                        let offset = sx * 4
                        r += Int(rowData[offset])
                        g += Int(rowData[offset + 1])
                        b += Int(rowData[offset + 2])
                        a += Int(rowData[offset + 3])
                        count += 1
                    }
                }

                if count > 0 {
                    let offset = x * 4
                    result[offset] = UInt8(r / count)
                    result[offset + 1] = UInt8(g / count)
                    result[offset + 2] = UInt8(b / count)
                    result[offset + 3] = UInt8(a / count)
                }
            }
        }

        return Data(result)
    }
}

/// A simpler solid color row buffer that doesn't need buffering
@objc(iTermSolidColorRowBuffer)
class iTermSolidColorRowBuffer: NSObject {
    private let width: Int
    private let bytesPerRow: Int
    private let color: NSColor
    private var redactionRects: [CGRect] = []
    private var currentRowIndex: Int = 0
    private let totalRows: Int

    /// The RGBA components of the fill color
    private let colorComponents: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)

    @objc init(color: NSColor, width: Int, totalRows: Int) {
        self.color = color
        self.width = width
        self.totalRows = totalRows
        self.bytesPerRow = width * 4

        // Convert color to RGBA
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        self.colorComponents = (
            r: UInt8(rgb.redComponent * 255),
            g: UInt8(rgb.greenComponent * 255),
            b: UInt8(rgb.blueComponent * 255),
            a: UInt8(rgb.alphaComponent * 255)
        )

        super.init()
    }

    /// Set the redaction rects. Should be called before processing rows.
    /// @param rects Rects in image coordinates (Y=0 at bottom, in pixels)
    @objc func setRedactionRects(_ rects: [NSValue]) {
        self.redactionRects = rects.map { $0.rectValue }
    }

    /// Process a row, applying solid color to redaction regions.
    /// @param rowData Pointer to RGBA pixel data for one row
    /// @return The processed row data
    @objc func processRow(_ rowData: UnsafePointer<UInt8>) -> Data {
        var result = [UInt8](repeating: 0, count: bytesPerRow)

        // Copy input row
        for i in 0..<bytesPerRow {
            result[i] = rowData[i]
        }

        // Check if any redaction rects intersect this row
        let rowY = CGFloat(totalRows - currentRowIndex - 1)  // Convert to image coords

        let intersectingRects = redactionRects.filter { rect in
            rowY >= rect.minY && rowY < rect.maxY
        }

        // Apply solid color to intersecting regions
        for rect in intersectingRects {
            let startX = max(0, Int(rect.minX))
            let endX = min(width, Int(rect.maxX))

            for x in startX..<endX {
                let offset = x * 4
                result[offset] = colorComponents.r
                result[offset + 1] = colorComponents.g
                result[offset + 2] = colorComponents.b
                result[offset + 3] = colorComponents.a
            }
        }

        currentRowIndex += 1
        return Data(result)
    }

    /// Reset for reprocessing
    @objc func reset() {
        currentRowIndex = 0
    }
}
