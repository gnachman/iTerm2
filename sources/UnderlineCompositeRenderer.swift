//
//  UnderlineCompositeRenderer.swift
//  iTerm2SharedARC
//
//  Composites text (T) and underline (U) offscreen textures onto the render target.
//  Text and underlines are rendered to separate offscreen textures so that the
//  compositing shader has access to both the text silhouette and the underlines.
//  This allows it to subtract a smeared version of the text from the underlines,
//  creating breaks where descenders would intersect the underline.
//

import Foundation

@objc(iTermUnderlineCompositeRendererTransientState)
class UnderlineCompositeRendererTransientState: iTermMetalRendererTransientState {
    @objc var textTexture: MTLTexture?
    @objc var underlineTexture: MTLTexture?
    @objc var solidMode: Bool = false

    override var skipRenderer: Bool {
        textTexture == nil || underlineTexture == nil
    }
}

@objc(iTermUnderlineCompositeRenderer)
class UnderlineCompositeRenderer: NSObject, iTermMetalRendererProtocol {
    private let metalRenderer: iTermMetalRenderer
    private let scalePool: iTermMetalBufferPool
    private let solidModePool: iTermMetalBufferPool
    @objc var enabled = false

    @objc(initWithDevice:)
    init(device: MTLDevice) {
        metalRenderer = iTermMetalRenderer(
            device: device,
            vertexFunctionName: "iTermUnderlineCompositeVertexShader",
            fragmentFunctionName: "iTermUnderlineCompositeFragmentShader",
            blending: iTermMetalBlending.compositeSourceOver(),
            transientStateClass: UnderlineCompositeRendererTransientState.self)!
        scalePool = iTermMetalBufferPool(device: device, bufferSize: MemoryLayout<Float>.size)
        solidModePool = iTermMetalBufferPool(device: device, bufferSize: MemoryLayout<Int32>.size)
    }

    override init() {
        it_fatalError()
    }

    func createTransientStateStat() -> iTermMetalFrameDataStat {
        return .pqCreateUnderlineCompositeTS
    }

    var rendererDisabled: Bool { false }

    func createTransientState(for configuration: iTermRenderConfiguration,
                              commandBuffer: MTLCommandBuffer) -> iTermMetalRendererTransientState? {
        guard enabled else { return nil }
        let tState = metalRenderer.createTransientState(
            for: configuration,
            commandBuffer: commandBuffer) as! UnderlineCompositeRendererTransientState
        tState.vertexBuffer = metalRenderer.newFlippedQuad(
            of: NSSize(width: CGFloat(tState.configuration.viewportSize.x),
                       height: CGFloat(tState.configuration.viewportSize.y)),
            poolContext: tState.poolContext)
        return tState
    }

    func draw(with frameData: iTermMetalFrameData,
              transientState: iTermMetalRendererTransientState) {
        guard let tState = transientState as? UnderlineCompositeRendererTransientState,
              let textTexture = tState.textTexture,
              let underlineTexture = tState.underlineTexture,
              let renderEncoder = frameData.renderEncoder else {
            return
        }

        var scale = Float(tState.configuration.scale)
        let scaleBuffer = withUnsafePointer(to: &scale) { ptr in
            scalePool.requestBuffer(from: tState.poolContext,
                                     withBytes: UnsafeRawPointer(ptr),
                                     checkIfChanged: true)
        }

        var solidMode: Int32 = tState.solidMode ? 1 : 0
        let solidModeBuffer = withUnsafePointer(to: &solidMode) { ptr in
            solidModePool.requestBuffer(from: tState.poolContext,
                                         withBytes: UnsafeRawPointer(ptr),
                                         checkIfChanged: true)
        }

        metalRenderer.draw(with: tState,
                           renderEncoder: renderEncoder,
                           numberOfVertices: 6,
                           numberOfPIUs: 0,
                           vertexBuffers: [
                               NSNumber(value: iTermVertexInputIndexVertices.rawValue): tState.vertexBuffer
                           ],
                           fragmentBuffers: [
                               NSNumber(value: 0): scaleBuffer,
                               NSNumber(value: 1): solidModeBuffer,
                           ],
                           textures: [
                               NSNumber(value: iTermTextureIndexPrimary.rawValue): textTexture,
                               NSNumber(value: iTermTextureIndexBackground.rawValue): underlineTexture
                           ])
    }
}
