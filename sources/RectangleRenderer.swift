//
//  RectangleRenderer.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 3/23/24.
//

import Foundation
import simd

@objc(iTermRectangleRendererTransientState)
class RectangleRendererTransientState: iTermMetalCellRendererTransientState {
    struct Rectangle: CustomDebugStringConvertible {
        var debugDescription: String {
            "rect=\(rect) color=\(color)"
        }
        var rect: VT100GridRect
        var insets: NSEdgeInsets
        var color: vector_float4
    }

    private(set) var rectangles = [Rectangle]()
    var isEmpty: Bool { rectangles.isEmpty }
    var count: Int { rectangles.count }
    var clipRect: NSRect?

    @objc(addRectangleWithRect:insets:color:)
    func add(rectangle rect: VT100GridRect, insets: NSEdgeInsets, color: vector_float4) {
        rectangles.append(Rectangle(rect: rect,
                                    insets: insets,
                                    color: color))
    }

    @objc
    func setClipRect(_ rect: NSRect) {
        clipRect = rect;
    }

    @objc(addFrameRectangleWithRect:thickness:insets:color:)
    func add(frameRectangle rect: VT100GridRect, thickness: CGFloat, insets: NSEdgeInsets, color: vector_float4) {
        // Top
        add(rectangle: VT100GridRect(origin: VT100GridCoord(x: rect.origin.x,
                                                            y: rect.origin.y),
                                     size: VT100GridSize(width: rect.size.width,
                                                         height: 0)),
            insets: NSEdgeInsets(top: insets.top, 
                                 left: insets.left,
                                 bottom: -insets.top - thickness,
                                 right: insets.right),
            color: color)

        // Left
        add(rectangle: VT100GridRect(origin: VT100GridCoord(x: rect.origin.x,
                                                            y: rect.origin.y),
                                     size: VT100GridSize(width: 0,
                                                         height: rect.size.height)),
            insets: NSEdgeInsets(top: insets.top + thickness,
                                 left: insets.left,
                                 bottom: insets.bottom,
                                 right: -insets.left - thickness),
            color: color)

        // Bottom
        add(rectangle: VT100GridRect(origin: VT100GridCoord(x: rect.origin.x,
                                                            y: rect.origin.y + rect.size.height),
                                     size: VT100GridSize(width: rect.size.width,
                                                         height: 0)),
            insets: NSEdgeInsets(top: -insets.bottom,
                                 left: insets.left,
                                 bottom: insets.bottom - thickness,
                                 right: insets.right),
            color: color)


        // Right
        add(rectangle: VT100GridRect(origin: VT100GridCoord(x: rect.origin.x + rect.size.width,
                                                            y: rect.origin.y),
                                     size: VT100GridSize(width: 0,
                                                         height: rect.size.height)),
            insets: NSEdgeInsets(top: insets.top,
                                 left: -insets.right,
                                 bottom: insets.bottom - thickness,
                                 right: insets.right - thickness),
            color: color)
    }

    override func writeDebugInfo(toFolder folder: URL) {
        super.writeDebugInfo(toFolder: folder)
        try? "rects=\(rectangles)".write(to: folder.appendingPathComponent("state.txt"),
                                         atomically: false,
                                         encoding: .utf8)
    }
}

@objc(iTermRectangleRenderer)
class RectangleRenderer: NSObject, iTermMetalCellRendererProtocol {
    private let renderer: iTermMetalCellRenderer
    private let colorPool: iTermMetalBufferPool

    @objc(initWithDevice:)
    init(device: MTLDevice) {
        renderer = iTermMetalCellRenderer(device: device,
                                          vertexFunctionName: "iTermRectangleVertexShader",
                                          fragmentFunctionName: "iTermRectangleFragmentShader",
                                          blending: iTermMetalBlending(),
                                          piuElementSize: 1,
                                          transientStateClass: RectangleRendererTransientState.self)!
        colorPool = iTermMetalBufferPool(device: device, bufferSize: MemoryLayout<vector_float4>.size)
    }

    override init() {
        fatalError()
    }

    func createTransientStateStat() -> iTermMetalFrameDataStat {
        return .pqCreateRectangleTS
    }

