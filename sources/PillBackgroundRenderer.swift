//
//  PillBackgroundRenderer.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 1/31/26.
//

import AppKit
import simd

@objc(iTermPillBackgroundRendererTransientState)
class PillBackgroundRendererTransientState: iTermMetalCellRendererTransientState {
    fileprivate struct PillInfo: CustomDebugStringConvertible {
        var debugDescription: String {
            "rect=\(rect) dividers=\(dividerXPositions) pressed=\(pressedSegmentIndex) line=\(line)"
        }
        var rect: NSRect  // In points. Note: origin.y is relative to row 0 without margins
        var dividerXPositions: [CGFloat]  // In points, relative to rect.origin.x
        var foregroundColor: vector_float4
        var backgroundColor: vector_float4
        var pressedSegmentIndex: Int  // -1 if none pressed
        var line: Int  // Screen line (0-based from top of visible area)
    }
    fileprivate var pills: [PillInfo] = []

    @objc(addPillWithRect:dividerXPositions:foregroundColor:backgroundColor:pressedSegmentIndex:line:)
    func addPill(rect: NSRect,
                 dividerXPositions: [NSNumber],
                 foregroundColor: vector_float4,
                 backgroundColor: vector_float4,
                 pressedSegmentIndex: Int,
                 line: Int) {
        pills.append(PillInfo(
            rect: rect,
            dividerXPositions: dividerXPositions.map { CGFloat($0.doubleValue) },
            foregroundColor: foregroundColor,
            backgroundColor: backgroundColor,
            pressedSegmentIndex: pressedSegmentIndex,
            line: line))
    }

    override func writeDebugInfo(toFolder folder: URL) {
        super.writeDebugInfo(toFolder: folder)
        let s = "pills=\(pills.map { $0.debugDescription })"
        try? s.write(to: folder.appendingPathComponent("state.txt"), atomically: false, encoding: .utf8)
    }
}

/// Cache key for pill textures, wrapped as an NSObject for use with iTermCache.
@objc(iTermPillTextureCacheKey)
private class PillTextureCacheKey: NSObject, NSCopying {
    let size: NSSize
    let dividerXPositions: [CGFloat]
    let foregroundColor: vector_float4
    let backgroundColor: vector_float4
    let pressedSegmentIndex: Int

    init(size: NSSize,
         dividerXPositions: [CGFloat],
         foregroundColor: vector_float4,
         backgroundColor: vector_float4,
         pressedSegmentIndex: Int) {
        self.size = size
        self.dividerXPositions = dividerXPositions
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
        self.pressedSegmentIndex = pressedSegmentIndex
    }

    func copy(with zone: NSZone? = nil) -> Any {
        return PillTextureCacheKey(size: size,
                                   dividerXPositions: dividerXPositions,
                                   foregroundColor: foregroundColor,
                                   backgroundColor: backgroundColor,
                                   pressedSegmentIndex: pressedSegmentIndex)
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(size.width)
        hasher.combine(size.height)
        for pos in dividerXPositions {
            hasher.combine(pos)
        }
        hasher.combine(foregroundColor.x)
        hasher.combine(foregroundColor.y)
        hasher.combine(foregroundColor.z)
        hasher.combine(foregroundColor.w)
        hasher.combine(backgroundColor.x)
        hasher.combine(backgroundColor.y)
        hasher.combine(backgroundColor.z)
        hasher.combine(backgroundColor.w)
        hasher.combine(pressedSegmentIndex)
        return hasher.finalize()
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? PillTextureCacheKey else { return false }
        return size == other.size &&
               dividerXPositions == other.dividerXPositions &&
               simd_equal(foregroundColor, other.foregroundColor) &&
               simd_equal(backgroundColor, other.backgroundColor) &&
               pressedSegmentIndex == other.pressedSegmentIndex
    }
}

@objc(iTermPillBackgroundRenderer)
class PillBackgroundRenderer: NSObject, iTermMetalCellRendererProtocol {
    private let renderer: iTermMetalCellRenderer
    private let textureCache: iTermCache<PillTextureCacheKey, MTLTexture>
    private var texturePool = iTermTexturePool()

    @objc(initWithDevice:)
    init(device: MTLDevice) {
        textureCache = iTermCache(capacity: 1000)
        // Reuse the terminal button shaders since we're just rendering textured quads
        renderer = iTermMetalCellRenderer(
            device: device,
            vertexFunctionName: "iTermTerminalButtonVertexShader",
            fragmentFunctionName: "iTermTerminalButtonFragmentShader",
            blending: iTermMetalBlending.premultipliedCompositing(),
            piuElementSize: 0,
            transientStateClass: PillBackgroundRendererTransientState.self)!
    }

    var rendererDisabled: Bool { false }

    func createTransientStateStat() -> iTermMetalFrameDataStat {
        .pqCreateButtonsTS
    }

    func draw(with frameData: iTermMetalFrameData,
              transientState: iTermMetalCellRendererTransientState) {
        guard let renderEncoder = frameData.renderEncoder else {
            return
        }
        let tState = transientState as! PillBackgroundRendererTransientState
        for pill in tState.pills {
            DLog("Drawing pill: line=\(pill.line) rect=\(pill.rect) gridHeight=\(tState.cellConfiguration.gridSize.height) cellHeight=\(tState.cellConfiguration.cellSize.height) bottomInset=\(tState.margins.top)")
            drawPill(pill, renderEncoder: renderEncoder, tState: tState)
        }
    }

