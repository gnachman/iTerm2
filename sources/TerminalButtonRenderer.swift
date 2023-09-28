//
//  TerminalButtonRenderer.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/27/23.
//

import Foundation

@available(macOS 11, *)
@objc(iTermTerminalButtonRendererTransientState)
class TerminalButtonRendererTransientState: iTermMetalCellRendererTransientState {
    fileprivate struct Button: CustomDebugStringConvertible {
        var debugDescription: String {
            "button=\(terminalButton) line=\(line)"
        }
        var terminalButton: TerminalButton
        var line: Int
        var foregroundColor: vector_float4
        var backgroundColor: vector_float4
    }
    fileprivate var buttons = [Button]()

    @objc(addButton:onScreenLine:foregroundColor:backgroundColor:)
    func add(terminalButton: TerminalButton,
             line: Int,
             foregroundColor: vector_float4,
             backgroundColor: vector_float4) {
        buttons.append(Button(terminalButton: terminalButton,
                              line: line,
                              foregroundColor:foregroundColor,
                              backgroundColor:backgroundColor))
    }

    override func writeDebugInfo(toFolder folder: URL) {
        super.writeDebugInfo(toFolder: folder)
        let s = "buttons=\(buttons.map { $0.debugDescription })"
        try? s.write(to: folder.appendingPathComponent("state.txt"), atomically: false, encoding: .utf8)
    }
}

@available(macOS 11, *)
@objc(iTermTerminalButtonRenderer)
class TerminalButtonRenderer: NSObject, iTermMetalCellRendererProtocol {
    private let metalRenderer: iTermMetalCellRenderer
    private struct TextureKey: Hashable, Equatable {
        var foregroundColor: vector_float4
        var backgroundColor: vector_float4
        var buttonClassName: String
        var selected: Bool
    }
    private var textureCache: [TextureKey: MTLTexture] = [:]
    private var texturePool = iTermTexturePool()

    @objc(initWithDevice:)
    init(device: MTLDevice) {
        metalRenderer = iTermMetalCellRenderer(
            device: device,
            vertexFunctionName: "iTermTerminalButtonVertexShader",
            fragmentFunctionName: "iTermTerminalButtonFragmentShader",
            blending: iTermMetalBlending(),
            piuElementSize: 0,
            transientStateClass: TerminalButtonRendererTransientState.self)!
    }

    var rendererDisabled: Bool { false }

    func createTransientStateStat() -> iTermMetalFrameDataStat {
        .pqCreateButtonsTS
    }
    
    func draw(with frameData: iTermMetalFrameData,
              transientState: iTermMetalCellRendererTransientState) {
        let tState = transientState as! TerminalButtonRendererTransientState
        var x = CGFloat(tState.configuration.viewportSize.x) - tState.margins.right
        for button in tState.buttons {
            drawButton(button,
                       x: &x,
                       renderEncoder: frameData.renderEncoder, 
                       tState:tState)
        }
    }
    
    private func vertexBuffer(button: TerminalButtonRendererTransientState.Button,
                              x: inout CGFloat,
                              cellHeight: CGFloat,
                              scale: CGFloat,
                              viewportSize: vector_uint2,
                              topInset: CGFloat,
                              context: iTermMetalBufferPoolContext) -> MTLBuffer {
        x -= button.terminalButton.width * scale
        let textureFrame = CGRect(x: 0, y: 0, width: 1, height: 1)
        let frame = NSRect(x: x,
                           y: CGFloat(button.line) * cellHeight,
                           width: button.terminalButton.width * scale,
                           height: button.terminalButton.height * scale)
        var quad = CGRect(x: frame.minX,
                          y: topInset + frame.minY,
                          width: frame.width,
                          height: frame.height)
        quad.origin.y = CGFloat(viewportSize.y) - quad.minY - quad.size.height
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
        print(vertices.map { $0.debugDescription })
        x -= 4 * scale
        return vertices.withUnsafeBytes { pointer in
            let byteArray = Array(pointer.bindMemory(to: UInt8.self))
            return metalRenderer.verticesPool.requestBuffer(from: context,
                                                            withBytes: byteArray,
                                                            checkIfChanged: true)
        }
    }

    private func drawButton(_ button: TerminalButtonRendererTransientState.Button,
                            x: inout CGFloat,
                            renderEncoder: MTLRenderCommandEncoder,
                            tState:TerminalButtonRendererTransientState) {
        let vertexBuffer = vertexBuffer(
            button: button,
            x: &x,
            cellHeight: tState.cellConfiguration.cellSize.height,
            scale: tState.configuration.scale,
            viewportSize: tState.configuration.viewportSize,
            topInset: tState.configuration.extraMargins.top,
            context: tState.poolContext)
        let texture = texture(for: button, tState: tState)
        guard let texture else {
            DLog("Failed ot create texture")
            return
        }
        metalRenderer.draw(with: tState,
                           renderEncoder: renderEncoder,
                           numberOfVertices: 6,
                           numberOfPIUs: 0,
                           vertexBuffers: [ NSNumber(value: iTermVertexInputIndexVertices.rawValue): vertexBuffer ],
                           fragmentBuffers: [:],
                           textures: [ NSNumber(value: iTermTextureIndexPrimary.rawValue): texture])
    }

    private func texture(for button: TerminalButtonRendererTransientState.Button,
                         tState: TerminalButtonRendererTransientState) -> MTLTexture? {
        let key = TextureKey(foregroundColor: button.foregroundColor,
                             backgroundColor: button.backgroundColor,
                             buttonClassName: String(describing: type(of: button.terminalButton)),
                             selected: button.terminalButton.selected)
        if let texture = textureCache[key] {
            return texture
        }
        let image = button.terminalButton.image(
            backgroundColor: NSColor(
                vector: button.backgroundColor,
                colorSpace: tState.configuration.colorSpace),
            foregroundColor: NSColor(
                vector: button.foregroundColor,
                colorSpace: tState.configuration.colorSpace),
            cellHeight: tState.cellConfiguration.cellSize.height * tState.configuration.scale)
        let texture = metalRenderer.texture(
            fromImage: iTermImageWrapper(image: image),
            context: tState.poolContext,
            pool: texturePool,
            colorSpace: tState.configuration.colorSpace)
        textureCache[key] = texture
        return texture
    }

    func createTransientState(forCellConfiguration configuration: iTermCellRenderConfiguration, commandBuffer: MTLCommandBuffer) -> iTermMetalRendererTransientState? {
        let tState = metalRenderer.createTransientState(forCellConfiguration: configuration,
                                                  commandBuffer: commandBuffer)
        return tState
    }
}

extension iTermVertex: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "<Vertex: (\(position.x), \(position.y)) Texture: (\(textureCoordinate.x), \(textureCoordinate.y))>"
    }
}
