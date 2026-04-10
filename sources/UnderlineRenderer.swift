//
//  UnderlineRenderer.swift
//  iTerm2SharedARC
//
//  Multi-pass underline renderer. Draws underline and strikethrough spans
//  as patterned quads, matching the visual output of the legacy text shader.
//

import Foundation
import simd

@objc(iTermUnderlineRendererTransientState)
class UnderlineRendererTransientState: iTermMetalCellRendererTransientState {
    struct Span {
        var row: Int32
        var startColumn: Int32
        var endColumn: Int32  // inclusive
        var style: Int32
        var isStrikethrough: Bool
        var isASCII: Bool
        var color: vector_float4
    }

    var underlineSpans = [Span]()
    var strikethroughSpans = [Span]()
    @objc var asciiUnderlineDescriptor = iTermMetalUnderlineDescriptor()
    @objc var nonAsciiUnderlineDescriptor = iTermMetalUnderlineDescriptor()
    @objc var strikethroughDescriptor = iTermMetalUnderlineDescriptor()
    @objc var asciiOffset: CGSize = .zero  // from text renderer, for underline position adjustment
    @objc var verticalOffset: CGFloat = 0

    @objc enum DrawMode: Int {
        case underlines
        case strikethrough
    }

    // Controls which spans are drawn. Set before each draw call.
    @objc var drawMode: DrawMode = .underlines

    var isEmpty: Bool { underlineSpans.isEmpty && strikethroughSpans.isEmpty }

    @objc func setSpans(underlineData: NSData?, strikethroughData: NSData?) {
        underlineSpans = Self.decodeSpans(underlineData)
        strikethroughSpans = Self.decodeSpans(strikethroughData)
    }

    private static func decodeSpans(_ data: NSData?) -> [Span] {
        guard let data, data.length > 0 else { return [] }
        let count = data.length / MemoryLayout<iTermMetalUnderlineSpan>.size
        var spans = [Span]()
        spans.reserveCapacity(count)
        let base = data.bytes.bindMemory(to: iTermMetalUnderlineSpan.self, capacity: count)
        for i in 0..<count {
            let s = base[i]
            let baseStyle = s.style & ~Int32(iTermMetalUnderlineSpanASCIIFlag)
            let isStrike = baseStyle == Int32(iTermMetalGlyphAttributesUnderlineStrikethrough.rawValue)
            let isASCII = (s.style & Int32(iTermMetalUnderlineSpanASCIIFlag)) != 0
            spans.append(Span(row: Int32(s.row),
                              startColumn: Int32(s.startColumn),
                              endColumn: Int32(s.endColumn),
                              style: baseStyle,
                              isStrikethrough: isStrike,
                              isASCII: isASCII,
                              color: s.color))
        }
        return spans
    }
}

// iTermUnderlineSpanInfo is defined in iTermShaderTypes.h and shared with Underline.metal.

@objc(iTermUnderlineRenderer)
class UnderlineRenderer: NSObject, iTermMetalCellRendererProtocol {
    private let renderer: iTermMetalCellRenderer
    private let spanInfoPool: iTermMetalBufferPool
    private let viewportPool: iTermMetalBufferPool
    private let cellBottomPool: iTermMetalBufferPool

    @objc(initWithDevice:)
    init(device: MTLDevice) {
        renderer = iTermMetalCellRenderer(
            device: device,
            vertexFunctionName: "iTermUnderlineVertexShader",
            fragmentFunctionName: "iTermUnderlineFragmentShader",
            blending: iTermMetalBlending.atop(),
            piuElementSize: 0,
            transientStateClass: UnderlineRendererTransientState.self)!
        spanInfoPool = iTermMetalBufferPool(device: device,
                                            bufferSize: MemoryLayout<iTermUnderlineSpanInfo>.size)
        viewportPool = iTermMetalBufferPool(device: device,
                                            bufferSize: MemoryLayout<vector_uint2>.size)
        cellBottomPool = iTermMetalBufferPool(device: device,
                                              bufferSize: MemoryLayout<Float>.size)
    }

    override init() {
        it_fatalError()
    }

    func createTransientStateStat() -> iTermMetalFrameDataStat {
        return .pqCreateUnderlineTS
    }

    var rendererDisabled: Bool { false }

    func createTransientState(forCellConfiguration configuration: iTermCellRenderConfiguration,
                              commandBuffer: MTLCommandBuffer) -> iTermMetalRendererTransientState? {
        return renderer.createTransientState(forCellConfiguration: configuration,
                                              commandBuffer: commandBuffer)
    }