    private func vertexBuffer(pill: PillBackgroundRendererTransientState.PillInfo,
                              tState: PillBackgroundRendererTransientState) -> MTLBuffer {
        let textureFrame = CGRect(x: 0, y: 0, width: 1, height: 1)
        let scale = tState.configuration.scale
        let cellHeight = tState.cellConfiguration.cellSize.height
        let gridHeight = Int(tState.cellConfiguration.gridSize.height)
        let bottomInset = tState.margins.top

        // Calculate Y position from line number, same as TerminalButtonRenderer
        let y = CGFloat(gridHeight - pill.line - 1) * cellHeight + bottomInset

        DLog("vertexBuffer: gridHeight=\(gridHeight) line=\(pill.line) cellHeight=\(cellHeight) bottomInset=\(bottomInset) scale=\(scale) -> y=\(y)")

        // Build the frame exactly like TerminalButtonRenderer does:
        // x is scaled, y is calculated (not scaled again), width and height are scaled
        let frame = NSRect(
            x: pill.rect.origin.x * scale,
            y: y,
            width: pill.rect.width * scale,
            height: pill.rect.height * scale
        )
        DLog("vertexBuffer frame: \(frame)")

        let quad = frame

        let bottomRight = iTermVertex(position: vector_float2(Float(quad.maxX),
                                                              Float(quad.minY)),
                                      textureCoordinate: vector_float2(Float(textureFrame.maxX),
                                                                       Float(textureFrame.maxY)))
        let bottomLeft = iTermVertex(position: vector_float2(Float(quad.minX),
                                                             Float(quad.minY)),
                                     textureCoordinate: vector_float2(Float(textureFrame.minX),
                                                                      Float(textureFrame.maxY)))
        let topLeft = iTermVertex(position: vector_float2(Float(quad.minX),
                                                          Float(quad.maxY)),
                                  textureCoordinate: vector_float2(Float(textureFrame.minX),
                                                                   Float(textureFrame.minY)))
        let topRight = iTermVertex(position: vector_float2(Float(quad.maxX),
                                                           Float(quad.maxY)),
                                   textureCoordinate: vector_float2(Float(textureFrame.maxX),
                                                                    Float(textureFrame.minY)))
        let vertices = [
            bottomRight, bottomLeft, topLeft,
            bottomRight, topLeft, topRight
        ]
        return vertices.withUnsafeBytes { pointer in
            let byteArray = Array(pointer.bindMemory(to: UInt8.self))
            return renderer.verticesPool.requestBuffer(from: tState.poolContext,
                                                       withBytes: byteArray,
                                                       checkIfChanged: true)
        }
    }

    private func drawPill(_ pill: PillBackgroundRendererTransientState.PillInfo,
                          renderEncoder: MTLRenderCommandEncoder,
                          tState: PillBackgroundRendererTransientState) {
        let vertexBuffer = vertexBuffer(pill: pill, tState: tState)
        guard let texture = texture(for: pill, tState: tState) else {
            DLog("Failed to create pill texture")
            return
        }
        renderer.draw(with: tState,
                      renderEncoder: renderEncoder,
                      numberOfVertices: 6,
                      numberOfPIUs: 0,
                      vertexBuffers: [NSNumber(value: iTermVertexInputIndexVertices.rawValue): vertexBuffer],
                      fragmentBuffers: [:],
                      textures: [NSNumber(value: iTermTextureIndexPrimary.rawValue): texture])
    }

    private func texture(for pill: PillBackgroundRendererTransientState.PillInfo,
                         tState: PillBackgroundRendererTransientState) -> MTLTexture? {
        let key = PillTextureCacheKey(size: pill.rect.size,
                                      dividerXPositions: pill.dividerXPositions,
                                      foregroundColor: pill.foregroundColor,
                                      backgroundColor: pill.backgroundColor,
                                      pressedSegmentIndex: pill.pressedSegmentIndex)

        if let cached = textureCache[key] {
            return cached
        }

        let image = PillBackgroundGenerator.generatePillImage(
            size: pill.rect.size,
            dividerXPositions: pill.dividerXPositions.map { NSNumber(value: Double($0)) },
            backgroundColor: NSColor(vector: pill.backgroundColor,
                                     colorSpace: tState.configuration.colorSpace),
            foregroundColor: NSColor(vector: pill.foregroundColor,
                                     colorSpace: tState.configuration.colorSpace),
            pressedSegmentIndex: pill.pressedSegmentIndex,
            scale: tState.configuration.scale)

        let texture = renderer.texture(
            fromImage: iTermImageWrapper(image: image),
            context: tState.poolContext,
            pool: texturePool,
            colorSpace: tState.configuration.colorSpace)

        if let texture {
            textureCache[key] = texture
        }
        return texture
    }

    func createTransientState(forCellConfiguration configuration: iTermCellRenderConfiguration,
                              commandBuffer: MTLCommandBuffer) -> iTermMetalRendererTransientState? {
        return renderer.createTransientState(forCellConfiguration: configuration,
                                             commandBuffer: commandBuffer)
    }
}
