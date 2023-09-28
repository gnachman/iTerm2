//
//  BlockRenderer.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 9/27/23.
//

import Foundation
import simd

@objc(iTermBlockRendererTransientState)
class BlockRendererTransientState: iTermMetalCellRendererTransientState {
    @objc var color = vector_float4(0, 0, 0, 0)
    private var rows = [Int]()
    var isEmpty: Bool { rows.isEmpty }
    var count: Int { rows.count }
    @objc(addRow:) func add(row: Int) {
        rows.append(row)
    }

    override func writeDebugInfo(toFolder folder: URL) {
        super.writeDebugInfo(toFolder: folder)
        try? "rows=\(rows), color=\(color)".write(to: folder.appendingPathComponent("state.txt"),
                                                  atomically: false,
                                                  encoding: .utf8)
    }

    func newPIUs() -> Data {
        var pius = [vector_float2]()
        let gridHeight = Int(cellConfiguration.gridSize.height)
        let cellHeight: CGFloat = cellConfiguration.cellSize.height
        let topMargin: CGFloat = margins.top
        for row in rows {
            let y = CGFloat(gridHeight - row - 1) * cellHeight + topMargin
            pius.append(vector_float2(0.0, Float(y)))
        }
        let data = Data(bytes: pius, count: pius.count * MemoryLayout<vector_float2>.stride)
        return data
    }
}

@objc(iTermBlockRenderer)
class BlockRenderer: NSObject, iTermMetalCellRendererProtocol {
    private let colorPool: iTermMetalBufferPool
    private let verticesPool: iTermMetalBufferPool
    private let renderer: iTermMetalCellRenderer
    private let piuPool: iTermMetalMixedSizeBufferPool

    @objc(initWithDevice:)
    init(device: MTLDevice) {
        renderer = iTermMetalCellRenderer(device: device,
                                          vertexFunctionName: "iTermBlockVertexShader",
                                          fragmentFunctionName: "iTermBlockFragmentShader",
                                          blending: iTermMetalBlending(),
                                          piuElementSize: 0,
                                          transientStateClass: BlockRendererTransientState.self)!
        colorPool = iTermMetalBufferPool(device: device, bufferSize: MemoryLayout<vector_float4>.size)
        verticesPool = iTermMetalBufferPool(device: device, bufferSize: MemoryLayout<vector_float2>.size * 6 * 4)
        piuPool = iTermMetalMixedSizeBufferPool(device: device,
                                                capacity: UInt(iTermMetalDriverMaximumNumberOfFramesInFlight + 1),
                                                name: "block PIU")
    }

    override init() {
        fatalError()
    }

    func createTransientStateStat() -> iTermMetalFrameDataStat {
        return .pqCreateBlockTS
    }

    func draw(with frameData: iTermMetalFrameData,
              transientState: iTermMetalCellRendererTransientState) {
        let tState = transientState as! BlockRendererTransientState
        guard !tState.isEmpty else {
            return
        }
        var color = tState.color
        let piuData = tState.newPIUs()
        let piuBuffer = piuPool.requestBuffer(from: tState.poolContext, size: piuData.count)
        tState.pius = piuBuffer
        piuData.copyMemory(to: tState.pius.contents())

        withUnsafePointer(to: &color) {
            let colorBuffer = colorPool.requestBuffer(from: tState.poolContext,
                                                      withBytes: UnsafeRawPointer($0),
                                                      checkIfChanged: true)
            renderer.draw(with: tState,
                          renderEncoder: frameData.renderEncoder,
                          numberOfVertices: 6,
                          numberOfPIUs: tState.count,
                          vertexBuffers: [ NSNumber(value: iTermVertexInputIndexVertices.rawValue): tState.vertexBuffer,
                                           NSNumber(value: iTermVertexInputIndexPerInstanceUniforms.rawValue): tState.pius ],
                          fragmentBuffers: [ NSNumber(value: iTermFragmentBufferIndexMarginColor.rawValue): colorBuffer],
                          textures: [:])
        }
    }

    var rendererDisabled: Bool { false }

    func createTransientState(forCellConfiguration configuration: iTermCellRenderConfiguration, 
                              commandBuffer: MTLCommandBuffer) -> iTermMetalRendererTransientState? {
        let transientState = renderer.createTransientState(forCellConfiguration: configuration,
                                                           commandBuffer: commandBuffer) as! BlockRendererTransientState
        initializeTransientState(transientState)
        return transientState
    }

    func width(_ tState: BlockRendererTransientState) -> CGFloat {
        let margins = tState.margins
        let scale = tState.configuration.scale
        return max(scale, margins.left - 2 * scale)
    }

    func height(_ tState: BlockRendererTransientState) -> CGFloat {
        return tState.cellConfiguration.cellSize.height
    }

    func initializeTransientState(_ tState: BlockRendererTransientState) {
        tState.vertexBuffer = renderer.newQuad(of: NSSize(width: width(tState),
                                                          height: height(tState)),
                                               poolContext: tState.poolContext)
    }
}

extension Data {
    func copyMemory(to dest: UnsafeMutableRawPointer) {
        withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            if let baseAddress = bytes.baseAddress {
                dest.copyMemory(from: baseAddress, byteCount: count)
            }
        }
    }
}