    func draw(with frameData: iTermMetalFrameData, transientState: iTermMetalCellRendererTransientState) {
        guard let tState = transientState as? UnderlineRendererTransientState,
              !tState.isEmpty,
              let renderEncoder = frameData.renderEncoder else {
            return
        }

        let scale = Float(tState.configuration.scale)
        let cellWidth = Float(tState.cellConfiguration.cellSize.width)
        let cellHeight = Float(tState.cellConfiguration.cellSize.height)
        let cellHeightWithoutSpacing = Float(tState.cellConfiguration.cellSizeWithoutSpacing.height)
        let marginLeft = Float(tState.margins.left)
        // The text renderer's offset buffer uses margins.top for the y component.
        let marginTop = Float(tState.margins.top)
        let viewportSize = tState.configuration.viewportSize
        let gridHeight = Int(tState.cellConfiguration.gridSize.height)
        let verticalOffset = Float(tState.verticalOffset)

        // Match the text renderer's verticalShift (iTermTextRendererTransientState.mm:566).
        let verticalShift = Float(round(Double(cellHeight - cellHeightWithoutSpacing) / Double(2 * scale))) * scale

        let viewportBuffer = viewportPool.requestBuffer(
            from: tState.poolContext,
            withBytes: [viewportSize].withUnsafeBytes { Array($0) },
            checkIfChanged: true)

        let allSpans = tState.drawMode == .strikethrough ? tState.strikethroughSpans : tState.underlineSpans
        for span in allSpans {
            var descriptor: iTermMetalUnderlineDescriptor
            if span.isStrikethrough {
                descriptor = tState.strikethroughDescriptor
            } else if span.isASCII {
                descriptor = tState.asciiUnderlineDescriptor
                // ASCII glyphs are shifted by asciiOffset.height relative to non-ASCII.
                // Adjust the underline offset to match (iTermTextRendererTransientState.mm:278).
                descriptor.offset -= Float(tState.asciiOffset.height) / scale
            } else {
                descriptor = tState.nonAsciiUnderlineDescriptor
            }

            let underlineThickness = descriptor.thickness * scale
            // Positive underline offset moves up visually.
            let underlineOffset: Float
            if span.isStrikethrough {
                underlineOffset = cellHeight - descriptor.offset * scale
            } else if span.style == Int32(iTermMetalGlyphAttributesUnderlineDouble.rawValue) ||
                      span.style == Int32(iTermMetalGlyphAttributesUnderlineHyperlink.rawValue) {
                // Match the legacy double/hyperlink underline position from
                // iTermTextDrawingHelper.m:2905:
                //
                //   origin.y = rect.origin.y + cellSize.height - 2
                //
                // The legacy stroke center is 2 points from the cell bottom.
                // iTermShapeBuilder converts this to a pixel-aligned filled rect
                // via pixelAlignedRect(), which calls convertToDeviceSpace, rounds
                // each edge, then converts back. The formula below reproduces where
                // the legacy rect actually lands.
                //
                // --- Why -1.5? ---
                //
                // It is the sum of two corrections (-0.5 and -1.0):
                //
                // -0.5: VerticalCoverage (Underline.metal) maps each fragment to
                //   a cell-relative position with:
                //     originOfCellInPixelSpace = pixelPos.y + 0.5 - cellBottomY
                //   The +0.5 shifts pixel centers (at half-integer positions) up by
                //   half a pixel: a pixel at device position p from the cell bottom
                //   gets VerticalCoverage range [p+1, p+2] instead of [p, p+1].
                //   Subtracting 0.5 from the offset compensates.
                //
                // -1.0: The legacy renderer's pixelAlignedRect() rounds device-space
                //   coordinates via round(). In a window-backed CGContext, device y
                //   is NEGATIVE because macOS device space has y-up (Quartz) while
                //   the flipped view has y-down. C's round() rounds half-integers
                //   away from zero, and for negative values "away from zero" means
                //   more negative — the opposite direction vs. positive values.
                //   This shifts the pixel-aligned rect by 1 device pixel:
                //
                //     round(-60.5) = -61      (negative: rounds MORE negative)
                //     round( 60.5) =  61      (positive: rounds MORE positive)
                //
                //   The Metal renderer has no pixelAlignedRect or round() call, so
                //   it needs -1.0 to match where the legacy rect actually lands.
                //
                // --- Worked example (retina S=2, T=1, cellHeight=15pt) ---
                //
                //   Legacy renderer (iTermTextDrawingHelper.m):
                //     stroke center:  y = 30         (= cellTop 17 + 15 - 2)
                //     lineWidth:      0.5 pt
                //     fill rect:      y ∈ [29.75, 30.25]   (center ± halfWidth)
                //     device rect:    y ∈ [-60.5, -59.5]   (×-2, negative device space)
                //     after round():  y ∈ [-61, -60]        (round away from zero)
                //     back to user:   y ∈ [30, 30.5]
                //     cell bottom:    y = 32
                //     distance:       32 - 30.5 = 1.5 pt = 3 device px from cell bottom
                //                       → lights up pixel p=3
                //
                //   Metal renderer (this code + Underline.metal):
                //     underlineOffset = 2·2 + 1/2 - 1.5 = 3.0
                //     shader adjusts:  lineOffset = 3.0 - 1.0 = 2.0
                //     upper band:      VC [4.0, 5.0]   (= lineOffset + 2T to + 3T)
                //     pixel p=3 has:   VC [4, 5]        (= [p+1, p+2])
                //                       → full coverage on pixel p=3  ✓
                //
                //        cell bottom                              cell top
                //        (y=32)                                    (y=17)
                //     ┌──────────────────────────────────────────────────┐
                //     │ p=0 │ p=1 │ p=2 │ p=3 │ p=4 │ ...             │
                //     │     │lower│     │upper│     │                   │
                //     │     │ ██  │     │ ██  │     │                   │
                //     └──────────────────────────────────────────────────┘
                //       VC:  1  2   2  3  3  4  4  5   5  6
                //           lower band    upper band
                //           [2,  3]       [4,  5]
                underlineOffset = 2 * scale + underlineThickness / 2 - 1.5
            } else {
                underlineOffset = max(underlineThickness, cellHeight - descriptor.offset * scale)
            }

            // Compute cell position matching the text renderer exactly.
            // Text renderer (iTermTextRendererTransientState.mm:567):
            //   yOffset = (gridHeight - row - 1) * cellHeight + verticalShift
            // Then the offset buffer adds margins.top:
            //   cellOffset.y = yOffset + margins.top
            let rowFromBottom = Float(gridHeight - 1 - Int(span.row))
            let cellOriginY = rowFromBottom * cellHeight + verticalShift + marginTop + verticalOffset

            // Quad covers the full cell height for this row in pixel space (y=0 at viewport bottom).
            // Extend below the cell by a few pixels so the lower line of double/curly/hyperlink
            // underlines isn't clipped (they can sit at offset 0 — the very bottom of the cell).
            let quadLeft = marginLeft + Float(span.startColumn) * cellWidth
            let quadRight = marginLeft + Float(span.endColumn + 1) * cellWidth
            let quadBottom = cellOriginY - scale * 2
            let quadTop = cellOriginY + cellHeight

            if quadRight <= quadLeft || quadTop <= quadBottom {
                continue
            }

            // Build vertex buffer (6 vertices for two triangles).
            let vertices = [
                // Bottom-right, bottom-left, top-left
                iTermVertex(position: vector_float2(quadRight, quadBottom),
                            textureCoordinate: vector_float2(1, 1)),
                iTermVertex(position: vector_float2(quadLeft, quadBottom),
                            textureCoordinate: vector_float2(0, 1)),
                iTermVertex(position: vector_float2(quadLeft, quadTop),
                            textureCoordinate: vector_float2(0, 0)),
                // Bottom-right, top-left, top-right
                iTermVertex(position: vector_float2(quadRight, quadBottom),
                            textureCoordinate: vector_float2(1, 1)),
                iTermVertex(position: vector_float2(quadLeft, quadTop),
                            textureCoordinate: vector_float2(0, 0)),
                iTermVertex(position: vector_float2(quadRight, quadTop),
                            textureCoordinate: vector_float2(1, 0)),
            ]
            let vertexBuffer = vertices.withUnsafeBufferPointer { buf in
                renderer.verticesPool.requestBuffer(from: tState.poolContext,
                                                     withBytes: buf.baseAddress!,
                                                     checkIfChanged: true)
            }

            // Span info uniform.
            var spanInfo = iTermUnderlineSpanInfo(
                color: span.color,
                lineOffset: underlineOffset,
                lineThickness: underlineThickness,
                style: span.style,
                scale: scale
            )
            let spanInfoBuffer = withUnsafePointer(to: &spanInfo) { ptr in
                spanInfoPool.requestBuffer(from: tState.poolContext,
                                            withBytes: UnsafeRawPointer(ptr),
                                            checkIfChanged: true)
            }

            // Cell bottom Y in the coordinate system used by VerticalCoverage.
            // This is the cell's y offset for the underline position computation.
            var cellBottomY = cellOriginY
            let cellBottomBuffer = withUnsafePointer(to: &cellBottomY) { ptr in
                cellBottomPool.requestBuffer(from: tState.poolContext,
                                              withBytes: UnsafeRawPointer(ptr),
                                              checkIfChanged: true)
            }

            renderer.draw(with: tState,
                          renderEncoder: renderEncoder,
                          numberOfVertices: 6,
                          numberOfPIUs: 0,
                          vertexBuffers: [
                              NSNumber(value: iTermVertexInputIndexVertices.rawValue): vertexBuffer
                          ],
                          fragmentBuffers: [
                              NSNumber(value: 0): spanInfoBuffer,
                              NSNumber(value: 1): viewportBuffer,
                              NSNumber(value: 2): cellBottomBuffer,
                          ],
                          textures: [:])
        }
    }
}