    private func quad(rectangle: RectangleRendererTransientState.Rectangle,
                      cellConfiguration: iTermCellRenderConfiguration,
                      margins: NSEdgeInsets,
                      scale: CGFloat,
                      viewportSize: vector_uint2) -> CGRect {
        let cellHeight: CGFloat = cellConfiguration.cellSize.height
        let cellWidth = cellConfiguration.cellSize.width

        var scaledInsets = rectangle.insets
        scaledInsets.top *= scale
        scaledInsets.left *= scale
        scaledInsets.bottom *= scale
        scaledInsets.right *= scale

        let left = margins.left + CGFloat(rectangle.rect.origin.x) * cellWidth + scaledInsets.left
        let right = margins.left + CGFloat(rectangle.rect.origin.x + rectangle.rect.size.width) * cellWidth - scaledInsets.right
        let top = margins.bottom + CGFloat(rectangle.rect.origin.y) * cellHeight + scaledInsets.top
        let bottom = margins.bottom + CGFloat(rectangle.rect.origin.y + rectangle.rect.size.height) * cellHeight - scaledInsets.bottom

        let topLeftFrame = NSRect(x: left,
                                  y: top,
                                  width: right - left,
                                  height: bottom - top)

        let frame = NSRect(x: topLeftFrame.minX,
                           y: CGFloat(viewportSize.y) - topLeftFrame.maxY,
                           width: topLeftFrame.width,
                           height: topLeftFrame.height)

        return CGRect(x: frame.minX,
                      y: frame.minY,
                      width: frame.width,
                      height: frame.height)
    }

    private func vertices(quad: CGRect, textureFrame: CGRect) -> [iTermVertex] {
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
        return vertices
    }

    private func vertexBuffer(rectangle: RectangleRendererTransientState.Rectangle,
                              cellConfiguration: iTermCellRenderConfiguration,
                              margins: NSEdgeInsets,
                              scale: CGFloat,
                              viewportSize: vector_uint2,
                              bottomInset: CGFloat,
                              clip: NSRect?,
                              context: iTermMetalBufferPoolContext) -> (MTLBuffer, Int)? {
        let quad = self.quad(rectangle: rectangle,
                             cellConfiguration: cellConfiguration,
                             margins: margins,
                             scale: scale,
                             viewportSize: viewportSize)
        let clipped = if let clip {
            quad.intersection(clip)
        } else {
            quad
        }
        if quad.width == 0 || quad.height == 0 {
            return nil
        }
        let textureFrame = CGRect(x: 0, y: 0, width: 1, height: 1)
        let vertices = self.vertices(quad: clipped, textureFrame: textureFrame)
        return vertices.withUnsafeBytes { pointer in
            let byteArray = Array(pointer.bindMemory(to: UInt8.self))
            return (renderer.verticesPool.requestBuffer(from: context,
                                                        withBytes: byteArray,
                                                        checkIfChanged: true), vertices.count)
        }
    }

    func draw(with frameData: iTermMetalFrameData, transientState: iTermMetalCellRendererTransientState) {
        let tState = transientState as! RectangleRendererTransientState
        guard !tState.isEmpty else {
            return
        }
        for rect in tState.rectangles {
            let tuple = vertexBuffer(rectangle: rect,
                                     cellConfiguration: tState.cellConfiguration,
                                     margins: tState.margins,
                                     scale: tState.configuration.scale,
                                     viewportSize: tState.configuration.viewportSize,
                                     bottomInset: tState.margins.top,
                                     clip: tState.clipRect,
                                     context: tState.poolContext)
            guard let tuple else {
                continue
            }
            let (vertexBuffer, numVertices) = tuple
            var color = rect.color
            withUnsafePointer(to: &color) {
                let colorBuffer = colorPool.requestBuffer(from: tState.poolContext,
                                                          withBytes: UnsafeRawPointer($0),
                                                          checkIfChanged: true)
                renderer.draw(with: tState,
                              renderEncoder: frameData.renderEncoder,
                              numberOfVertices: numVertices,
                              numberOfPIUs: 0,
                              vertexBuffers: [ NSNumber(value: iTermVertexInputIndexVertices.rawValue): vertexBuffer,
                                               NSNumber(value: iTermVertexColorArray.rawValue): colorBuffer ],
                              fragmentBuffers: [:],
                              textures: [:])
            }
        }
    }

    var rendererDisabled: Bool { false }

    func createTransientState(forCellConfiguration configuration: iTermCellRenderConfiguration,
                              commandBuffer: MTLCommandBuffer) -> iTermMetalRendererTransientState? {
        let transientState = renderer.createTransientState(forCellConfiguration: configuration,
                                                           commandBuffer: commandBuffer) as! RectangleRendererTransientState
        initializeTransientState(transientState)
        return transientState
    }

    func width(_ tState: RectangleRendererTransientState) -> CGFloat {
        let margins = tState.margins
        let scale = tState.configuration.scale
        return max(scale, margins.left - 2 * scale)
    }

    func height(_ tState: RectangleRendererTransientState) -> CGFloat {
        return tState.cellConfiguration.cellSize.height
    }

    func initializeTransientState(_ tState: RectangleRendererTransientState) {
        tState.vertexBuffer = renderer.newQuad(of: NSSize(width: width(tState),
                                                          height: height(tState)),
                                               poolContext: tState.poolContext)
    }
}
